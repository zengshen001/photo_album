import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/story/story_input_mapper.dart';

PhotoEntity _photo({
  required int id,
  required DateTime time,
  String? formattedAddress,
  String? district,
  double? lat,
  double? lon,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/p$id.jpg'
    ..timestamp = time.millisecondsSinceEpoch
    ..width = 1200
    ..height = 900
    ..formattedAddress = formattedAddress
    ..district = district
    ..latitude = lat
    ..longitude = lon
    ..aiTags = ['海边'];
}

void main() {
  group('StoryInputMapper', () {
    test('build sorts by timestamp and prefers address mode', () {
      final input = [
        _photo(id: 2, time: DateTime(2026, 3, 2, 13, 0), lat: 22.5, lon: 114.0),
        _photo(
          id: 1,
          time: DateTime(2026, 3, 2, 9, 0),
          formattedAddress: '广东省深圳市南山区深圳湾公园',
        ),
      ];

      final mapped = StoryInputMapper.build(input);

      expect(mapped.sortedPhotos.map((e) => e.id).toList(), [1, 2]);
      expect(mapped.locationMode, 'address');
      expect(mapped.photoDescriptions.length, 2);
    });

    test('build falls back to gps mode when no address', () {
      final input = [
        _photo(id: 1, time: DateTime(2026, 3, 2, 9, 0), lat: 22.5, lon: 114.0),
      ];

      final mapped = StoryInputMapper.build(input);
      expect(mapped.locationMode, 'gps');
    });
  });
}
