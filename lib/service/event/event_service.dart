import 'package:isar/isar.dart';

import '../../models/entity/event_entity.dart';
import '../../utils/event/event_cluster_helper.dart';
import 'event_clustering_service.dart';
import 'event_location_service.dart';
import 'event_smart_info_service.dart';
import '../photo/photo_service.dart';

class EventService {
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal();

  static const String _amapWebKey = String.fromEnvironment(
    'AMAP_WEB_KEY',
    defaultValue: '',
  );

  // 📊 聚类算法配置（旅游同日增强）
  static const ClusterConfig _clusterConfig = ClusterConfig(
    initialTimeThresholdHours: 4,
    baseDistanceThresholdKm: 12,
    sameCityTimeThresholdHours: 6,
    sameCityDistanceThresholdKm: 20,
    fallbackSameCityDistanceKm: 45,
    sameDayMergeGapHours: 10,
    crossDayMergeGapHours: 18,
    minPhotosPerClusterForMerge: 1,
    enableSameDayTravelMerge: true,
    enableCrossDayTravelMerge: true,
  );

  static const int minPhotosForDisplay = 5;
  static const bool _useIncrementalEventUpdate = true;
  static const int _topTagLimit = 5;

  final EventClusteringService _clusteringService =
      const EventClusteringService();
  late final EventLocationService _locationService = EventLocationService(
    amapWebKey: _amapWebKey,
    minPhotosForDisplay: minPhotosForDisplay,
  );
  late final EventSmartInfoService _smartInfoService = EventSmartInfoService(
    minPhotosForDisplay: minPhotosForDisplay,
    topTagLimit: _topTagLimit,
  );

  static bool shouldResolvePhotoLocation({
    required int eventPhotoCount,
    required bool isLocationProcessed,
    required double? latitude,
    required double? longitude,
  }) {
    return EventLocationService.shouldResolvePhotoLocation(
      eventPhotoCount: eventPhotoCount,
      isLocationProcessed: isLocationProcessed,
      latitude: latitude,
      longitude: longitude,
      minPhotosForDisplay: minPhotosForDisplay,
    );
  }

  bool _isEventVisible(EventEntity event) {
    return event.photoCount >= minPhotosForDisplay;
  }

  /// 运行一次完整的“照片 -> 事件”聚类流程。
  Future<void> runClustering() async {
    final isar = PhotoService().isar;
    final execution = await _clusteringService.run(
      isar: isar,
      clusterConfig: _clusterConfig,
      useIncrementalEventUpdate: _useIncrementalEventUpdate,
    );
    if (execution == null) {
      print("⚠️ 没有照片可以聚类");
      return;
    }

    print("🔍 开始聚类分析，共 ${execution.photoCount} 张照片");
    print(
      "✅ 聚类完成: 初分簇=${execution.initialClusterCount} "
      "合并=${execution.mergedCount} 最终事件=${execution.finalClusterCount}",
    );

    if (execution.incrementalMode) {
      print(
        "💾 事件增量更新完成: 匹配保留=${execution.matchedCount} 新建=${execution.newCount} "
        "保留未匹配旧事件=${execution.retainedUnmatchedOldCount}",
      );
    } else {
      print("💾 事件全量重建完成（回滚模式）");
    }

    await _validateEventPhotoConsistency(execution.affectedEventIds);

    // 只解析受影响事件，避免全量刷地址造成不必要耗时与配额消耗。
    _locationService.resolveEventLocations(
      isar: isar,
      onlyEventIds: execution.affectedEventIds,
    );
    _locationService.resolvePhotoLocationsForVisibleEvents(
      isar: isar,
      onlyEventIds: execution.affectedEventIds,
    );
  }

  /// 轻量一致性校验，用于发现事件写入异常。
  Future<void> _validateEventPhotoConsistency(Set<int> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }

    final isar = PhotoService().isar;
    for (final eventId in eventIds) {
      final event = await isar.collection<EventEntity>().get(eventId);
      if (event == null) {
        continue;
      }
      if (event.photoCount != event.photoIds.length) {
        print(
          "⚠️ 事件一致性异常: id=$eventId photoCount=${event.photoCount} photoIds=${event.photoIds.length}",
        );
      }
    }
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
        .sortByStartTimeDesc()
        .watch(fireImmediately: true)
        .map((events) => events.where(_isEventVisible).toList());
  }

  /// 增量刷新事件的智能信息（封面、标签、标题）。
  Future<void> refreshEventSmartInfo(List<int> eventIds) async {
    final isar = PhotoService().isar;
    await _smartInfoService.refreshEventSmartInfo(
      isar: isar,
      eventIds: eventIds,
    );
  }
}
