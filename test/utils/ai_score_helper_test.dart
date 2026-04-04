import 'package:flutter_test/flutter_test.dart';

import 'package:photo_album/utils/photo/ai_score_helper.dart';

void main() {
  group('AIScoreHelper', () {
    test('computes multidimensional emotion scores with joy compatibility', () {
      final scores = AIScoreHelper.calculateEmotionScores(
        faceCount: 4,
        maxSmileProb: 0.85,
        tags: ['人群', '灯光', '美食', '节日'],
      );

      expect(scores.happy, greaterThan(0.4));
      expect(scores.lively, greaterThan(0.4));
      expect(scores.compatibilityJoyScore, greaterThan(0.4));
      expect(scores.dominantEmotion, isNotEmpty);
    });

    test('calm scenes produce calm score without requiring faces', () {
      final scores = AIScoreHelper.calculateEmotionScores(
        faceCount: 0,
        maxSmileProb: 0.0,
        tags: ['日落', '天空', '湖', '风景'],
      );

      expect(scores.calm, greaterThan(scores.lively));
      expect(scores.calm, greaterThan(0.4));
    });
  });
}
