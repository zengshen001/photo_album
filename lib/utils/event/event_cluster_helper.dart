import '../../models/entity/photo_entity.dart';
import 'event_cluster_city_rules.dart';
import 'event_festival_rules.dart';
import 'event_cluster_spatial_rules.dart';
import 'event_cluster_time_rules.dart';

/// 事件聚类配置。
///
/// 这份配置决定了“照片 -> 初分簇 -> 旅行合并 -> 节日后处理”的各类阈值。
/// 注意：阈值的单位不完全相同，时间相关均为小时，距离相关均为公里。
class ClusterConfig {
  /// 初始分簇：当两张相邻照片的时间差超过该阈值（跨城会用更严格规则）时切分事件。
  final int initialTimeThresholdHours;

  /// 初始分簇：当两张相邻照片的直线距离超过该阈值（在有 GPS 时）时切分事件。
  final double baseDistanceThresholdKm;

  /// 同城照片的时间阈值（同城可更宽松，以减少同一城市的事件被过度切碎）。
  final int sameCityTimeThresholdHours;

  /// 同城照片的距离阈值（同城可更宽松，以减少同一城市的事件被过度切碎）。
  final double sameCityDistanceThresholdKm;

  /// 当缺少 city/adcode 但有 GPS 时，用“距离”粗略判定同城/跨城的兜底阈值。
  final double fallbackSameCityDistanceKm;

  /// 旅行合并：同一天内，相邻簇间隔不超过该阈值时允许合并（前提：不跨城）。
  final int sameDayMergeGapHours;

  /// 旅行合并：跨天时，相邻簇间隔不超过该阈值时允许合并（前提：允许跨天合并且不跨城）。
  final int crossDayMergeGapHours;

  /// 旅行合并：参与合并判断的最小簇大小。
  ///
  /// 这是一个保护阈值：太小的簇更可能是噪声，不参与合并以避免错误串联。
  final int minPhotosPerClusterForMerge;

  /// 是否开启“同一天旅行合并”逻辑。
  final bool enableSameDayTravelMerge;

  /// 是否开启“跨天旅行合并”逻辑。
  final bool enableCrossDayTravelMerge;

  /// 是否开启“节日后处理”逻辑（节日边界切分 + 同节日合并）。
  final bool enableFestivalClustering;

  /// 节日合并：两个“同节日”簇之间允许合并的最大时间间隔（小时）。
  final int festivalMergeGapHours;

  /// 节日规则版本号，用于可观测性/诊断（当前为内置规则版本）。
  final String festivalListVersion;

  const ClusterConfig({
    this.initialTimeThresholdHours = 3,
    this.baseDistanceThresholdKm = 8,
    this.sameCityTimeThresholdHours = 6,
    this.sameCityDistanceThresholdKm = 20,
    this.fallbackSameCityDistanceKm = 45,
    this.sameDayMergeGapHours = 8,
    this.crossDayMergeGapHours = 18,
    this.minPhotosPerClusterForMerge = 3,
    this.enableSameDayTravelMerge = true,
    this.enableCrossDayTravelMerge = true,
    this.enableFestivalClustering = false,
    this.festivalMergeGapHours = 48,
    this.festivalListVersion = EventFestivalRules.builtInVersion,
  });
}

/// 聚类结果（纯内存结构）。
///
/// - [clusters]：最终事件簇（每个簇是一段按时间连续的照片列表）
/// - [festivalMatches]：每个簇对应的节日匹配结果（与 clusters 一一对应）
/// - [initialClusterCount]：初分簇数量（未进行合并/节日后处理前）
/// - [mergedCount]：最终簇相对初分簇减少的数量（用于统计“合并了多少簇”）
class ClusterResult {
  final List<List<PhotoEntity>> clusters;
  final List<FestivalMatchResult> festivalMatches;
  final int initialClusterCount;
  final int mergedCount;

  const ClusterResult({
    required this.clusters,
    required this.festivalMatches,
    required this.initialClusterCount,
    required this.mergedCount,
  });
}

