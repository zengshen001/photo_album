import 'dart:math';
import 'package:dio/dio.dart';
import 'package:isar/isar.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import 'photo_service.dart';

class EventService {
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal();

  final Dio _dio = Dio();

  // 🔑 你的高德 Web 服务 Key (一定要去申请一个填在这里)
  static const String _amapWebKey = "你的高德Key填在这里";

  // 📊 聚类算法配置
  static const int timeThresholdHours = 3; // 时间间隔阈值（小时）
  static const double distanceThresholdKm = 20.0; // 距离阈值（公里）

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
    final List<List<PhotoEntity>> clusters = [];
    List<PhotoEntity> currentCluster = [photos[0]];

    for (int i = 1; i < photos.length; i++) {
      final prev = photos[i - 1];
      final curr = photos[i];

      // 计算时间间隔（毫秒转小时）
      final timeDiff = (curr.timestamp - prev.timestamp) / (1000 * 60 * 60);

      // 计算地理距离（如果有GPS）
      double? distance;
      if (prev.latitude != null &&
          prev.longitude != null &&
          curr.latitude != null &&
          curr.longitude != null) {
        distance = _calculateDistance(
          prev.latitude!,
          prev.longitude!,
          curr.latitude!,
          curr.longitude!,
        );
      }

      // 判断是否需要切分
      bool shouldSplit = false;

      if (timeDiff > timeThresholdHours) {
        shouldSplit = true;
        print("  ⏱️  时间间隔 ${timeDiff.toStringAsFixed(1)}h > ${timeThresholdHours}h，切分");
      } else if (distance != null && distance > distanceThresholdKm) {
        shouldSplit = true;
        print("  📍 距离 ${distance.toStringAsFixed(1)}km > ${distanceThresholdKm}km，切分");
      }

      if (shouldSplit) {
        // 保存当前聚类，开始新聚类
        clusters.add(currentCluster);
        currentCluster = [curr];
      } else {
        // 继续当前聚类
        currentCluster.add(curr);
      }
    }

    // 添加最后一个聚类
    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    print("✅ 聚类完成，共生成 ${clusters.length} 个事件");

    // 4. 将聚类结果存入数据库
    await isar.writeTxn(() async {
      // 清空旧事件
      await isar.collection<EventEntity>().clear();

      // 插入新事件
      for (final cluster in clusters) {
        final event = EventEntity.fromPhotos(cluster);
        await isar.collection<EventEntity>().put(event);
      }
    });

    print("💾 事件已存入数据库");

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
        // 使用事件中心点调用高德 API
        final response = await _dio.get(
          "https://restapi.amap.com/v3/geocode/regeo",
          queryParameters: {
            "key": _amapWebKey,
            "location": "${event.avgLongitude},${event.avgLatitude}",
            "extensions": "base",
            "radius": 1000,
            "coordsys": "gps", // GPS 坐标
          },
        );

        if (response.statusCode == 200 && response.data['status'] == '1') {
          final regeocode = response.data['regeocode'];
          final addressComponent = regeocode['addressComponent'];

          await isar.writeTxn(() async {
            final e = await isar.collection<EventEntity>().get(event.id);
            if (e != null) {
              // 更新地址信息
              final rawProvince = addressComponent['province'];
              final rawCity = addressComponent['city'];

              e.province = rawProvince is String ? rawProvince : "";

              // 处理直辖市
              if (rawCity is String && rawCity.isNotEmpty) {
                e.city = rawCity;
              } else {
                e.city = e.province;
              }

              // 如果有 city，更新 title 为 "城市 · 日期"
              if (e.city != null && e.city!.isNotEmpty) {
                e.title = "${e.city} · ${e.dateRangeText}";
              }

              await isar.collection<EventEntity>().put(e);
            }
          });

          print("📍 事件地址解析成功: ${event.title} -> ${addressComponent['city'] ?? addressComponent['province']}");
        } else {
          print("⚠️ 高德 API 业务错误: ${response.data['info']}");
        }
      } catch (e) {
        print("❌ 地址解析失败: $e");
      }

      // 延时，避免触发高德 API 限流
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 🔄 递归调用，处理剩余事件
    _resolveEventLocations();
  }

  // 📐 计算两点间的距离（Haversine 公式，单位：公里）
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0; // 地球半径（公里）
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * pi / 180;
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

    return {
      'total': total,
      'withLocation': withLocation,
    };
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
}
