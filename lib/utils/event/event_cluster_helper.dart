import '../../models/entity/photo_entity.dart';
import 'event_cluster_city_rules.dart';
import 'event_festival_rules.dart';
import 'event_cluster_spatial_rules.dart';
import 'event_cluster_time_rules.dart';

class ClusterConfig {
  final int initialTimeThresholdHours;
  final double baseDistanceThresholdKm;
  final int sameCityTimeThresholdHours;
  final double sameCityDistanceThresholdKm;
  final double fallbackSameCityDistanceKm;
  final int sameDayMergeGapHours;
  final int crossDayMergeGapHours;
  final int minPhotosPerClusterForMerge;
  final bool enableSameDayTravelMerge;
  final bool enableCrossDayTravelMerge;
  final bool enableFestivalClustering;
  final int festivalMergeGapHours;
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

class EventClusterHelper {
  const EventClusterHelper._();

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

  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return EventClusterSpatialRules.calculateDistanceKm(lat1, lon1, lat2, lon2);
  }
}

class _FestivalPostProcessResult {
  final List<List<PhotoEntity>> clusters;
  final List<FestivalMatchResult> matches;

  const _FestivalPostProcessResult({
    required this.clusters,
    required this.matches,
  });
}
