enum StoryEditBlockType { text, image, mixed }

class StoryEditBlock {
  const StoryEditBlock({
    required this.type,
    this.text = '',
    this.photoId,
    required this.order,
  });

  final StoryEditBlockType type;
  final String text;
  final int? photoId;
  final int order;

  bool get hasText => text.trim().isNotEmpty;
  bool get hasPhoto => photoId != null;

  StoryEditBlock withPhoto(int newPhotoId) {
    return copyWith(
      photoId: newPhotoId,
      type: hasText ? StoryEditBlockType.mixed : StoryEditBlockType.image,
    );
  }

  StoryEditBlock withoutPhoto() {
    return copyWith(photoId: null, type: StoryEditBlockType.text);
  }

  StoryEditBlock copyWith({
    StoryEditBlockType? type,
    String? text,
    Object? photoId = _sentinel,
    int? order,
  }) {
    return StoryEditBlock(
      type: type ?? this.type,
      text: text ?? this.text,
      photoId: identical(photoId, _sentinel) ? this.photoId : photoId as int?,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'text': text,
      'photoId': photoId,
      'order': order,
    };
  }

  factory StoryEditBlock.fromJson(Map<String, dynamic> json) {
    final typeName = (json['type'] as String? ?? StoryEditBlockType.text.name)
        .trim();
    final type = StoryEditBlockType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => StoryEditBlockType.text,
    );

    return StoryEditBlock(
      type: type,
      text: (json['text'] as String? ?? '').trimRight(),
      photoId: json['photoId'] as int?,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }

  static List<StoryEditBlock> normalizeOrder(Iterable<StoryEditBlock> blocks) {
    return blocks
        .toList()
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(order: entry.key))
        .toList();
  }
}

const Object _sentinel = Object();
