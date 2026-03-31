import '../../models/entity/event_entity.dart';
import '../../models/vo/event_match_candidate.dart';
import 'event_cluster_helper.dart';

/// 增量匹配的配置项。
///
/// 增量聚类的目标是：当用户重复扫描/增量同步照片时，尽量让“同一事件”复用同一个 EventEntity.id，
/// 这样 UI 不会频繁抖动（事件卡片不至于每次都变成新事件）。
class EventMatchConfig {
  /// 候选匹配的最低综合分，低于该值直接忽略。
  final double minScore;

  /// 允许作为候选的时间间隔上限（小时），超过则认为不可能是同一事件。
  final int candidateGapHours;

  /// 空间距离阈值（公里），用于把事件中心点距离映射为一个 0~1 的分数。
  final double distanceThresholdKm;

  const EventMatchConfig({
    this.minScore = 0.6,
    this.candidateGapHours = 24,
    this.distanceThresholdKm = 5,
  });
}

/// 增量匹配的输出计划。
///
/// - [newIndexToOldId]：新事件（按数组下标）复用到的旧事件 ID
/// - [staleOldEventIds]：未匹配但与新事件有照片重叠的旧事件（用于诊断抖动）
/// - [matchedCount]/[newCount]：统计信息
class EventMatchPlan {
  /// 新事件下标 -> 旧事件 ID。
  ///
  /// 示例：`newIndexToOldId[2] = 15` 表示第 3 个新事件复用旧事件 15。
  final Map<int, int> newIndexToOldId;

  /// 本轮未匹配但与聚类照片有重叠的旧事件。
  ///
  /// 用于诊断匹配抖动，当前流程默认保留，不直接删除。
  final List<int> staleOldEventIds;
  final int matchedCount;
  final int newCount;

  const EventMatchPlan({
    required this.newIndexToOldId,
    required this.staleOldEventIds,
    required this.matchedCount,
    required this.newCount,
  });
}

/// 增量匹配工具：在“新聚类结果”与“旧事件列表”之间建立稳定映射。
///
/// 思路（贪心一对一匹配）：
/// 1) 为每个 (new, old) 计算综合分（时间相近 + 空间相近 + 照片重叠）
/// 2) 过滤掉明显不可能的候选（无照片重叠 / 时间差过大 / 分数过低）
/// 3) 将候选按分数降序排序，依次尝试匹配，保证 old 与 new 都只被使用一次
class EventMatchHelper {
  const EventMatchHelper._();

  /// 生成增量匹配计划：将 `newEvents` 与 `oldEvents` 做一对一匹配。
  ///
  /// 过程：
  /// 1) 计算所有候选匹配分数（时间/距离/照片重叠）
  /// 2) 过滤掉低于阈值的候选
  /// 3) 按分数降序贪心分配，保证一对一
  /// 4) 输出未匹配旧事件（用于日志/诊断）
  static EventMatchPlan buildIncrementalMatchPlan({
    required List<EventEntity> oldEvents,
    required List<EventEntity> newEvents,
    EventMatchConfig config = const EventMatchConfig(),
  }) {
    // Step 1: 构建候选池
    final candidates = <EventMatchCandidate>[];
    for (var newIndex = 0; newIndex < newEvents.length; newIndex++) {
      final draft = newEvents[newIndex];
      for (final old in oldEvents) {
        final scoreData = calculateMatchScore(
          old: old,
          draft: draft,
          config: config,
        );
        if (scoreData == null || scoreData.score < config.minScore) {
          continue;
        }
        candidates.add(
          EventMatchCandidate(
            oldEventId: old.id,
            newIndex: newIndex,
            score: scoreData.score,
            timeScore: scoreData.timeScore,
            distanceScore: scoreData.distanceScore,
            overlapScore: scoreData.overlapScore,
          ),
        );
      }
    }

    // Step 2: 高分优先尝试匹配
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // Step 3: 一对一贪心分配
    final usedOld = <int>{};
    final usedNew = <int>{};
    final newIndexToOldId = <int, int>{};
    for (final candidate in candidates) {
      if (usedOld.contains(candidate.oldEventId) ||
          usedNew.contains(candidate.newIndex)) {
        continue;
      }
      usedOld.add(candidate.oldEventId);
      usedNew.add(candidate.newIndex);
      newIndexToOldId[candidate.newIndex] = candidate.oldEventId;
    }

    // Step 4: 标记疑似“陈旧”旧事件（仅诊断，不强制删除）
    final clusteredPhotoIds = newEvents
        .expand((event) => event.photoIds)
        .toSet();
    final staleOldEventIds = oldEvents
        .where(
          (old) =>
              !usedOld.contains(old.id) &&
              old.photoIds.any(clusteredPhotoIds.contains),
        )
        .map((old) => old.id)
        .toList();

    return EventMatchPlan(
      newIndexToOldId: newIndexToOldId,
      staleOldEventIds: staleOldEventIds,
      matchedCount: newIndexToOldId.length,
      newCount: newEvents.length - newIndexToOldId.length,
    );
  }