/// 照片聚类核心工具。
///
/// 输入一串按时间排序的照片（一般是“时间升序”），输出“事件簇”列表：
///
/// 1) 初分簇：按相邻照片的时间差/距离/跨城规则切分
/// 2) 旅行合并：把相邻簇在一定间隔内合并（同日/跨日策略）
/// 3) 节日后处理：按节日边界切分，并把同节日相邻簇在阈值内合并
class EventClusterHelper {
  const EventClusterHelper._();

  /// 执行聚类主流程。
  ///
  /// 约定：调用方应保证 [photos] 按时间升序排列（否则初分簇与相邻合并的语义会被破坏）。
  static ClusterResult clusterPhotos({
    required List<PhotoEntity> photos,
    ClusterConfig config = const ClusterConfig(),
  }) {
    if (photos.isEmpty) {
      return const ClusterResult(
        clusters: [],
        festivalMatches: [],
        initialClusterCount: 0,
        mergedCount: 0,
      );
    }

    final initialClusters = _initialSplit(photos: photos, config: config);
    final travelMergedClusters = config.enableSameDayTravelMerge
        ? _mergeSameDayTravelClusters(clusters: initialClusters, config: config)
        : initialClusters;
    final festivalProcessed = config.enableFestivalClustering
        ? _applyFestivalPostProcessing(
            clusters: travelMergedClusters,
            config: config,
          )
        : _FestivalPostProcessResult(
            clusters: travelMergedClusters,
            matches: travelMergedClusters
                .map((cluster) => EventFestivalRules.matchCluster(cluster))
                .toList(),
          );

    return ClusterResult(
      clusters: festivalProcessed.clusters,
      festivalMatches: festivalProcessed.matches,
      initialClusterCount: initialClusters.length,
      mergedCount: initialClusters.length - festivalProcessed.clusters.length,
    );
  }

  /// 初分簇：顺序扫描照片序列，遇到“应切分”的相邻对就断开，形成多个簇。
  ///
  /// 这里的“相邻”是指时间排序后相邻，因此必须保证输入是时间升序。
  static List<List<PhotoEntity>> _initialSplit({
    required List<PhotoEntity> photos,
    required ClusterConfig config,
  }) {
    final clusters = <List<PhotoEntity>>[];
    var currentCluster = <PhotoEntity>[photos.first];

    for (var i = 1; i < photos.length; i++) {
      final prev = photos[i - 1];
      final curr = photos[i];
      final timeDiff = (curr.timestamp - prev.timestamp) / (1000 * 60 * 60);

      final shouldSplit = _shouldSplitByPair(
        prev: prev,
        curr: curr,
        timeDiffHours: timeDiff,
        config: config,
      );

      if (shouldSplit) {
        clusters.add(currentCluster);
        currentCluster = <PhotoEntity>[curr];
      } else {
        currentCluster.add(curr);
      }
    }

    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    return clusters;
  }

  /// 旅行合并：把相邻簇尝试合并成更长的事件。
  ///
  /// 合并需要满足：
  /// - 两簇都不太小（>= minPhotosPerClusterForMerge）
  /// - 簇间隔不超过阈值（同日用 sameDayMergeGapHours，否则用 crossDayMergeGapHours）
  /// - 不跨城
  static List<List<PhotoEntity>> _mergeSameDayTravelClusters({
    required List<List<PhotoEntity>> clusters,
    required ClusterConfig config,
  }) {
    if (clusters.length <= 1) {
      return clusters;
    }

    final merged = <List<PhotoEntity>>[List<PhotoEntity>.from(clusters.first)];

    for (var i = 1; i < clusters.length; i++) {
      final lastCluster = merged.last;
      final currentCluster = clusters[i];

      if (_shouldMergeClusters(
        left: lastCluster,
        right: currentCluster,
        config: config,
      )) {
        lastCluster.addAll(currentCluster);
      } else {
        merged.add(List<PhotoEntity>.from(currentCluster));
      }
    }

    return merged;
  }

