import '../../models/entity/photo_entity.dart';
import 'event_cluster_city_rules.dart';

/// 节日合并策略。
///
/// - preferMerge：同节日更倾向合并（只要满足通用条件即可）
/// - strictSplit：跨节日边界时倾向强制切分（避免两个节日被合在一个事件里）
enum FestivalMergePolicy { preferMerge, strictSplit }

/// 单条节日规则。
///
/// 节日判断按“自然日”进行（忽略具体时分秒），并提供优先级与合并策略配置。
class FestivalRule {
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final int priority;
  final FestivalMergePolicy mergePolicy;

  const FestivalRule({
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.priority,
    this.mergePolicy = FestivalMergePolicy.preferMerge,
  });

  bool contains(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

/// 一个照片簇的“节日匹配结果”。
///
/// 匹配由 [EventFestivalRules.matchCluster] 生成，用于：
/// - 聚类后处理：决定是否同节日合并、是否跨节日强制切分
/// - 事件落库字段：isFestivalEvent / festivalName / festivalScore
class FestivalMatchResult {
  final bool isFestivalEvent;
  final String? festivalName;
  final double festivalScore;
  final FestivalRule? rule;

  const FestivalMatchResult({
    required this.isFestivalEvent,
    required this.festivalName,
    required this.festivalScore,
    required this.rule,
  });

  static const none = FestivalMatchResult(
    isFestivalEvent: false,
    festivalName: null,
    festivalScore: 0,
    rule: null,
  );
}

/// 节日规则引擎。
///
/// 核心职责：
/// 1) 对一个簇打节日标签（matchCluster）
/// 2) 判断一个簇是否需要在节日边界处强制切分（shouldForceSplitCluster）
/// 3) 提供“某天属于哪个节日规则”的解析能力（resolveFestivalRule / rulesForYear）
class EventFestivalRules {
  const EventFestivalRules._();

  /// 内置节日规则表版本号（用于日志/配置可观测性）。
  static const String builtInVersion = 'cn_builtin_2024_2030_v2';

  /// 判断一个簇是否为“节日事件”。
  ///
  /// 计算方法：
  /// - 遍历簇内每张照片的日期，统计命中每条节日规则的次数
  /// - 取命中次数最多且优先级最高的规则作为候选
  /// - 若候选命中比例 < 0.5，则认为不是节日事件
  static FestivalMatchResult matchCluster(List<PhotoEntity> cluster) {
    if (cluster.isEmpty) {
      return FestivalMatchResult.none;
    }

    final candidates = <FestivalRule, int>{};
    for (final photo in cluster) {
      final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      for (final rule in rulesForYear(date.year)) {
        if (rule.contains(date)) {
          candidates[rule] = (candidates[rule] ?? 0) + 1;
        }
      }
    }

    if (candidates.isEmpty) {
      return FestivalMatchResult.none;
    }

    final sortedCandidates = candidates.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return b.key.priority.compareTo(a.key.priority);
      });

    final best = sortedCandidates.first;
    final score = best.value / cluster.length;
    if (score < 0.5) {
      return FestivalMatchResult.none;
    }

    return FestivalMatchResult(
      isFestivalEvent: true,
      festivalName: best.key.name,
      festivalScore: score,
      rule: best.key,
    );
  }

  /// 判断一个簇是否需要“按节日边界强制切分”。
  ///
  /// 典型场景：一个簇跨越不同节日，且其中至少一个节日规则标记为 strictSplit，
  /// 那么为了避免“节日事件被混到一起”，在节日切换点切分簇。
  ///
  /// 额外条件：如果跨城，会更倾向切分（由 [EventClusterCityRules.isCrossCity] 辅助判断）。
  static bool shouldForceSplitCluster({
    required List<PhotoEntity> cluster,
    required double fallbackSameCityDistanceKm,
  }) {
    if (cluster.length < 2) {
      return false;
    }

    final firstMatch = _matchPhoto(cluster.first);
    final lastMatch = _matchPhoto(cluster.last);
    if (firstMatch == null || lastMatch == null) {
      return false;
    }
    if (firstMatch.name == lastMatch.name) {
      return false;
    }
    if (firstMatch.mergePolicy != FestivalMergePolicy.strictSplit &&
        lastMatch.mergePolicy != FestivalMergePolicy.strictSplit) {
      return false;
    }

    return EventClusterCityRules.isCrossCity(
      cluster.first,
      cluster.last,
      fallbackSameCityDistanceKm: fallbackSameCityDistanceKm,
    );
  }

