import 'package:flutter_test/flutter_test.dart';

import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/event/event_scenario_rules.dart';

PhotoEntity _photo({
  required int id,
  required DateTime time,
  List<String>? tags,
  int faceCount = 0,
  double smileProb = 0,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = time.millisecondsSinceEpoch
    ..width = 100
    ..height = 100
    ..aiTags = tags
    ..faceCount = faceCount
    ..smileProb = smileProb;
}

void main() {
  test('graduation season requires month ratio and face count', () {
    final photos = [
      _photo(
        id: 1,
        time: DateTime(2022, 6, 18),
        tags: ['学校', '人群'],
        faceCount: 4,
      ),
      _photo(
        id: 2,
        time: DateTime(2022, 6, 18),
        tags: ['学校', '建筑'],
        faceCount: 4,
      ),
      _photo(
        id: 3,
        time: DateTime(2022, 6, 18),
        tags: ['校园', '活动'],
        faceCount: 4,
      ),
    ];

    final tags = EventScenarioRules.generateAdvancedTags(photos);
    expect(tags, contains('🎓 毕业季'));
  });

  test('ancient town and family gathering tags can be inferred', () {
    final photos = [
      _photo(
        id: 1,
        time: DateTime(2025, 2, 1),
        tags: ['古城', '灯笼', '人群', '建筑'],
        faceCount: 2,
      ),
      _photo(
        id: 2,
        time: DateTime(2025, 2, 1),
        tags: ['室内', '餐厅', '桌子'],
        faceCount: 4,
      ),
    ];

    final tags = EventScenarioRules.generateAdvancedTags(photos);
    expect(tags, contains('🏮 古城漫游'));
    expect(tags, contains('👨‍👩‍👧‍👦 家庭欢聚'));
  });
}
