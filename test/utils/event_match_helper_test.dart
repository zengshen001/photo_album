import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/utils/event/event_match_helper.dart';

EventEntity _event({
  required int id,
  required DateTime start,
  required DateTime end,
  required List<int> photoIds,
  double? lat,
  double? lon,
}) {
  return EventEntity()
    ..id = id
    ..title = 'E$id'
    ..startTime = start.millisecondsSinceEpoch
    ..endTime = end.millisecondsSinceEpoch
    ..photoIds = photoIds
    ..photoCount = photoIds.length
    ..avgLatitude = lat
    ..avgLongitude = lon;
}

void main() {
  group('EventMatchHelper', () {
    test('jaccardByPhotoIds computes expected ratio', () {
      final score = EventMatchHelper.jaccardByPhotoIds([1, 2, 3], [2, 3, 4]);
      expect(score, closeTo(0.5, 0.0001));
    });

    test(
      'buildIncrementalMatchPlan keeps old event id when overlap is strong',
      () {
        final oldEvents = [
          _event(
            id: 10,
            start: DateTime(2026, 3, 1, 9),
            end: DateTime(2026, 3, 1, 18),
            photoIds: [1, 2, 3, 4],
            lat: 22.54,
            lon: 114.06,
          ),
        ];
        final newEvents = [
          _event(
            id: 0,
            start: DateTime(2026, 3, 1, 9),
            end: DateTime(2026, 3, 1, 19),
            photoIds: [2, 3, 4, 5],
            lat: 22.541,
            lon: 114.061,
          ),
        ];

        final plan = EventMatchHelper.buildIncrementalMatchPlan(
          oldEvents: oldEvents,
          newEvents: newEvents,
        );

        expect(plan.matchedCount, 1);
        expect(plan.newCount, 0);
        expect(plan.newIndexToOldId[0], 10);
        expect(plan.staleOldEventIds, isEmpty);
      },
    );

    test(
      'stale old event is detected when it overlaps clustered photos but not matched',
      () {
        final oldEvents = [
          _event(
            id: 10,
            start: DateTime(2026, 3, 1, 9),
            end: DateTime(2026, 3, 1, 12),
            photoIds: [1, 2, 3],
            lat: 22.54,
            lon: 114.06,
          ),
          _event(
            id: 11,
            start: DateTime(2026, 3, 1, 9),
            end: DateTime(2026, 3, 1, 13),
            photoIds: [2, 3, 4],
            lat: 22.54,
            lon: 114.06,
          ),
        ];
        final newEvents = [
          _event(
            id: 0,
            start: DateTime(2026, 3, 1, 9),
            end: DateTime(2026, 3, 1, 14),
            photoIds: [2, 3, 4],
            lat: 22.54,
            lon: 114.06,
          ),
        ];

        final plan = EventMatchHelper.buildIncrementalMatchPlan(
          oldEvents: oldEvents,
          newEvents: newEvents,
        );

        expect(plan.matchedCount, 1);
        expect(plan.staleOldEventIds.length, 1);
        expect(plan.staleOldEventIds.first, 10);
      },
    );

    test('calculateMatchScore returns null when no photo overlap', () {
      final scoreData = EventMatchHelper.calculateMatchScore(
        old: _event(
          id: 10,
          start: DateTime(2026, 3, 1, 9),
          end: DateTime(2026, 3, 1, 12),
          photoIds: [1, 2],
        ),
        draft: _event(
          id: 0,
          start: DateTime(2026, 3, 1, 9),
          end: DateTime(2026, 3, 1, 12),
          photoIds: [3, 4],
        ),
      );
      expect(scoreData, isNull);
    });
  });
}
