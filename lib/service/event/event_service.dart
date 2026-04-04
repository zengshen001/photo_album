import 'dart:async';
import 'dart:developer';

import 'package:isar/isar.dart';

import '../ai/ai_service.dart';
import '../../models/entity/event_entity.dart';
import '../../utils/event/event_cluster_config_catalog.dart';
import '../../utils/event/event_cluster_helper.dart';
import '../../utils/concurrency/concurrency_pool.dart';
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

  // 📊 聚类算法配置（仅改为集中引用，不改变任何默认值）
  static const ClusterConfig _clusterConfig =
      EventClusterConfigCatalog.defaultConfig;

  static const int minPhotosForDisplay = 5;
  static const bool _useIncrementalEventUpdate = true;
  static const int _topTagLimit = 5;
  static final ConcurrencyPool backgroundPool = ConcurrencyPool(
    maxConcurrent: 5,
  );

  final EventClusteringService _clusteringService =
      const EventClusteringService();
  late final EventLocationService _locationService = EventLocationService(
    amapWebKey: _amapWebKey,
    minPhotosForDisplay: minPhotosForDisplay,
    pool: backgroundPool,
  );
  late final EventSmartInfoService _smartInfoService = EventSmartInfoService(
    minPhotosForDisplay: minPhotosForDisplay,
    topTagLimit: _topTagLimit,
    pool: backgroundPool,
  );
  bool _isAiEnhancementRunning = false;
  final Set<int> _pendingAiEventIds = <int>{};

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

  /// 事件是否对 UI 可见。
  ///
  /// 当前策略：照片数达到阈值才展示，避免碎片事件影响体验。
  bool _isEventVisible(EventEntity event) {
    return event.photoCount >= minPhotosForDisplay;
  }

  /// 运行一次完整的“照片 -> 事件”聚类流程。
  ///
  /// 该方法负责把纯聚类结果“落库 + 触发后续任务”：
  /// - 聚类持久化：写入/更新 EventEntity，并给 PhotoEntity 回写 eventId
  /// - 地址解析：仅处理受影响事件（避免全量刷地址）
  /// - AI 增强：后台分析照片并刷新事件智能信息
  Future<void> runClustering() async {
    final isar = PhotoService().isar;
    final execution = await _clusteringService.run(
      isar: isar,
      clusterConfig: _clusterConfig,
      useIncrementalEventUpdate: _useIncrementalEventUpdate,
    );
    if (execution == null) {
      log('没有照片可以聚类', name: 'EventService');
      return;
    }

    log('开始聚类分析，共 ${execution.photoCount} 张照片', name: 'EventService');
    log(
      '聚类完成: 初分簇=${execution.initialClusterCount} '
      '合并=${execution.mergedCount} 最终事件=${execution.finalClusterCount}',
      name: 'EventService',
    );

    if (execution.incrementalMode) {
      log(
        '事件增量更新完成: 匹配保留=${execution.matchedCount} 新建=${execution.newCount} '
        '保留未匹配旧事件=${execution.retainedUnmatchedOldCount}',
        name: 'EventService',
      );
    } else {
      log('事件全量重建完成（回滚模式）', name: 'EventService');
    }

    await _validateEventPhotoConsistency(execution.affectedEventIds);

    // 只解析受影响事件，避免全量刷地址造成不必要耗时与配额消耗。
    unawaited(
      _locationService.resolveEventLocations(
        isar: isar,
        onlyEventIds: execution.affectedEventIds,
      ),
    );
    unawaited(
      _locationService.resolvePhotoLocationsForVisibleEvents(
        isar: isar,
        onlyEventIds: execution.affectedEventIds,
      ),
    );

    unawaited(_scheduleAiEnhancement(execution.affectedEventIds));
  }

  Future<void> resumePostProcessing({Set<int>? onlyEventIds}) async {
    final isar = PhotoService().isar;
    final targetEventIds = onlyEventIds ?? await _loadVisibleEventIds(isar);
    if (targetEventIds.isEmpty) {
      return;
    }

    unawaited(
      _locationService.resolveEventLocations(
        isar: isar,
        onlyEventIds: targetEventIds,
      ),
    );
    unawaited(
      _locationService.resolvePhotoLocationsForVisibleEvents(
        isar: isar,
        onlyEventIds: targetEventIds,
      ),
    );
    unawaited(_scheduleAiEnhancement(targetEventIds));
  }

  Future<Set<int>> _loadVisibleEventIds(Isar isar) async {
    final events = await isar.collection<EventEntity>().where().findAll();
    return events.where(_isEventVisible).map((e) => e.id).toSet();
  }

  /// 轻量一致性校验，用于发现事件写入异常。
  ///
  /// 典型问题：event.photoCount 与 photoIds.length 不一致，可能来自增量更新或回写失败。
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
        log(
          '事件一致性异常: id=$eventId photoCount=${event.photoCount} photoIds=${event.photoIds.length}',
          name: 'EventService',
        );
      }
    }
  }

  /// 启动（或合并）后台 AI 增强任务。
  ///
  /// - 同时只允许一个任务运行，新的 eventIds 会被合并到队列里
  /// - 每轮取出队列快照进行处理，处理完再检查是否有新增任务
  Future<void> _scheduleAiEnhancement(Set<int> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }

    _pendingAiEventIds.addAll(eventIds);
    if (_isAiEnhancementRunning) {
      log(
        'AI 增强任务已在运行，合并新的事件队列: ${_pendingAiEventIds.length}',
        name: 'EventService',
      );
      return;
    }

    _isAiEnhancementRunning = true;
    try {
      while (_pendingAiEventIds.isNotEmpty) {
        final batchEventIds = Set<int>.from(_pendingAiEventIds);
        _pendingAiEventIds.clear();

        log('启动后台 AI 增强，事件数: ${batchEventIds.length}', name: 'EventService');
        await AIService().analyzePhotosInBackground(eventIds: batchEventIds);
        await refreshEventSmartInfo(batchEventIds.toList());
      }
    } catch (e, stackTrace) {
      log(
        '后台 AI 增强失败: $e',
        name: 'EventService',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _isAiEnhancementRunning = false;
    }
  }

  /// 获取事件统计信息（用于调试/观测）。
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

  Future<Map<String, dynamic>> getPostProcessingStats({
    Set<int>? onlyEventIds,
  }) async {
    final isar = PhotoService().isar;
    final ai = await AIService().getAnalysisProgress();
    final location = await _locationService.getLocationProgress(
      isar: isar,
      onlyEventIds: onlyEventIds,
    );
    return {'ai': ai, 'location': location};
  }

  /// 获取事件流（UI 监听用）。
  ///
  /// 返回按 startTime 倒序的事件列表，并过滤掉低于展示阈值的碎片事件。
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
