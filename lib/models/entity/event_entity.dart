import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';

import '../ai_theme.dart';
import 'photo_entity.dart';
import '../event.dart';
import '../vo/photo.dart';
import '../../utils/event/event_festival_rules.dart';
import '../../utils/event/event_scenario_rules.dart';

part 'event_entity.g.dart';

@Collection()
class EventEntity {
  Id id = Isar.autoIncrement;

  // 📅 事件基本信息
  late String title; // 事件标题，默认为日期（如 "8月15日-8月18日"）
  late int startTime; // 开始时间戳 (毫秒)
  late int endTime; // 结束时间戳 (毫秒)

  // 📍 聚类中心点坐标 (可能为空，如果所有照片都没有GPS)
  double? avgLatitude;
  double? avgLongitude;

  // 🏙️ 地理位置信息 (从高德解析)
  String? city; // 城市名称（如 "青岛市"）
  String? province; // 省份（如 "山东省"）

  // 📸 关联的照片
  List<int> photoIds = []; // 关联的 PhotoEntity 的 id 列表

  // 🖼️ 封面图
  int? coverPhotoId; // 封面图的 PhotoEntity id (智能选图：最高 joyScore)

  // 🏷️ 标签和主题
  List<String> tags = []; // 聚合的标签（从照片 AI 标签统计得出）

  // 📊 统计信息
  int photoCount = 0; // 照片数量（冗余字段，方便查询）

  // 😊 AI 智能增强字段
  double? joyScore; // 事件平均欢乐值 (0.0 - 1.0)
  double? avgHappyScore;
  double? avgCalmScore;
  double? avgNostalgicScore;
  double? avgLivelyScore;
  String? dominantEmotion;
  double? emotionDiversity;
  List<String>? aiThemes; // AI 生成的标题列表（本地规则：1个，LLM：3-5个）
  bool isLlmGenerated = false; // 标记当前标题是否由 LLM 生成
  int analyzedPhotoCount = 0; // 已分析照片数量（进度追踪）
  bool isFestivalEvent = false;
  String? festivalName;
  double? festivalScore;

  // 🎨 季节推导 (根据月份自动计算)
  String get season {
    final date = DateTime.fromMillisecondsSinceEpoch(startTime);
    final month = date.month;
    if (month >= 3 && month <= 5) return '春天';
    if (month >= 6 && month <= 8) return '夏天';
    if (month >= 9 && month <= 11) return '秋天';
    return '冬天';
  }

  // 📅 年份
  int get year {
    final date = DateTime.fromMillisecondsSinceEpoch(startTime);
    return date.year;
  }

  // 🌆 位置描述（优先使用 city，如果为空则返回 "未知地点"）
  String get location => city ?? province ?? '未知地点';