  /// 计算单个旧事件与新事件草稿的匹配分数。
  ///
  /// 返回 null 表示不可匹配（无照片重叠或时间差过大）。
  static EventMatchScore? calculateMatchScore({
    required EventEntity old,
    required EventEntity draft,
    EventMatchConfig config = const EventMatchConfig(),
  }) {
    final overlapScore = jaccardByPhotoIds(old.photoIds, draft.photoIds);
    if (overlapScore <= 0) {
      return null;
    }

    final gapHours = eventGapHours(
      old.startTime,
      old.endTime,
      draft.startTime,
      draft.endTime,
    );
    if (gapHours > config.candidateGapHours) {
      return null;
    }

    final timeScore = (1 - (gapHours / config.candidateGapHours)).clamp(
      0.0,
      1.0,
    );
    final distanceScore = eventCenterDistanceScore(
      old: old,
      draft: draft,
      distanceThresholdKm: config.distanceThresholdKm,
    );

    final score = 0.4 * timeScore + 0.25 * distanceScore + 0.35 * overlapScore;
    return EventMatchScore(
      score: score,
      timeScore: timeScore,
      distanceScore: distanceScore,
      overlapScore: overlapScore,
    );
  }

  /// 事件时间段最小间隔（小时）。
  ///
  /// - 时间段重叠 => 0
  /// - 不重叠 => 两段最近边界的差值
  static double eventGapHours(int s1, int e1, int s2, int e2) {
    if (e1 < s2) {
      return (s2 - e1) / (1000 * 60 * 60);
    }
    if (e2 < s1) {
      return (s1 - e2) / (1000 * 60 * 60);
    }
    return 0.0;
  }

  /// 基于事件中心点距离计算空间分数。
  ///
  /// - 无GPS：给默认 0.6，避免过度惩罚
  /// - 距离 >= 阈值：0
  /// - 否则按线性衰减
  static double eventCenterDistanceScore({
    required EventEntity old,
    required EventEntity draft,
    double distanceThresholdKm = 5,
  }) {
    if (old.avgLatitude == null ||
        old.avgLongitude == null ||
        draft.avgLatitude == null ||
        draft.avgLongitude == null) {
      return 0.6;
    }

    final distanceKm = EventClusterHelper.calculateDistanceKm(
      old.avgLatitude!,
      old.avgLongitude!,
      draft.avgLatitude!,
      draft.avgLongitude!,
    );
    if (distanceKm >= distanceThresholdKm) {
      return 0.0;
    }
    return 1 - (distanceKm / distanceThresholdKm);
  }

  /// 照片集合 Jaccard 相似度：|交集| / |并集|。
  static double jaccardByPhotoIds(List<int> left, List<int> right) {
    if (left.isEmpty || right.isEmpty) {
      return 0.0;
    }
    final l = left.toSet();
    final r = right.toSet();
    final intersection = l.intersection(r).length;
    final union = l.union(r).length;
    if (union == 0) {
      return 0.0;
    }
    return intersection / union;
  }
}

/// 单次 (old, new) 候选的分数拆解结果。
///
/// - score：最终综合分（用于排序与阈值判断）
/// - timeScore：时间相似度
/// - distanceScore：空间相似度
/// - overlapScore：照片重叠相似度
class EventMatchScore {
  final double score;
  final double timeScore;
  final double distanceScore;
  final double overlapScore;

  const EventMatchScore({
    required this.score,
    required this.timeScore,
    required this.distanceScore,
    required this.overlapScore,
  });
}
