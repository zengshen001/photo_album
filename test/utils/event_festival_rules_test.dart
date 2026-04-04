import 'package:flutter_test/flutter_test.dart';

import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/event/event_festival_rules.dart';

PhotoEntity _photo({
  required int id,
  required DateTime time,
  List<String>? tags,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = time.millisecondsSinceEpoch
    ..width = 100
    ..height = 100
    ..aiTags = tags;
}

void main() {
  test('festival cluster exposes propagated festival tag', () {
    final photos = [
      _photo(id: 1, time: DateTime(2024, 6, 10), tags: ['美食', '水', '船']),
      _photo(id: 2, time: DateTime(2024, 6, 10), tags: ['人群', '建筑']),
      _photo(id: 3, time: DateTime(2024, 6, 10), tags: ['美食']),
    ];

    final match = EventFestivalRules.matchCluster(photos);
    expect(match.isFestivalEvent, isTrue);
    expect(match.festivalName, '端午');
    expect(
      EventFestivalRules.buildFestivalTags(
        isFestivalEvent: match.isFestivalEvent,
        festivalName: match.festivalName,
      ),
      contains('🥟 端午'),
    );
  });

  test('event entity merges festival tag into tags', () {
    final photos = [
      _photo(id: 1, time: DateTime(2024, 6, 10), tags: ['美食', '水', '船']),
      _photo(id: 2, time: DateTime(2024, 6, 10), tags: ['人群', '建筑']),
      _photo(id: 3, time: DateTime(2024, 6, 10), tags: ['美食']),
    ];

    final event = EventEntity.fromPhotos(photos);
    expect(event.tags, contains('🥟 端午'));
  });
}
