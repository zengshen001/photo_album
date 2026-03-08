import 'dart:math';

import '../../models/entity/photo_entity.dart';

class EventClusterSpatialRules {
  const EventClusterSpatialRules._();

  static bool hasGps(PhotoEntity photo) {
    return photo.latitude != null && photo.longitude != null;
  }

  static double calculateDistanceKm(
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
