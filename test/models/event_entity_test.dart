import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/event/event_festival_rules.dart';

PhotoEntity _photo({
  required int id,
  required DateTime time,
  String? city,
  String? province,
  String? adcode,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/p$id.jpg'
    ..timestamp = time.millisecondsSinceEpoch
    ..width = 1200
    ..height = 900
    ..city = city
    ..province = province
    ..adcode = adcode;
}

void main() {
  group('EventEntity.fromPhotos', () {
    test('writes festival fields into event entity', () {
      final photos = <PhotoEntity>[
        _photo(
          id: 1,
          time: DateTime(2026, 2, 16, 9),
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 2,
          time: DateTime(2026, 2, 16, 10),
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
      ];

      final event = EventEntity.fromPhotos(
        photos,
        festivalMatch: EventFestivalRules.matchCluster(photos),
      );

      expect(event.isFestivalEvent, isTrue);
      expect(event.festivalName, '春节');
      expect(event.festivalScore, 1);
      expect(event.title, '春节回忆');
      expect(event.coverPhotoId, 1);
    });

    test('keeps date title for non festival event', () {
      final photos = <PhotoEntity>[
        _photo(id: 1, time: DateTime(2026, 3, 9, 9)),
        _photo(id: 2, time: DateTime(2026, 3, 9, 10)),
      ];

      final event = EventEntity.fromPhotos(photos);

      expect(event.isFestivalEvent, isFalse);
      expect(event.festivalName, isNull);
      expect(event.title, '3月9日');
      expect(event.coverPhotoId, 1);
    });
  });
}
