import '../../models/entity/photo_entity.dart';
import 'event_cluster_spatial_rules.dart';

/// 城市/跨城规则（聚类工具）。
///
/// 聚类时，“跨城”往往比“时间差”更强烈地暗示两个事件应当切分。
/// 本工具优先使用 adcode/city/province 等已解析地址信息，缺失时再用 GPS 距离兜底。
class EventClusterCityRules {
  const EventClusterCityRules._();

  /// 判断两张照片是否“跨城”。
  ///
  /// 判定策略：
  /// 1) 若两者都能提取到城市级 key（优先 adcode，其次 city/province），直接比较；
  /// 2) 否则若两者都有 GPS，用距离是否超过 [fallbackSameCityDistanceKm] 兜底；
  /// 3) 其余情况返回 false（信息不足时不轻易判跨城，避免过度拆分）。
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

  /// 判断两张照片是否“同城”。
  ///
  /// 与 [isCrossCity] 相反：
  /// 1) 优先比较城市级 key 是否相同；
  /// 2) 再用 GPS 距离 <= [fallbackSameCityDistanceKm] 兜底；
  /// 3) 信息不足时返回 false（同理，避免因为误判同城而错误合并）。
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

  /// 提取“城市级别”的 key，用于同城/跨城判断。
  ///
  /// 优先级：
  /// 1) adcode（会归一化到城市级：前 4 位 + 00）
  /// 2) province/city 文本（例如 "山东省/青岛市"）
  ///
  /// 返回 null 表示缺乏足够信息。
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

  /// 将高德 adcode 归一化到“城市级别”。
  ///
  /// 高德 adcode 常见为 6 位，后两位通常是区县级别。
  /// 聚类判定“是否同城”时使用城市级编码（前 4 位 + 00），
  /// 避免同城不同区被误判为跨城，导致刷新后事件被拆散。
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
