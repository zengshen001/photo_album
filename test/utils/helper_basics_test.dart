import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/utils/photo/ai_score_helper.dart';
import 'package:photo_album/utils/location/location_helper.dart';
import 'package:photo_album/utils/photo/photo_filter_helper.dart';

void main() {
  group('LocationHelper', () {
    test('resolveFromParts falls back to subAdministrativeArea', () {
      final info = LocationHelper.resolveFromParts(
        administrativeArea: '广东省',
        locality: null,
        subAdministrativeArea: '深圳市',
      );

      expect(info.province, '广东省');
      expect(info.city, '深圳市');
    });
  });

  group('PhotoFilterHelper', () {
    test('isLikelyCameraPhoto rejects screenshot keyword', () {
      expect(
        PhotoFilterHelper.isLikelyCameraPhoto('/DCIM/Screenshot_20260308.png'),
        isFalse,
      );
    });

    test('isLikelyCameraPhoto accepts seed-like camera name', () {
      expect(
        PhotoFilterHelper.isLikelyCameraPhoto('/tmp/20260308_091500.jpg'),
        isTrue,
      );
    });
  });

  group('AIScoreHelper', () {
    test('calculateJoyScore prefers smile score when face exists', () {
      final score = AIScoreHelper.calculateJoyScore(
        faceCount: 1,
        maxSmileProb: 0.82,
        tags: const ['海滩'],
      );
      expect(score, 0.82);
    });

    test('calculateJoyScore falls back to joyful tags', () {
      final score = AIScoreHelper.calculateJoyScore(
        faceCount: 0,
        maxSmileProb: 0.0,
        tags: const ['美食'],
      );
      expect(score, 0.5);
    });
  });
}
