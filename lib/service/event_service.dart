import 'package:geocoding/geocoding.dart';
import 'package:isar/isar.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import '../utils/event_cluster_helper.dart';
import '../utils/location_helper.dart';
import '../utils/smart_title_generator.dart';
import '../service/llm_service.dart';
import 'photo_service.dart';

class EventService {
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal();

  // 📊 聚类算法配置
  static const int timeThresholdHours = 2; // 时间间隔阈值（小时）
  static const double distanceThresholdKm = 1.0; // 距离阈值（公里）

  // 🧮 核心方法：运行时空聚类算法
  Future<void> runClustering() async {
    final isar = PhotoService().isar;

    // 1. 读取所有照片（按时间倒序）
    final allPhotos = await isar
        .collection<PhotoEntity>()
        .where()
        .sortByTimestampDesc()
        .findAll();

    if (allPhotos.isEmpty) {
      print("⚠️ 没有照片可以聚类");
      return;
    }

    print("🔍 开始聚类分析，共 ${allPhotos.length} 张照片");

    // 2. 反转为时间升序（方便按时间顺序处理）
    final photos = allPhotos.reversed.toList();

    // 3. 聚类逻辑
    final clusters = EventClusterHelper.clusterPhotos(
      photos: photos,
      timeThresholdHours: timeThresholdHours,
      distanceThresholdKm: distanceThresholdKm,
    );

    print("✅ 聚类完成，共生成 ${clusters.length} 个事件");

    // 4. 将聚类结果存入数据库并设置 eventId 反向关联
    await isar.writeTxn(() async {
      // 清空旧事件
      await isar.collection<EventEntity>().clear();

      // 插入新事件并更新照片的 eventId
      for (final cluster in clusters) {
        final event = EventEntity.fromPhotos(cluster);
        final eventId = await isar.collection<EventEntity>().put(event);

        // 🔗 关键：将此事件的 ID 写入每张照片的 eventId 字段
        for (final photo in cluster) {
          photo.eventId = eventId;
          await isar.collection<PhotoEntity>().put(photo);
        }
      }
    });

    print("💾 事件已存入数据库，照片关联已建立");

    // 5. 启动地址解析
    _resolveEventLocations();
  }