  // 📆 格式化日期范围
  String get dateRangeText {
    final start = DateTime.fromMillisecondsSinceEpoch(startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(endTime);
    final startStr = '${start.month}月${start.day}日';
    final endStr = '${end.month}月${end.day}日';

    if (start.month == end.month && start.day == end.day) {
      return startStr;
    }
    return '$startStr - $endStr';
  }

  // 🔄 转换为 UI 层的 Event 模型
  Future<Event> toUIModel(Isar isar) async {
    // 1. 根据 photoIds 查询出所有照片
    final photoEntities = await isar
        .collection<PhotoEntity>()
        .where()
        .anyOf(photoIds, (q, id) => q.idEqualTo(id))
        .sortByTimestamp() // 按时间顺序排列
        .findAll();

    // 2. 转换为 UI 层的 Photo 对象（优先使用 assetId 解析当前可用路径）
    final photos = <Photo>[];
    for (final entity in photoEntities) {
      final resolvedPath = await _resolvePhotoPath(entity);
      photos.add(
        Photo(
          id: entity.assetId, // 使用 assetId 作为 Photo 的 id
          path: resolvedPath,
          dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
          tags: entity.aiTags ?? [],
          location: entity.city ?? entity.province,
        ),
      );
    }

    // 3. 构造 Event 对象
    final themes = _buildAiThemes();

    // 适配旧数据：实时使用规则引擎生成最新标签，覆盖存储的旧标签（topN词频）
    final advancedTags = EventScenarioRules.generateAdvancedTags(photoEntities);
    final festivalTags = EventFestivalRules.buildFestivalTags(
      isFestivalEvent: isFestivalEvent,
      festivalName: festivalName,
    );
    final mergedTags = <String>{...festivalTags, ...advancedTags}.toList();

    return Event(
      id: id.toString(),
      title: title,
      season: season,
      year: year,
      location: location,
      startDate: DateTime.fromMillisecondsSinceEpoch(startTime),
      endDate: DateTime.fromMillisecondsSinceEpoch(endTime),
      photos: photos,
      tags: mergedTags,
      aiThemes: themes,
      analyzedPhotoCount: analyzedPhotoCount,
      isFestivalEvent: isFestivalEvent,
      festivalName: festivalName,
    );
  }

  Future<String> _resolvePhotoPath(PhotoEntity entity) async {
    if (entity.path.isNotEmpty && File(entity.path).existsSync()) {
      return entity.path;
    }
    final asset = await AssetEntity.fromId(entity.assetId);
    final file = await asset?.file;
    return file?.path ?? entity.path;
  }

  List<AITheme> _buildAiThemes() {
    final sourceTitles = <String>[];

    if (aiThemes != null && aiThemes!.isNotEmpty) {
      sourceTitles.addAll(aiThemes!);
    }

    if (sourceTitles.isEmpty) {
      sourceTitles.addAll(tags.take(3).map((tag) => '$tag时光'));
    }

    if (sourceTitles.isEmpty) {
      sourceTitles.add('$location的回忆');
    }

    return sourceTitles.asMap().entries.map((entry) {
      final title = entry.value;
      return AITheme(
        id: 'theme_${id}_${entry.key}',
        emoji: _inferEmoji(title),
        title: title,
        subtitle: _buildSubtitle(title),
      );
    }).toList();
  }

  String _inferEmoji(String title) {
    if (title.contains('海') || title.contains('沙滩')) return '🌊';
    if (title.contains('山')) return '⛰️';
    if (title.contains('花')) return '🌸';
    if (title.contains('美食') || title.contains('吃')) return '🍜';
    if (title.contains('猫') || title.contains('狗') || title.contains('宠物')) {
      return '🐾';
    }
    if (title.contains('夜') || title.contains('星')) return '🌃';
    return '📸';
  }

  String _buildSubtitle(String title) {
    if (title.contains('回忆') || title.contains('记忆')) {
      return '把这一刻写成故事';
    }

    if (title.contains('时光')) {
      return '用第一人称记录当时的心情';
    }

    return '$title，值得再次回看';
  }

  // 📊 从照片列表生成事件的工厂方法
  static EventEntity fromPhotos(
    List<PhotoEntity> photos, {
    FestivalMatchResult? festivalMatch,
  }) {
    if (photos.isEmpty) {
      throw ArgumentError('Cannot create event from empty photo list');
    }

    // 按时间排序
    photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final event = EventEntity()
      ..startTime = photos.first.timestamp
      ..endTime = photos.last.timestamp
      ..photoIds = photos.map((p) => p.id).toList()
      ..photoCount = photos.length
      ..coverPhotoId = photos.first.id;

    final resolvedFestivalMatch =
        festivalMatch ?? EventFestivalRules.matchCluster(photos);
    event.isFestivalEvent = resolvedFestivalMatch.isFestivalEvent;
    event.festivalName = resolvedFestivalMatch.festivalName;
    event.festivalScore = resolvedFestivalMatch.festivalScore;

    // 计算中心坐标
    final photosWithGPS = photos
        .where((p) => p.latitude != null && p.longitude != null)
        .toList();
    if (photosWithGPS.isNotEmpty) {
      event.avgLatitude =
          photosWithGPS.map((p) => p.latitude!).reduce((a, b) => a + b) /
          photosWithGPS.length;
      event.avgLongitude =
          photosWithGPS.map((p) => p.longitude!).reduce((a, b) => a + b) /
          photosWithGPS.length;
    }

    // 生成高级场景标签（规则引擎推导，语义更丰富）
    event.tags = {
      ...EventFestivalRules.buildFestivalTags(
        isFestivalEvent: event.isFestivalEvent,
        festivalName: event.festivalName,
      ),
      ...EventScenarioRules.generateAdvancedTags(photos),
    }.toList();

    // 生成默认标题（日期范围）
    final start = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    if (event.isFestivalEvent && event.festivalName != null) {
      event.title = '${event.festivalName}回忆';
    } else if (start.month == end.month && start.day == end.day) {
      event.title = '${start.month}月${start.day}日';
    } else {
      event.title = '${start.month}月${start.day}日 - ${end.month}月${end.day}日';
    }

    return event;
  }
}
