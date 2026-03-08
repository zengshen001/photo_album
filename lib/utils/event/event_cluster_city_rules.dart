import '../../models/entity/photo_entity.dart';
import 'event_cluster_spatial_rules.dart';

class EventClusterCityRules {
  const EventClusterCityRules._();

  static bool isCrossCity(
    PhotoEntity a,
    PhotoEntity b, {
    required double fallbackSameCityDistanceKm,
  }) {
    final aCityKey = _cityKey(a);
    final bCityKey = _cityKey(b);
    if (aCityKey != null && bCityKey != null) {
      return aCityKey != bCityKey;
    }

    if (EventClusterSpatialRules.hasGps(a) &&
        EventClusterSpatialRules.hasGps(b)) {
      final distance = EventClusterSpatialRules.calculateDistanceKm(
        a.latitude!,
        a.longitude!,
        b.latitude!,
        b.longitude!,
      );
      return distance > fallbackSameCityDistanceKm;
    }

    return false;
  }

  static bool isSameCity(
    PhotoEntity a,
    PhotoEntity b, {
    required double fallbackSameCityDistanceKm,
  }) {
    final aCityKey = _cityKey(a);
    final bCityKey = _cityKey(b);
    if (aCityKey != null && bCityKey != null) {
      return aCityKey == bCityKey;
    }

    if (EventClusterSpatialRules.hasGps(a) &&
        EventClusterSpatialRules.hasGps(b)) {
      final distance = EventClusterSpatialRules.calculateDistanceKm(
        a.latitude!,
        a.longitude!,
        b.latitude!,
        b.longitude!,
      );
      return distance <= fallbackSameCityDistanceKm;
    }

    return false;
  }

  static String? _cityKey(PhotoEntity photo) {
    if (photo.adcode != null && photo.adcode!.trim().isNotEmpty) {
      final cityAdcode = _normalizeAdcodeToCityLevel(photo.adcode!.trim());
      if (cityAdcode != null) {
        return 'adcode:$cityAdcode';
      }
    }

    final city = photo.city?.trim();
    final province = photo.province?.trim();
    if (city != null && city.isNotEmpty) {
      return 'city:${province ?? ''}/$city';
    }

    return null;
  }

  // 高德 adcode 常见为 6 位，后两位通常是区县级别。
  // 聚类判定“是否同城”时使用城市级编码（前 4 位 + 00），
  // 避免同城不同区被误判为跨城，导致刷新后事件被拆散。
  static String? _normalizeAdcodeToCityLevel(String adcode) {
    if (adcode.length < 4) {
      return null;
    }
    final prefix = adcode.substring(0, 4);
    final isNumeric = RegExp(r'^\d{4}$').hasMatch(prefix);
    if (!isNumeric) {
      return null;
    }
    return '${prefix}00';
  }
}