  /// 节日后处理：在“旅行合并”之后，进一步做节日边界切分与节日合并。
  ///
  /// - 先按节日边界拆分：避免一个簇同时包含两个严格分离的节日（如清明和非清明）
  /// - 再按节日合并：相邻簇如果同属一个节日，且间隔与跨城条件允许，则合并
  static _FestivalPostProcessResult _applyFestivalPostProcessing({
    required List<List<PhotoEntity>> clusters,
    required ClusterConfig config,
  }) {
    if (clusters.isEmpty) {
      return const _FestivalPostProcessResult(clusters: [], matches: []);
    }

    final normalizedClusters = <List<PhotoEntity>>[];
    for (final cluster in clusters) {
      final splitClusters = _splitClusterByFestivalBoundary(
        cluster: cluster,
        config: config,
      );
      normalizedClusters.addAll(splitClusters);
    }

    final mergedClusters = <List<PhotoEntity>>[];
    final matches = <FestivalMatchResult>[];

    for (final cluster in normalizedClusters) {
      final match = EventFestivalRules.matchCluster(cluster);
      if (mergedClusters.isEmpty) {
        mergedClusters.add(List<PhotoEntity>.from(cluster));
        matches.add(match);
        continue;
      }

      if (_shouldMergeByFestival(
        left: mergedClusters.last,
        right: cluster,
        leftMatch: matches.last,
        rightMatch: match,
        config: config,
      )) {
        mergedClusters.last.addAll(cluster);
        matches[matches.length - 1] = EventFestivalRules.matchCluster(
          mergedClusters.last,
        );
      } else {
        mergedClusters.add(List<PhotoEntity>.from(cluster));
        matches.add(match);
      }
    }

    return _FestivalPostProcessResult(
      clusters: mergedClusters,
      matches: matches,
    );
  }

  /// 当一个簇跨越了“节日边界”且规则要求严格切分时，把该簇拆成两段。
  ///
  /// 返回值可能是：
  /// - 原簇（无需拆分）
  /// - 2 个子簇（在边界处切开）
  static List<List<PhotoEntity>> _splitClusterByFestivalBoundary({
    required List<PhotoEntity> cluster,
    required ClusterConfig config,
  }) {
    if (!EventFestivalRules.shouldForceSplitCluster(
      cluster: cluster,
      fallbackSameCityDistanceKm: config.fallbackSameCityDistanceKm,
    )) {
      return [List<PhotoEntity>.from(cluster)];
    }

    for (var i = 1; i < cluster.length; i++) {
      final prevRule = EventFestivalRules.resolveFestivalRule(
        DateTime.fromMillisecondsSinceEpoch(cluster[i - 1].timestamp),
      );
      final currentRule = EventFestivalRules.resolveFestivalRule(
        DateTime.fromMillisecondsSinceEpoch(cluster[i].timestamp),
      );
      if (prevRule?.name == currentRule?.name) {
        continue;
      }
      return [
        List<PhotoEntity>.from(cluster.take(i)),
        List<PhotoEntity>.from(cluster.skip(i)),
      ].where((part) => part.isNotEmpty).toList();
    }

    return [List<PhotoEntity>.from(cluster)];
  }

  /// 判断两个相邻簇是否应该按“节日逻辑”合并。
  ///
  /// 合并条件：
  /// - 两边都被识别为节日事件
  /// - 节日名称相同
  /// - 簇间隔不超过 festivalMergeGapHours
  /// - 不跨城（避免把两个不同城市的“节日照片”串成一个事件）
  static bool _shouldMergeByFestival({
    required List<PhotoEntity> left,
    required List<PhotoEntity> right,
    required FestivalMatchResult leftMatch,
    required FestivalMatchResult rightMatch,
    required ClusterConfig config,
  }) {
    if (!leftMatch.isFestivalEvent || !rightMatch.isFestivalEvent) {
      return false;
    }
    if (leftMatch.festivalName != rightMatch.festivalName) {
      return false;
    }

    final gapHours =
        (right.first.timestamp - left.last.timestamp) / (1000 * 60 * 60);
    if (gapHours > config.festivalMergeGapHours) {
      return false;
    }

    if (EventClusterCityRules.isCrossCity(
      left.last,
      right.first,
      fallbackSameCityDistanceKm: config.fallbackSameCityDistanceKm,
    )) {
      return false;
    }

    return true;
  }

