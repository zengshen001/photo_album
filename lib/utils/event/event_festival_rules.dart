import '../../models/entity/photo_entity.dart';
import 'event_cluster_city_rules.dart';

enum FestivalMergePolicy { preferMerge, strictSplit }

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

class EventFestivalRules {
  const EventFestivalRules._();

  static const String builtInVersion = 'cn_builtin_2024_2030_v1';

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

  static FestivalRule? resolveFestivalRule(DateTime date) {
    for (final rule in rulesForYear(date.year)) {
      if (rule.contains(date)) {
        return rule;
      }
    }
    return null;
  }

  static List<FestivalRule> rulesForYear(int year) {
    return _rulesByYear[year] ?? _buildFallbackRules(year);
  }

  static FestivalRule? _matchPhoto(PhotoEntity photo) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    return resolveFestivalRule(date);
  }

  static List<FestivalRule> _buildFallbackRules(int year) {
    return [
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
    ];
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
