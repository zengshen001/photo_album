class StoryTemplateContext {
  final int storyId;
  final String title;
  final String content;
  final List<StoryTemplatePhotoContext> photos;

  const StoryTemplateContext({
    required this.storyId,
    required this.title,
    required this.content,
    required this.photos,
  });
}

class StoryTemplatePhotoContext {
  final int photoId;
  final List<String> tags;
  final String? caption;
  final String? formattedAddress;

  const StoryTemplatePhotoContext({
    required this.photoId,
    required this.tags,
    required this.caption,
    required this.formattedAddress,
  });

  String toPromptLine() {
    final parts = <String>['图片$photoId'];
    if (tags.isNotEmpty) {
      parts.add('tags: ${tags.join('、')}');
    }
    if (caption != null && caption!.trim().isNotEmpty) {
      parts.add('caption: ${caption!.trim()}');
    }
    if (formattedAddress != null && formattedAddress!.trim().isNotEmpty) {
      parts.add('formattedAddress: ${formattedAddress!.trim()}');
    }
    return parts.join(' | ');
  }
}