  // 🌏 后台任务：为事件解析地址（仅解析中心点）
  Future<void> _resolveEventLocations() async {
    final isar = PhotoService().isar;

    // 查询需要解析地址的事件（有GPS但 city 为空）
    final events = await isar
        .collection<EventEntity>()
        .filter()
        .avgLatitudeIsNotNull()
        .cityIsNull()
        .limit(10) // 每次最多处理 10 个事件
        .findAll();

    if (events.isEmpty) {
      print("✅ 所有事件地址已解析完成");
      return;
    }

    print("🌏 开始解析 ${events.length} 个事件地址...");

    for (final event in events) {
      try {
        final placemarks = await placemarkFromCoordinates(
          event.avgLatitude!,
          event.avgLongitude!,
        );
        final locationInfo = LocationHelper.resolveFromPlacemarks(placemarks);
        final province = locationInfo.province;
        final city = locationInfo.city;

        await isar.writeTxn(() async {
          final e = await isar.collection<EventEntity>().get(event.id);
          if (e == null) {
            return;
          }

          e.province = (province != null && province.isNotEmpty)
              ? province
              : null;
          if (city != null && city.isNotEmpty) {
            e.city = city;
          } else {
            e.city = e.province;
          }

          if (e.city != null && e.city!.isNotEmpty) {
            e.title = "${e.city} · ${e.dateRangeText}";
          }

          await isar.collection<EventEntity>().put(e);
        });

        print("📍 事件地址解析成功: ${event.title} -> ${city ?? province ?? '未知地点'}");
      } catch (e) {
        print("❌ 地址解析失败: $e");
      }

      // 延时，避免触发高德 API 限流
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 🔄 递归调用，处理剩余事件
    _resolveEventLocations();
  }

  // 📊 获取事件统计信息
  Future<Map<String, int>> getEventStats() async {
    final isar = PhotoService().isar;
    final total = await isar.collection<EventEntity>().count();
    final withLocation = await isar
        .collection<EventEntity>()
        .filter()
        .cityIsNotNull()
        .count();

    return {'total': total, 'withLocation': withLocation};
  }

  // 🔄 获取事件流（UI 监听用）
  Stream<List<EventEntity>> watchEvents() {
    final isar = PhotoService().isar;
    return isar
        .collection<EventEntity>()
        .where()
        .sortByStartTimeDesc() // 按时间倒序
        .watch(fireImmediately: true);
  }

  // 🧠 核心方法：增量刷新事件的智能信息（混合标题生成）
  // 此方法由 AIService 在分析完一批照片后调用
  Future<void> refreshEventSmartInfo(List<int> eventIds) async {
    if (eventIds.isEmpty) return;

    final isar = PhotoService().isar;

    print("🧠 开始刷新 ${eventIds.length} 个事件的智能信息...");

    for (final eventId in eventIds) {
      try {
        // 1. 获取事件
        final event = await isar.collection<EventEntity>().get(eventId);
        if (event == null) continue;

        // 2. 查询该事件下所有已分析的照片
        final analyzedPhotos = await isar
            .collection<PhotoEntity>()
            .filter()
            .eventIdEqualTo(eventId)
            .isAiAnalyzedEqualTo(true)
            .findAll();

        if (analyzedPhotos.isEmpty) {
          print("  ⚠️ 事件 $eventId 暂无已分析照片，跳过");
          continue;
        }

        // 3. 计算统计数据
        final stats = _calculateEventStats(analyzedPhotos);

        // 4. 计算分析进度
        final progress = SmartTitleGenerator.calculateProgress(
          stats['analyzedCount'] as int,
          event.photoCount,
        );

        // 5. 决定使用哪种标题生成策略
        List<String> generatedTitles;
        bool shouldUseLLM = false;

        if (progress >= 100) {
          // ✅ 分析完成：尝试使用 LLM
          shouldUseLLM = true;

          // 检查是否已经生成过 LLM 标题（避免浪费 API 额度）
          if (event.isLlmGenerated) {
            print("  ℹ️ 事件 $eventId 已有 LLM 标题，跳过重复生成");
            continue;
          }
        }

        await isar.writeTxn(() async {
          final e = await isar.collection<EventEntity>().get(eventId);
          if (e != null) {
            // 更新基础 AI 数据
            e.joyScore = stats['avgJoyScore'];
            e.analyzedPhotoCount = stats['analyzedCount'] as int;
            e.coverPhotoId = stats['bestPhotoId'] as int?;
            e.tags = _extractTopTags(stats, 5);

            if (shouldUseLLM) {
              // 📡 Phase 2: LLM 生成创意标题
              try {
                final topTags = _extractTopTags(stats, 5);

                // 检查是否使用模拟模式（如果 API Key 未配置）
                final llmService = LLMService();
                if (llmService.isApiKeyConfigured) {
                  generatedTitles = await llmService.generateCreativeTitles(
                    e,
                    topTags,
                  );
                } else {
                  print("  ⚠️ LLM API Key 未配置，使用模拟模式");
                  generatedTitles = await llmService.generateCreativeTitlesMock(
                    e,
                    topTags,
                  );
                }

                e.aiThemes = generatedTitles;
                e.isLlmGenerated = true;
                print("  🎨 [LLM] 生成 ${generatedTitles.length} 个创意标题");
              } catch (llmError) {
                print("  ❌ LLM 生成失败: $llmError，回退到本地规则");
                // LLM 失败，回退到本地规则
                generatedTitles = [_generateLocalTitle(e, stats)];
                e.aiThemes = generatedTitles;
                e.isLlmGenerated = false;
              }
            } else {
              // 📋 Phase 1: 本地规则生成
              generatedTitles = [_generateLocalTitle(e, stats)];
              e.aiThemes = generatedTitles;
              e.isLlmGenerated = false;
              print(
                "  🏠 [本地] 生成规则标题: ${generatedTitles.first} (进度: $progress%)",
              );
            }

            // 更新默认显示标题（使用第一个生成的标题）
            if (e.aiThemes != null && e.aiThemes!.isNotEmpty) {
              e.title = e.aiThemes!.first;
            }

            await isar.collection<EventEntity>().put(e);
            print(
              "  ✅ 事件 $eventId 已更新：封面=${e.coverPhotoId} 欢乐=${e.joyScore?.toStringAsFixed(2)} 进度=$progress%",
            );
          }
        });
      } catch (e) {
        print("  ❌ 刷新事件 $eventId 失败: $e");
      }
    }

    print("🎉 智能信息刷新完成");
  }

  // 🏠 生成本地规则标题
  String _generateLocalTitle(EventEntity event, Map<String, dynamic> stats) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final topTag = stats['topTag'] as String?;
    final joyScore = stats['avgJoyScore'] as double?;

    return SmartTitleGenerator.generate(
      date: date,
      city: event.city,
      province: event.province,
      topTag: topTag,
      joyScore: joyScore,
    );
  }

  // 🏷️ 从统计数据中提取前 N 个标签
  List<String> _extractTopTags(Map<String, dynamic> stats, int count) {
    final tagCounts = stats['tagCounts'] as Map<String, int>?;
    if (tagCounts == null || tagCounts.isEmpty) return [];

    final sortedTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedTags.take(count).map((e) => e.key).toList();
  }

  // 📊 计算事件统计数据
  Map<String, dynamic> _calculateEventStats(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      return {
        'analyzedCount': 0,
        'avgJoyScore': null,
        'topTag': null,
        'topTagRatio': 0.0,
        'tagCounts': <String, int>{},
        'bestPhotoId': null,
      };
    }

    // 统计1：已分析照片数量
    final analyzedCount = photos.length;

    // 统计2：平均欢乐值
    final joyScores = photos
        .where((p) => p.joyScore != null)
        .map((p) => p.joyScore!)
        .toList();

    final avgJoyScore = joyScores.isNotEmpty
        ? joyScores.reduce((a, b) => a + b) / joyScores.length
        : null;

    // 统计3：标签频率（找出最高频标签）
    final Map<String, int> tagCounts = {};
    for (final photo in photos) {
      if (photo.aiTags != null) {
        for (final tag in photo.aiTags!) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }

    String? topTag;
    double topTagRatio = 0.0;
    if (tagCounts.isNotEmpty) {
      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topTag = sortedTags.first.key;
      topTagRatio = sortedTags.first.value / analyzedCount;
    }

    // 统计4：最佳照片（最高 joyScore）
    int? bestPhotoId;
    double maxJoy = 0.0;
    for (final photo in photos) {
      if (photo.joyScore != null && photo.joyScore! > maxJoy) {
        maxJoy = photo.joyScore!;
        bestPhotoId = photo.id;
      }
    }

    return {
      'analyzedCount': analyzedCount,
      'avgJoyScore': avgJoyScore,
      'topTag': topTag,
      'topTagRatio': topTagRatio,
      'tagCounts': tagCounts, // 返回完整的标签统计，供 LLM 使用
      'bestPhotoId': bestPhotoId,
    };
  }
}
