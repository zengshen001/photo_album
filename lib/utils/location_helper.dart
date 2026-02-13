import 'package:geocoding/geocoding.dart';

class LocationInfo {
  final String? province;
  final String? city;

  const LocationInfo({required this.province, required this.city});
}

class LocationHelper {
  const LocationHelper._();

  static LocationInfo resolveFromPlacemarks(List<Placemark> placemarks) {
    final place = placemarks.isNotEmpty ? placemarks.first : null;
    return resolveFromParts(
      administrativeArea: place?.administrativeArea,
      locality: place?.locality,
      subAdministrativeArea: place?.subAdministrativeArea,
    );
  }

  static LocationInfo resolveFromParts({
    required String? administrativeArea,
    required String? locality,
    required String? subAdministrativeArea,
  }) {
    final province = _normalize(administrativeArea);
    final city =
        _normalize(locality) ?? _normalize(subAdministrativeArea) ?? province;
    return LocationInfo(province: province, city: city);
  }

  static String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
