import '../../models/entity/photo_entity.dart';

class PhotoAssetMapper {
  const PhotoAssetMapper._();

  static PhotoEntity toEntity({
    required String assetId,
    required int timestamp,
    required String filePath,
    required int width,
    required int height,
    required double? latitude,
    required double? longitude,
  }) {
    return PhotoEntity()
      ..assetId = assetId
      ..timestamp = timestamp
      ..path = filePath
      ..width = width
      ..height = height
      ..latitude = latitude
      ..longitude = longitude
      ..isLocationProcessed = false;
  }
}
