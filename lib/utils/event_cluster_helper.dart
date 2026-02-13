import 'dart:math';

import '../models/entity/photo_entity.dart';

class EventClusterHelper {
  const EventClusterHelper._();

  static List<List<PhotoEntity>> clusterPhotos({
    required List<PhotoEntity> photos,
    required int timeThresholdHours,
    required double distanceThresholdKm,
  }) {
    if (photos.isEmpty) {
      return const [];
    }

    final clusters = <List<PhotoEntity>>[];
    var currentCluster = <PhotoEntity>[photos.first];

    for (var i = 1; i < photos.length; i++) {
      final prev = photos[i - 1];
      final curr = photos[i];
      final timeDiff = (curr.timestamp - prev.timestamp) / (1000 * 60 * 60);

      double? distance;
      if (prev.latitude != null &&
          prev.longitude != null &&
          curr.latitude != null &&
          curr.longitude != null) {
        distance = _calculateDistance(
          prev.latitude!,
          prev.longitude!,
          curr.latitude!,
          curr.longitude!,
        );
      }

      final shouldSplit =
          timeDiff > timeThresholdHours ||
          (distance != null && distance > distanceThresholdKm);

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

  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
  }
}
