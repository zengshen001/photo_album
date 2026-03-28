import 'dart:convert';

import 'package:isar/isar.dart';

import 'photo_entity.dart';
import '../vo/photo.dart';
import '../vo/story_edit_block.dart';

part 'story_entity.g.dart';

/// 故事实体 - 存储用户生成的故事文章
@Collection()
class StoryEntity {
  Id id = Isar.autoIncrement;

  // 📝 故事基本信息
  late String title; // 故事主题/标题
  late String subtitle; // 副标题/切入点
  late String content; // Markdown 格式内容（含图片占位符）
  String? contentJson; // 结构化图文编辑数据
  late int createdAt; // 创建时间戳
  late int updatedAt; // 更新时间戳

  // 🔗 关联信息
  late int eventId; // 来源事件 ID
  List<int> photoIds = []; // 选中的照片 ID 列表（按时间顺序）

  // 🎨 元数据
  int photoCount = 0; // 照片数量（冗余字段）
  bool isLlmGenerated = true; // 是否由 LLM 生成

  // 📅 格式化创建时间
  String get createdAtText {
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 🔄 工厂方法：从事件和选中照片创建故事
  static StoryEntity create({
    required String title,
    required String subtitle,
    required String content,
    required int eventId,
    required List<int> photoIds,
    String? contentJson,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return StoryEntity()
      ..title = title
      ..subtitle = subtitle
      ..content = content
      ..contentJson = contentJson
      ..createdAt = now
      ..updatedAt = now
      ..eventId = eventId
      ..photoIds = photoIds
      ..photoCount = photoIds.length
      ..isLlmGenerated = true;
  }

  List<StoryEditBlock> resolveEditBlocks() {
    final fromJson = decodeEditBlocks(contentJson);
    if (fromJson.isNotEmpty) {
      return StoryEditBlock.normalizeOrder(fromJson);
    }
    return parseMarkdownToBlocks(content: content, photoIds: photoIds);
  }

  void syncStructuredContent(List<StoryEditBlock> blocks) {
    final normalizedBlocks = StoryEditBlock.normalizeOrder(blocks);
    photoIds = derivePhotoIds(normalizedBlocks);
    photoCount = photoIds.length;
    contentJson = encodeEditBlocks(normalizedBlocks);
    content = blocksToMarkdown(normalizedBlocks);
  }

  List<Map<String, dynamic>> parseToSections(List<PhotoEntity> photos) {
    final photoById = {for (final photo in photos) photo.id: photo};
    final sections = <Map<String, dynamic>>[];

    for (final block in resolveEditBlocks()) {
      final photoId = block.photoId;
      final photoEntity = photoId == null ? null : photoById[photoId];
      if (photoEntity == null) {
        continue;
      }

      sections.add({
        'text': block.text.trim(),
        'photo': _convertToPhoto(photoEntity),
        'photoId': photoEntity.id,
      });
    }

    if (sections.isNotEmpty) {
      return sections;
    }

    final legacySections = <Map<String, dynamic>>[];
    final lines = content.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();

      final imgMatch = RegExp(r'!\[img\]\((\d+)\)').firstMatch(trimmed);

      if (imgMatch != null) {
        if (buffer.isNotEmpty) {
          final indexStr = imgMatch.group(1);
          final index = int.tryParse(indexStr ?? '0') ?? 0;

          if (index < photos.length) {
            final photoEntity = photos[index];
            legacySections.add({
              'text': buffer.toString().trim(),
              'photo': _convertToPhoto(photoEntity),
              'photoId': photoEntity.id,
            });
          }
          buffer.clear();
        }
      } else if (trimmed.isNotEmpty) {
        buffer.writeln(line);
      }
    }

    if (buffer.isNotEmpty && legacySections.isNotEmpty) {
      final lastSection = legacySections.last;
      legacySections[legacySections.length - 1] = {
        'text': '${lastSection['text']}\n\n${buffer.toString().trim()}',
        'photo': lastSection['photo'],
        'photoId': lastSection['photoId'],
      };
    }

    return legacySections;
  }

  static String sectionsToMarkdown(List<Map<String, dynamic>> sections) {
    final blocks = sections
        .asMap()
        .entries
        .map(
          (entry) => StoryEditBlock(
            type: StoryEditBlockType.mixed,
            text: (entry.value['text'] as String? ?? '').trim(),
            photoId: entry.value['photoId'] as int?,
            order: entry.key,
          ),
        )
        .toList();
    return blocksToMarkdown(blocks);
  }

  static List<StoryEditBlock> parseMarkdownToBlocks({
    required String content,
    required List<int> photoIds,
  }) {
    final blocks = <StoryEditBlock>[];
    final lines = content.split('\n');
    final textBuffer = <String>[];

    void flushText() {
      final text = textBuffer.join('\n').trim();
      if (text.isEmpty) {
        textBuffer.clear();
        return;
      }
      blocks.add(
        StoryEditBlock(
          type: StoryEditBlockType.text,
          text: text,
          order: blocks.length,
        ),
      );
      textBuffer.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      final imgMatch = RegExp(r'!\[img\]\((\d+)\)').firstMatch(trimmed);
      if (imgMatch != null) {
        flushText();
        final index = int.tryParse(imgMatch.group(1) ?? '') ?? -1;
        final photoId = (index >= 0 && index < photoIds.length)
            ? photoIds[index]
            : null;
        blocks.add(
          StoryEditBlock(
            type: StoryEditBlockType.image,
            photoId: photoId,
            order: blocks.length,
          ),
        );
        continue;
      }
      textBuffer.add(line);
    }

    flushText();

    return StoryEditBlock.normalizeOrder(
      blocks.where((block) => block.hasText || block.hasPhoto),
    );
  }

  static String encodeEditBlocks(List<StoryEditBlock> blocks) {
    return jsonEncode(blocks.map((block) => block.toJson()).toList());
  }

  static List<StoryEditBlock> decodeEditBlocks(String? contentJson) {
    if (contentJson == null || contentJson.trim().isEmpty) {
      return const <StoryEditBlock>[];
    }

    try {
      final decoded = jsonDecode(contentJson);
      if (decoded is! List) {
        return const <StoryEditBlock>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => StoryEditBlock.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .where((block) => block.hasText || block.hasPhoto)
          .toList();
    } catch (_) {
      return const <StoryEditBlock>[];
    }
  }

  static List<int> derivePhotoIds(List<StoryEditBlock> blocks) {
    final result = <int>[];
    for (final block in blocks) {
      final photoId = block.photoId;
      if (photoId == null || result.contains(photoId)) {
        continue;
      }
      result.add(photoId);
    }
    return result;
  }

  static String blocksToMarkdown(List<StoryEditBlock> blocks) {
    final normalizedBlocks = StoryEditBlock.normalizeOrder(blocks);
    final orderedPhotoIds = derivePhotoIds(normalizedBlocks);
    final buffer = StringBuffer();

    for (final block in normalizedBlocks) {
      final text = block.text.trim();
      if (text.isNotEmpty) {
        buffer.writeln(text);
        buffer.writeln();
      }

      final photoId = block.photoId;
      if (photoId != null) {
        final index = orderedPhotoIds.indexOf(photoId);
        if (index >= 0) {
          buffer.writeln('![img]($index)');
          buffer.writeln();
        }
      }
    }

    return buffer.toString().trim();
  }

  // 🔄 PhotoEntity 转换为 Photo (UI 模型)
  static Photo _convertToPhoto(PhotoEntity entity) {
    return Photo(
      id: entity.assetId,
      path: entity.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
      tags: entity.aiTags ?? [],
      location: entity.city ?? entity.province,
    );
  }
}
