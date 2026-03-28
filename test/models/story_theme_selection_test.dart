import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/ai_theme.dart';
import 'package:photo_album/models/story_theme_selection.dart';

void main() {
  group('StoryThemeSelection', () {
    test('fromAITheme keeps recommended metadata', () {
      final selection = StoryThemeSelection.fromAITheme(
        AITheme(id: 'theme_1', emoji: '🌊', title: '夏日旅行', subtitle: '海风与阳光'),
        tone: StoryThemeTone.humorous,
      );

      expect(selection.themeId, 'theme_1');
      expect(selection.themeTitle, '夏日旅行');
      expect(selection.subtitle, '海风与阳光');
      expect(selection.source, StoryThemeSource.aiRecommend);
      expect(selection.tone, StoryThemeTone.humorous);
    });

    test('validates trimmed title length and supports json round trip', () {
      const selection = StoryThemeSelection(
        themeTitle: '  周末城市漫游  ',
        subtitle: '街角与晚风',
        source: StoryThemeSource.custom,
        tone: StoryThemeTone.warm,
      );

      expect(selection.isValid, isTrue);
      expect(selection.normalizedThemeTitle, '周末城市漫游');

      final restored = StoryThemeSelection.fromJson(selection.toJson());
      expect(restored.normalizedThemeTitle, '周末城市漫游');
      expect(restored.subtitle, '街角与晚风');
      expect(restored.source, StoryThemeSource.custom);
      expect(restored.tone, StoryThemeTone.warm);
    });
  });
}
