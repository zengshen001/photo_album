import 'package:isar/isar.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../utils/event/event_cluster_helper.dart';
import '../../utils/event/event_match_helper.dart';
import '../../utils/event/event_festival_rules.dart';

/// 一次聚类执行的汇总信息（用于日志与后续增量任务）。
class EventClusteringExecution {
  /// 本次参与聚类的照片总数。
  final int photoCount;

  /// 初分簇数量（未做合并/节日后处理前）。
  final int initialClusterCount;

  /// 合并减少的簇数量（初分簇 - 最终簇）。
  final int mergedCount;

  /// 最终事件数量（最终簇数量）。
  final int finalClusterCount;

  /// 本次聚类影响到的事件 ID（新建或被更新）。
  final Set<int> affectedEventIds;

  /// 增量模式：复用旧事件的数量。
  final int matchedCount;

  /// 增量模式：新建事件的数量。
  final int newCount;

  /// 增量模式：未匹配但被判断为“陈旧”的旧事件数量（用于诊断，默认保留）。
  final int retainedUnmatchedOldCount;

  /// 是否启用了增量更新模式。
  final bool incrementalMode;

  const EventClusteringExecution({
    required this.photoCount,
    required this.initialClusterCount,
    required this.mergedCount,
    required this.finalClusterCount,
    required this.affectedEventIds,
    required this.matchedCount,
    required this.newCount,
    required this.retainedUnmatchedOldCount,
    required this.incrementalMode,
  });
}

/// “照片 -> 事件”的聚类执行器。
///
/// 主要职责：
/// 1) 从数据库读取所有照片（按时间排序）
/// 2) 调用 [EventClusterHelper] 进行纯内存聚类，得到簇列表 + 节日匹配
/// 3) 将簇持久化为 [EventEntity]（支持增量更新或全量重建）
/// 4) 将簇内照片的 eventId 回写到 [PhotoEntity]，用于后续增量任务
class EventClusteringService {
  const EventClusteringService();

  /// 执行一次聚类。
  ///
  /// - [clusterConfig]：控制切分/合并阈值与是否启用节日后处理
  /// - [useIncrementalEventUpdate]：true 使用“事件复用+增量更新”，false 走“清库重建”
  Future<EventClusteringExecution?> run({
    required Isar isar,
    required ClusterConfig clusterConfig,
    required bool useIncrementalEventUpdate,
  }) async {
    final allPhotos = await _loadPhotosForClustering(isar);
    if (allPhotos.isEmpty) {
      return null;
    }

    final clusterResult = EventClusterHelper.clusterPhotos(
      photos: allPhotos.reversed.toList(),
      config: clusterConfig,
    );
    final drafts = _buildClusterDrafts(
      clusterResult.clusters,
      clusterResult.festivalMatches,
    );

    final persistResult = useIncrementalEventUpdate
        ? await _persistClustersIncrementally(isar: isar, drafts: drafts)
        : await _persistClustersByFullRebuild(isar: isar, drafts: drafts);

    return EventClusteringExecution(
      photoCount: allPhotos.length,
      initialClusterCount: clusterResult.initialClusterCount,
      mergedCount: clusterResult.mergedCount,
      finalClusterCount: clusterResult.clusters.length,
      affectedEventIds: persistResult.affectedEventIds,
      matchedCount: persistResult.matchedCount,
      newCount: persistResult.newCount,
      retainedUnmatchedOldCount: persistResult.retainedUnmatchedOldCount,
      incrementalMode: useIncrementalEventUpdate,
    );
  }

  /// 读取用于聚类的照片集合（按时间倒序）。
  ///
  /// 注意：下游聚类期望时间升序，因此调用处会反转列表以满足“时间升序”约定。
  Future<List<PhotoEntity>> _loadPhotosForClustering(Isar isar) {
    return isar
        .collection<PhotoEntity>()
        .where()
        .sortByTimestampDesc()
        .findAll();
  }

  /// 将簇列表转换为可持久化的草稿结构（簇照片 + 事件实体）。
  ///
  /// 这里会把节日匹配结果传入 [EventEntity.fromPhotos]，让事件实体写入
  /// isFestivalEvent / festivalName / festivalScore 等字段。
  List<_ClusterDraft> _buildClusterDrafts(
    List<List<PhotoEntity>> clusters,
    List<FestivalMatchResult> festivalMatches,
  ) {
    return clusters
        .asMap()
        .entries
        .map(
          (entry) => _ClusterDraft.fromCluster(
            entry.value,
            festivalMatch: festivalMatches[entry.key],
          ),
        )
        .toList();
  }

