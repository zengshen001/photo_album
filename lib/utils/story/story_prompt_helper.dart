import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/story_theme_selection.dart';
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
    int? templateId,
  }) {
    return StoryPromptTemplate.buildStoryPrompt(
      selection: selection,
      event: event,
      photoDescriptions: photoDescriptions,
      isShort: isShort,
      locationMode: locationMode,
      templateId: templateId,
    );
  }

  static Future<String> generateMockStoryContent({
    required StoryThemeSelection selection,
    required List<String> photoDescriptions,
    required bool isShort,
  }) async {
    return StoryMockGenerator.generate(
      title: selection.normalizedThemeTitle,
      subtitle: selection.normalizedSubtitle,
      photoDescriptions: photoDescriptions,
      isShort: isShort,
    );
  }
}
