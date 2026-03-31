import 'dart:math';

import '../../models/entity/photo_entity.dart';

/// 空间规则（聚类工具）。
///
/// 统一提供 GPS 可用性判断与距离计算，避免在聚类主流程中散落数学细节。
class EventClusterSpatialRules {
  const EventClusterSpatialRules._();

  /// 是否存在可用的 GPS 坐标（经纬度都非空）。
  static bool hasGps(PhotoEntity photo) {
    return photo.latitude != null && photo.longitude != null;
  }

  /// 计算两点之间的大圆距离（单位：公里）。
  ///
  /// 使用 Haversine 公式，足够满足事件聚类的“同城/跨城”与“距离阈值”判断。
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

  /// 角度转弧度（内部工具）。
  static double _toRadians(double degree) {
    return degree * pi / 180;
  }
}