  /// 解析某一天属于哪条节日规则（按自然日匹配）。
  static FestivalRule? resolveFestivalRule(DateTime date) {
    for (final rule in rulesForYear(date.year)) {
      if (rule.contains(date)) {
        return rule;
      }
    }
    return null;
  }

  /// 获取某年的规则表。
  ///
  /// - 内置年份：直接返回预置列表
  /// - 非内置年份：返回简化兜底规则（保证基本可用）
  static List<FestivalRule> rulesForYear(int year) {
    final yearRules = _rulesByYear[year];
    final combined = yearRules == null
        ? _buildFallbackRules(year)
        : [...yearRules, ..._buildFixedSolarRules(year)];
    return _sortByPriorityDesc(combined);
  }

  /// 单张照片匹配节日规则（内部工具）。
  static FestivalRule? _matchPhoto(PhotoEntity photo) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    return resolveFestivalRule(date);
  }

  /// 当年份未在内置表中时提供最小可用兜底规则（内部工具）。
  static List<FestivalRule> _buildFallbackRules(int year) {
    return _sortByPriorityDesc([
      FestivalRule(
        name: '清明',
        startDate: DateTime(year, 4, 4),
        endDate: DateTime(year, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(year, 10, 1),
        endDate: DateTime(year, 10, 7),
        priority: 90,
      ),
      ..._buildFixedSolarRules(year),
    ]);
  }

  /// 生成“每年固定日期”的节日规则（公历）。
  ///
  /// 这些节日不依赖农历，因此不需要按 year 写死，只要按同样的月/日生成即可。
  static List<FestivalRule> _buildFixedSolarRules(int year) {
    return [
      FestivalRule(
        name: '元旦',
        startDate: DateTime(year, 1, 1),
        endDate: DateTime(year, 1, 1),
        priority: 55,
      ),
      FestivalRule(
        name: '情人节',
        startDate: DateTime(year, 2, 14),
        endDate: DateTime(year, 2, 14),
        priority: 35,
      ),
      FestivalRule(
        name: '妇女节',
        startDate: DateTime(year, 3, 8),
        endDate: DateTime(year, 3, 8),
        priority: 30,
      ),
      FestivalRule(
        name: '愚人节',
        startDate: DateTime(year, 4, 1),
        endDate: DateTime(year, 4, 1),
        priority: 15,
      ),
      FestivalRule(
        name: '劳动节',
        startDate: DateTime(year, 5, 1),
        endDate: DateTime(year, 5, 3),
        priority: 75,
      ),
      FestivalRule(
        name: '儿童节',
        startDate: DateTime(year, 6, 1),
        endDate: DateTime(year, 6, 1),
        priority: 28,
      ),
      FestivalRule(
        name: '万圣节',
        startDate: DateTime(year, 10, 31),
        endDate: DateTime(year, 10, 31),
        priority: 30,
      ),
      FestivalRule(
        name: '圣诞节',
        startDate: DateTime(year, 12, 24),
        endDate: DateTime(year, 12, 26),
        priority: 40,
      ),
      FestivalRule(
        name: '跨年夜',
        startDate: DateTime(year, 12, 31),
        endDate: DateTime(year, 12, 31),
        priority: 45,
      ),
    ];
  }

  static List<FestivalRule> _sortByPriorityDesc(List<FestivalRule> rules) {
    final list = List<FestivalRule>.from(rules);
    list.sort((a, b) => b.priority.compareTo(a.priority));
    return list;
  }

  static final Map<int, List<FestivalRule>> _rulesByYear = {
    2024: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2024, 2, 9),
        endDate: DateTime(2024, 2, 17),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2024, 2, 23),
        endDate: DateTime(2024, 2, 25),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2024, 4, 4),
        endDate: DateTime(2024, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2024, 6, 8),
        endDate: DateTime(2024, 6, 10),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2024, 9, 15),
        endDate: DateTime(2024, 9, 17),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2024, 10, 1),
        endDate: DateTime(2024, 10, 7),
        priority: 90,
      ),
    ],
    2025: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2025, 1, 28),
        endDate: DateTime(2025, 2, 4),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2025, 2, 11),
        endDate: DateTime(2025, 2, 13),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2025, 4, 4),
        endDate: DateTime(2025, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2025, 5, 31),
        endDate: DateTime(2025, 6, 2),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2025, 10, 5),
        endDate: DateTime(2025, 10, 7),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2025, 10, 1),
        endDate: DateTime(2025, 10, 8),
        priority: 90,
      ),
    ],
    2026: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2026, 2, 15),
        endDate: DateTime(2026, 2, 23),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2026, 3, 2),
        endDate: DateTime(2026, 3, 4),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2026, 4, 4),
        endDate: DateTime(2026, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2026, 6, 19),
        endDate: DateTime(2026, 6, 21),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2026, 9, 25),
        endDate: DateTime(2026, 9, 27),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 7),
        priority: 90,
      ),
    ],
    2027: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2027, 2, 5),
        endDate: DateTime(2027, 2, 13),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2027, 2, 20),
        endDate: DateTime(2027, 2, 22),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2027, 4, 3),
        endDate: DateTime(2027, 4, 5),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2027, 6, 8),
        endDate: DateTime(2027, 6, 10),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2027, 9, 14),
        endDate: DateTime(2027, 9, 16),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2027, 10, 1),
        endDate: DateTime(2027, 10, 7),
        priority: 90,
      ),
    ],
    2028: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2028, 1, 25),
        endDate: DateTime(2028, 2, 2),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2028, 2, 9),
        endDate: DateTime(2028, 2, 11),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2028, 4, 4),
        endDate: DateTime(2028, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2028, 5, 27),
        endDate: DateTime(2028, 5, 29),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2028, 10, 2),
        endDate: DateTime(2028, 10, 4),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2028, 10, 1),
        endDate: DateTime(2028, 10, 7),
        priority: 90,
      ),
    ],
    2029: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2029, 2, 12),
        endDate: DateTime(2029, 2, 20),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2029, 2, 26),
        endDate: DateTime(2029, 2, 28),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2029, 4, 4),
        endDate: DateTime(2029, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2029, 6, 15),
        endDate: DateTime(2029, 6, 17),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2029, 9, 21),
        endDate: DateTime(2029, 9, 23),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2029, 10, 1),
        endDate: DateTime(2029, 10, 7),
        priority: 90,
      ),
    ],
    2030: [
      FestivalRule(
        name: '春节',
        startDate: DateTime(2030, 2, 2),
        endDate: DateTime(2030, 2, 10),
        priority: 100,
      ),
      FestivalRule(
        name: '元宵',
        startDate: DateTime(2030, 2, 16),
        endDate: DateTime(2030, 2, 18),
        priority: 70,
      ),
      FestivalRule(
        name: '清明',
        startDate: DateTime(2030, 4, 4),
        endDate: DateTime(2030, 4, 6),
        priority: 60,
        mergePolicy: FestivalMergePolicy.strictSplit,
      ),
      FestivalRule(
        name: '端午',
        startDate: DateTime(2030, 6, 4),
        endDate: DateTime(2030, 6, 6),
        priority: 80,
      ),
      FestivalRule(
        name: '中秋',
        startDate: DateTime(2030, 9, 12),
        endDate: DateTime(2030, 9, 14),
        priority: 85,
      ),
      FestivalRule(
        name: '国庆',
        startDate: DateTime(2030, 10, 1),
        endDate: DateTime(2030, 10, 7),
        priority: 90,
      ),
    ],
  };
}
