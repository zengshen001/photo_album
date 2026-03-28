import 'package:isar/isar.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../utils/event/event_cluster_helper.dart';
import '../../utils/event/event_match_helper.dart';
import '../../utils/event/event_festival_rules.dart';

class EventClusteringExecution {
  final int photoCount;
  final int initialClusterCount;
  final int mergedCount;
  final int finalClusterCount;
  final Set<int> affectedEventIds;
  final int matchedCount;
  final int newCount;
  final int retainedUnmatchedOldCount;
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

class EventClusteringService {
  const EventClusteringService();

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

  Future<List<PhotoEntity>> _loadPhotosForClustering(Isar isar) {
    return isar
        .collection<PhotoEntity>()
        .where()
        .sortByTimestampDesc()
        .findAll();
  }

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

class _PersistResult {
  final Set<int> affectedEventIds;
  final int matchedCount;
  final int newCount;
  final int retainedUnmatchedOldCount;

  const _PersistResult({
    required this.affectedEventIds,
    required this.matchedCount,
    required this.newCount,
    required this.retainedUnmatchedOldCount,
  });
}

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
