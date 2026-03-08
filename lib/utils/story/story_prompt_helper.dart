import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import 'story_mock_generator.dart';
import 'story_prompt_formatter.dart';
import 'story_prompt_template.dart';

class StoryPromptHelper {
  const StoryPromptHelper._();

  static List<String> buildPhotoDescriptions(List<PhotoEntity> photos) {
    return StoryPromptFormatter.buildPhotoDescriptions(photos);
  }

  static String buildStoryPrompt({
    required String title,
    required String subtitle,
    required EventEntity event,
    required List<String> photoDescriptions,
    required bool isShort,
    required String locationMode,
  }) {
    return StoryPromptTemplate.buildStoryPrompt(
      title: title,
      subtitle: subtitle,
      event: event,
      photoDescriptions: photoDescriptions,
      isShort: isShort,
      locationMode: locationMode,
    );
  }

  static Future<String> generateMockStoryContent({
    required String title,
    required String subtitle,
    required List<String> photoDescriptions,
    required bool isShort,
  }) async {
    return StoryMockGenerator.generate(
      title: title,
      subtitle: subtitle,
      photoDescriptions: photoDescriptions,
      isShort: isShort,
    );
  }
}
