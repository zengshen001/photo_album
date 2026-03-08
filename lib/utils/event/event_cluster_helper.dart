import '../../models/entity/photo_entity.dart';
import 'event_cluster_city_rules.dart';
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
  });
}

class ClusterResult {
  final List<List<PhotoEntity>> clusters;
  final int initialClusterCount;
  final int mergedCount;

  const ClusterResult({
    required this.clusters,
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
        initialClusterCount: 0,
        mergedCount: 0,
      );
    }

    final initialClusters = _initialSplit(photos: photos, config: config);
    final mergedClusters = config.enableSameDayTravelMerge
        ? _mergeSameDayTravelClusters(clusters: initialClusters, config: config)
        : initialClusters;

    return ClusterResult(
      clusters: mergedClusters,
      initialClusterCount: initialClusters.length,
      mergedCount: initialClusters.length - mergedClusters.length,
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
