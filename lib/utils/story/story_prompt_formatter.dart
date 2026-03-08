import '../../models/entity/photo_entity.dart';

class StoryPromptFormatter {
  const StoryPromptFormatter._();

  static List<String> buildPhotoDescriptions(List<PhotoEntity> photos) {
    final descriptions = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final time = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      final timeStr =
          '${time.month}月${time.day}日 ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
      final tags = photo.aiTags?.join(', ') ?? '无标签';
      final areaParts =
          [photo.province?.trim(), photo.city?.trim(), photo.district?.trim()]
              .where((item) => item != null && item.isNotEmpty)
              .cast<String>()
              .toList();
      final areaText = areaParts.isEmpty ? '' : areaParts.join('');
      final addressText = photo.formattedAddress?.trim() ?? '';
      final hasGps = photo.latitude != null && photo.longitude != null;
      final gpsText = hasGps
          ? '${photo.latitude!.toStringAsFixed(6)},${photo.longitude!.toStringAsFixed(6)}'
          : '';
      final locationSegments = <String>[];
      if (addressText.isNotEmpty) {
        locationSegments.add('formatted_address=$addressText');
        locationSegments.add('地址：$addressText');
      }
      if (areaText.isNotEmpty) {
        locationSegments.add('行政区：$areaText');
      }
      if (gpsText.isNotEmpty) {
        locationSegments.add('坐标：$gpsText');
      }
      final locationText = locationSegments.join('；');
      final desc =
          'Image $i: 拍摄于 $timeStr'
          '${locationText.isNotEmpty ? '，位置线索：$locationText' : ''}'
          '，标签：$tags';
      descriptions.add(desc);
    }
    return descriptions;
  }
}
