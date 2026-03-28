import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/story_theme_selection.dart';
import 'package:photo_album/service/story/story_theme_preference_service.dart';

void main() {
  group('StoryThemePreferenceService', () {
    test('saves and loads the latest selection', () async {
      final tempDir = await Directory.systemTemp.createTemp('story_theme_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/selection.json');
      final service = StoryThemePreferenceService(fileFactory: () => file);
      const selection = StoryThemeSelection(
        themeId: 'theme_1',
        themeTitle: '海边散记',
        subtitle: '海风与黄昏',
        source: StoryThemeSource.aiRecommend,
        tone: StoryThemeTone.lyrical,
      );

      await service.saveLatestSelection(selection);
      final loaded = await service.loadLatestSelection();

      expect(loaded, isNotNull);
      expect(loaded!.themeId, 'theme_1');
      expect(loaded.themeTitle, '海边散记');
      expect(loaded.subtitle, '海风与黄昏');
      expect(loaded.source, StoryThemeSource.aiRecommend);
      expect(loaded.tone, StoryThemeTone.lyrical);
    });

    test('ignores invalid persisted selection', () async {
      final tempDir = await Directory.systemTemp.createTemp('story_theme_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/selection.json');
      await file.writeAsString(
        '{"themeTitle":"a","subtitle":"","source":"custom","tone":"warm"}',
      );

      final service = StoryThemePreferenceService(fileFactory: () => file);
      final loaded = await service.loadLatestSelection();

      expect(loaded, isNull);
    });
  });
}
