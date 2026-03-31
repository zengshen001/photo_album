import 'package:isar/isar.dart';

part 'story_template_entity.g.dart';

/// 故事模版实体 - 存储预定义的故事模版
@Collection()
class StoryTemplateEntity {
  Id id = Isar.autoIncrement;

  // 📝 模版基本信息
  late String title; // 模版标题
  late String subtitle; // 模版副标题
  late String description; // 模版描述
  late String content; // Markdown 格式内容（含图片占位符）
  String? contentJson; // 结构化图文编辑数据
  late int createdAt; // 创建时间戳
  late int updatedAt; // 更新时间戳

  // 🎨 元数据
  String? thumbnailPhotoId; // 缩略图照片ID
  int photoCount = 0; // 照片数量（冗余字段）
  bool isSystemTemplate = false; // 是否为系统模版

  // 📅 格式化创建时间
  String get createdAtText {
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 🔄 工厂方法：创建故事模版
  static StoryTemplateEntity create({
    required String title,
    required String subtitle,
    required String description,
    required String content,
    String? contentJson,
    String? thumbnailPhotoId,
    bool isSystemTemplate = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return StoryTemplateEntity()
      ..title = title
      ..subtitle = subtitle
      ..description = description
      ..content = content
      ..contentJson = contentJson
      ..createdAt = now
      ..updatedAt = now
      ..thumbnailPhotoId = thumbnailPhotoId
      ..isSystemTemplate = isSystemTemplate;
  }

  // 🔄 复制方法：用于编辑模版
  StoryTemplateEntity copyWith({
    String? title,
    String? subtitle,
    String? description,
    String? content,
    String? contentJson,
    String? thumbnailPhotoId,
    bool? isSystemTemplate,
  }) {
    return StoryTemplateEntity()
      ..id = id
      ..title = title ?? this.title
      ..subtitle = subtitle ?? this.subtitle
      ..description = description ?? this.description
      ..content = content ?? this.content
      ..contentJson = contentJson ?? this.contentJson
      ..createdAt = createdAt
      ..updatedAt = DateTime.now().millisecondsSinceEpoch
      ..thumbnailPhotoId = thumbnailPhotoId ?? this.thumbnailPhotoId
      ..photoCount = photoCount
      ..isSystemTemplate = isSystemTemplate ?? this.isSystemTemplate;
  }
}