  /// 判断两个相邻簇是否应该按“旅行合并逻辑”合并。
  ///
  /// 注意：该方法只判断“是否可合并”，不负责真正合并。
  static bool _shouldMergeClusters({
    required List<PhotoEntity> left,
    required List<PhotoEntity> right,
    required ClusterConfig config,
  }) {
    if (left.length < config.minPhotosPerClusterForMerge ||
        right.length < config.minPhotosPerClusterForMerge) {
      return false;
    }

    final leftEnd = left.last;
    final rightStart = right.first;
    final gapHours =
        (rightStart.timestamp - leftEnd.timestamp) / (1000 * 60 * 60);
    final isSameDay = EventClusterTimeRules.isSameLocalDay(
      leftEnd.timestamp,
      rightStart.timestamp,
    );
    final mergeGapThreshold = isSameDay
        ? config.sameDayMergeGapHours
        : config.crossDayMergeGapHours;

    if (gapHours > mergeGapThreshold) {
      return false;
    }

    if (!isSameDay && !config.enableCrossDayTravelMerge) {
      return false;
    }

    // 已识别为跨城的相邻簇不合并
    if (EventClusterCityRules.isCrossCity(
      leftEnd,
      rightStart,
      fallbackSameCityDistanceKm: config.fallbackSameCityDistanceKm,
    )) {
      return false;
    }

    return true;
  }

  /// 判断两张相邻照片是否应当切分事件。
  ///
  /// 优先级：
  /// 1) 跨城直接切分
  /// 2) 时间差超过阈值切分（同城阈值更宽松）
  /// 3) 若两者都有 GPS，则再用距离阈值判断是否切分
  ///
  /// 说明：若缺少 GPS，则只依赖跨城判断（基于 adcode/city）与时间差判断。
  static bool _shouldSplitByPair({
    required PhotoEntity prev,
    required PhotoEntity curr,
    required double timeDiffHours,
    required ClusterConfig config,
  }) {
    if (EventClusterCityRules.isCrossCity(
      prev,
      curr,
      fallbackSameCityDistanceKm: config.fallbackSameCityDistanceKm,
    )) {
      return true;
    }

    final hasBothGps =
        EventClusterSpatialRules.hasGps(prev) &&
        EventClusterSpatialRules.hasGps(curr);
    final sameCity = EventClusterCityRules.isSameCity(
      prev,
      curr,
      fallbackSameCityDistanceKm: config.fallbackSameCityDistanceKm,
    );

    final timeThreshold = sameCity
        ? config.sameCityTimeThresholdHours
        : config.initialTimeThresholdHours;
    if (timeDiffHours > timeThreshold) {
      return true;
    }

    if (!hasBothGps) {
      return false;
    }

    final distance = EventClusterSpatialRules.calculateDistanceKm(
      prev.latitude!,
      prev.longitude!,
      curr.latitude!,
      curr.longitude!,
    );
    final distanceThreshold = sameCity
        ? config.sameCityDistanceThresholdKm
        : config.baseDistanceThresholdKm;
    return distance > distanceThreshold;
  }

  /// 对外暴露的距离计算工具（用于增量匹配等模块共享）。
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return EventClusterSpatialRules.calculateDistanceKm(lat1, lon1, lat2, lon2);
  }
}

/// 节日后处理的内部返回结构。
///
/// 为了在聚类流程中同时携带“簇列表”与“节日匹配结果列表”，使用该结构作为中间结果。
class _FestivalPostProcessResult {
  final List<List<PhotoEntity>> clusters;
  final List<FestivalMatchResult> matches;

  const _FestivalPostProcessResult({
    required this.clusters,
    required this.matches,
  });
}
