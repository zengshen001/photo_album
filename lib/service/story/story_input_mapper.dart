import '../../models/entity/photo_entity.dart';
import '../../utils/story/story_prompt_helper.dart';

/// Maps selected photos into prompt-ready story input.
class StoryInputMapper {
  const StoryInputMapper._();

  static StoryPromptInput build(List<PhotoEntity> photos) {
    final sortedPhotos = List<PhotoEntity>.from(photos)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final locationMode = _detectLocationMode(sortedPhotos);
    final photoDescriptions = StoryPromptHelper.buildPhotoDescriptions(
      sortedPhotos,
    );
    return StoryPromptInput(
      sortedPhotos: sortedPhotos,
      locationMode: locationMode,
      photoDescriptions: photoDescriptions,
    );
  }

  static String _detectLocationMode(List<PhotoEntity> photos) {
    final hasAddress = photos.any(
      (photo) =>
          (photo.formattedAddress?.trim().isNotEmpty ?? false) ||
          (photo.district?.trim().isNotEmpty ?? false),
    );
    if (hasAddress) {
      return 'address';
    }

    final hasGps = photos.any(
      (photo) => photo.latitude != null && photo.longitude != null,
    );
    if (hasGps) {
      return 'gps';
    }

    return 'time-tag-only';
  }
}

class StoryPromptInput {
  final List<PhotoEntity> sortedPhotos;
  final String locationMode;
  final List<String> photoDescriptions;

  const StoryPromptInput({
    required this.sortedPhotos,
    required this.locationMode,
    required this.photoDescriptions,
  });
}