  /// 增量持久化：尽量复用旧事件 ID，减少 UI 抖动与历史数据丢失。
  ///
  /// 过程：
  /// - 用 [EventMatchHelper] 计算“新簇事件”与“旧事件”的一对一匹配
  /// - 对每个新簇：若匹配到旧事件则更新旧事件，否则新建事件
  /// - 将簇内照片的 eventId 统一回写
  Future<_PersistResult> _persistClustersIncrementally({
    required Isar isar,
    required List<_ClusterDraft> drafts,
  }) async {
    final oldEvents = await isar.collection<EventEntity>().where().findAll();
    final matchPlan = EventMatchHelper.buildIncrementalMatchPlan(
      oldEvents: oldEvents,
      newEvents: drafts.map((draft) => draft.event).toList(),
    );

    final affectedEventIds = <int>{};
    await isar.writeTxn(() async {
      for (var i = 0; i < drafts.length; i++) {
        final draft = drafts[i];
        final matchedOldEventId = matchPlan.newIndexToOldId[i];
        final eventId = await _upsertDraftEvent(
          isar: isar,
          draft: draft,
          matchedOldEventId: matchedOldEventId,
        );
        affectedEventIds.add(eventId);
        await _relinkDraftPhotosToEvent(
          isar: isar,
          draft: draft,
          eventId: eventId,
        );
      }
    });

    return _PersistResult(
      affectedEventIds: affectedEventIds,
      matchedCount: matchPlan.matchedCount,
      newCount: matchPlan.newCount,
      retainedUnmatchedOldCount: matchPlan.staleOldEventIds.length,
    );
  }

  /// 全量重建：清空 EventEntity 后重新写入全部簇。
  ///
  /// 该模式用于回滚/兜底场景，代价是事件 ID 会完全变化，UI 会有明显抖动。
  Future<_PersistResult> _persistClustersByFullRebuild({
    required Isar isar,
    required List<_ClusterDraft> drafts,
  }) async {
    final affectedEventIds = <int>{};
    await isar.writeTxn(() async {
      await isar.collection<EventEntity>().clear();
      for (final draft in drafts) {
        final eventId = await isar.collection<EventEntity>().put(draft.event);
        affectedEventIds.add(eventId);
        await _relinkDraftPhotosToEvent(
          isar: isar,
          draft: draft,
          eventId: eventId,
        );
      }
    });
    return _PersistResult(
      affectedEventIds: affectedEventIds,
      matchedCount: 0,
      newCount: drafts.length,
      retainedUnmatchedOldCount: 0,
    );
  }

  /// 依据匹配结果对单个簇事件进行 upsert：
  ///
  /// - 未匹配：直接 put 新事件
  /// - 已匹配：读取旧事件并合并字段，再 put 回去（保留旧事件 ID）
  Future<int> _upsertDraftEvent({
    required Isar isar,
    required _ClusterDraft draft,
    required int? matchedOldEventId,
  }) async {
    if (matchedOldEventId == null) {
      return isar.collection<EventEntity>().put(draft.event);
    }

    final existing = await isar.collection<EventEntity>().get(
      matchedOldEventId,
    );
    if (existing == null) {
      return isar.collection<EventEntity>().put(draft.event);
    }

    _mergeEventWithDraft(existing: existing, draft: draft.event);
    return isar.collection<EventEntity>().put(existing);
  }

  /// 将簇内每张照片的 eventId 回写为当前事件 ID。
  ///
  /// 这一步对“增量更新”和后续服务（地址解析、AI 增强等）都很关键。
  Future<void> _relinkDraftPhotosToEvent({
    required Isar isar,
    required _ClusterDraft draft,
    required int eventId,
  }) async {
    for (final photo in draft.photos) {
      photo.eventId = eventId;
      await isar.collection<PhotoEntity>().put(photo);
    }
  }

  /// 将新草稿事件的字段合并进旧事件实体。
  ///
  /// 规则：
  /// - 聚类结构字段（时间范围、照片列表、坐标、封面等）用草稿覆盖
  /// - 节日标记用草稿覆盖
  /// - 如果旧事件已经由 LLM 生成标题，则保留旧标题，否则用草稿标题覆盖
  void _mergeEventWithDraft({
    required EventEntity existing,
    required EventEntity draft,
  }) {
    existing.startTime = draft.startTime;
    existing.endTime = draft.endTime;
    existing.photoIds = draft.photoIds;
    existing.photoCount = draft.photoCount;
    existing.avgLatitude = draft.avgLatitude;
    existing.avgLongitude = draft.avgLongitude;
    existing.tags = draft.tags;
    existing.coverPhotoId = draft.coverPhotoId;
    existing.isFestivalEvent = draft.isFestivalEvent;
    existing.festivalName = draft.festivalName;
    existing.festivalScore = draft.festivalScore;

    if (!existing.isLlmGenerated) {
      existing.title = draft.title;
    }
  }
}

/// 持久化阶段的内部汇总结果。
class _PersistResult {
  /// 本次写入/更新影响到的事件 ID 集合。
  final Set<int> affectedEventIds;

  /// 增量模式：复用旧事件的数量。
  final int matchedCount;

  /// 增量模式：新建事件的数量。
  final int newCount;

  /// 增量模式：未匹配但保留的旧事件数量（用于诊断）。
  final int retainedUnmatchedOldCount;

  const _PersistResult({
    required this.affectedEventIds,
    required this.matchedCount,
    required this.newCount,
    required this.retainedUnmatchedOldCount,
  });
}

/// 聚类流程中的内部草稿结构：将一个簇携带的照片列表与对应 EventEntity 绑定在一起。
class _ClusterDraft {
  final List<PhotoEntity> photos;
  final EventEntity event;

  const _ClusterDraft({required this.photos, required this.event});

  factory _ClusterDraft.fromCluster(
    List<PhotoEntity> cluster, {
    required FestivalMatchResult festivalMatch,
  }) {
    return _ClusterDraft(
      photos: List<PhotoEntity>.from(cluster),
      event: EventEntity.fromPhotos(
        List<PhotoEntity>.from(cluster),
        festivalMatch: festivalMatch,
      ),
    );
  }
}
