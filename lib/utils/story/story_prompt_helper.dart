import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/story_theme_selection.dart';
import '../../models/vo/story_template_context.dart';
import 'story_mock_generator.dart';
import 'story_prompt_formatter.dart';
import 'story_prompt_template.dart';

class StoryPromptHelper {
  const StoryPromptHelper._();

  static List<String> buildPhotoDescriptions(List<PhotoEntity> photos) {
    return StoryPromptFormatter.buildPhotoDescriptions(photos);
  }

  static String buildStoryPrompt({
    required StoryThemeSelection selection,
    required EventEntity event,
    required List<String> photoDescriptions,
    required bool isShort,
    required String locationMode,
    StoryTemplateContext? templateContext,
  }) {
    return StoryPromptTemplate.buildStoryPrompt(
      selection: selection,
      event: event,
      photoDescriptions: photoDescriptions,
      isShort: isShort,
      locationMode: locationMode,
      templateContext: templateContext,
    );
  }

  static Future<String> generateMockStoryContent({
    required StoryThemeSelection selection,
    required List<String> photoDescriptions,
    required bool isShort,
    String? templateTitle,
  }) async {
    return StoryMockGenerator.generate(
      title: selection.normalizedThemeTitle,
      photoDescriptions: photoDescriptions,
      isShort: isShort,
      templateTitle: templateTitle,
    );
  }
}
