import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/vo/story_edit_block.dart';
import '../../models/vo/story_template_context.dart';
import '../../models/story_length.dart';
import '../../models/story_theme_selection.dart';
import '../../utils/story/story_prompt_helper.dart';
import '../photo/photo_service.dart';
import '../ai/llm_service.dart';
import '../event/event_service.dart';
import 'story_input_mapper.dart';

/// 故事服务 - 管理故事的生成和存储
class StoryService {
  static final StoryService _instance = StoryService._internal();
  factory StoryService() => _instance;
  StoryService._internal();

  /// 📝 核心方法：生成故事
  ///
  /// 参数:
  /// - [event]: 事件实体
  /// - [selectedPhotos]: 用户选中的照片列表
  /// - [selection]: 结构化主题选择
  /// - [length]: 故事篇幅（短/中）
  /// - [templateStoryId]: 作为模版的已保存故事 ID（可选）
  ///
  /// 返回: 生成的故事实体（失败返回 null）
  Future<StoryEntity?> generateStory({
    required EventEntity event,
    required List<PhotoEntity> selectedPhotos,
    required StoryThemeSelection selection,
    required StoryLength length,
    int? templateStoryId,
  }) async {
    try {
      if (!_canGenerateStory(event: event, selectedPhotos: selectedPhotos)) {
        return null;
      }

      // 1. 加载最新照片信息，保证 prompt 可读取最新地址字段（formattedAddress 等）
      final latestPhotos = await _loadLatestPhotosForPrompt(selectedPhotos);

      // 2. 统一输入映射：排序、位置模式判定、描述构建
      final promptInput = StoryInputMapper.build(latestPhotos);
      _logPromptInput(promptInput);
      final templateContext = templateStoryId == null
          ? null
          : await _loadTemplateStoryContext(templateStoryId);

      // 3. 调用 LLM 生成故事内容
      final content = await _generateStoryContent(
        selection: selection,
        event: event,
        photoDescriptions: promptInput.photoDescriptions,
        length: length,
        locationMode: promptInput.locationMode,
        templateContext: templateContext,
      );

      if (content == null) {
        print("❌ LLM 生成失败");
        return null;
      }

      final story = _buildStoryDraft(
        title: selection.normalizedThemeTitle,
        subtitle: '',
        content: content,
        eventId: event.id,
        photoIds: promptInput.sortedPhotos.map((p) => p.id).toList(),
      );
      print("✅ 故事初稿生成成功");
      return story;
    } catch (e) {
      print("❌ 故事生成异常: $e");
      return null;
    }
  }

  bool _canGenerateStory({
    required EventEntity event,
    required List<PhotoEntity> selectedPhotos,
  }) {
    if (event.photoCount < EventService.minPhotosForDisplay) {
      print(
        "⚠️ 事件照片数(${event.photoCount})低于展示阈值(${EventService.minPhotosForDisplay})，跳过故事生成",
      );
      return false;
    }
    if (selectedPhotos.isEmpty) {
      print("⚠️ 没有选中照片，无法生成故事");
      return false;
    }
    return true;
  }

  void _logPromptInput(StoryPromptInput promptInput) {
    print("📍 故事位置线索模式: ${promptInput.locationMode}");
    print("📝 开始生成故事：${promptInput.sortedPhotos.length} 张照片");
  }

  StoryEntity _buildStoryDraft({
    required String title,
    required String subtitle,
    required String content,
    required int eventId,
    required List<int> photoIds,
  }) {
    final blocks = StoryEntity.parseMarkdownToBlocks(
      content: content,
      photoIds: photoIds,
    );
    return StoryEntity.create(
      title: title,
      subtitle: subtitle,
      content: content,
      contentJson: StoryEntity.encodeEditBlocks(blocks),
      eventId: eventId,
      photoIds: photoIds,
    );
  }

  Future<StoryEntity> createStoryFromDraft({
    required StoryEntity story,
    required List<StoryEditBlock> blocks,
  }) async {
    final payload = buildSavePayload(blocks);
    final created = StoryEntity.create(
      title: story.title,
      subtitle: story.subtitle,
      content: payload.content,
      contentJson: payload.contentJson,
      eventId: story.eventId,
      photoIds: payload.photoIds,
    )..isLlmGenerated = story.isLlmGenerated;

    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      await isar.collection<StoryEntity>().put(created);
    });
    print("💾 故事已保存：ID=${created.id}");
    return created;
  }

  Future<List<PhotoEntity>> _loadLatestPhotosForPrompt(
    List<PhotoEntity> selectedPhotos,
  ) async {
    final isar = PhotoService().isar;
    final selectedIds = selectedPhotos.map((photo) => photo.id).toList();
    final latest = await isar
        .collection<PhotoEntity>()
        .where()
        .anyOf(selectedIds, (q, id) => q.idEqualTo(id))
        .findAll();
    if (latest.isEmpty) {
      return selectedPhotos;
    }

    final latestById = {for (final photo in latest) photo.id: photo};
    return selectedPhotos
        .map((photo) => latestById[photo.id] ?? photo)
        .toList();
  }

  Future<StoryTemplateContext?> _loadTemplateStoryContext(
    int templateStoryId,
  ) async {
    final isar = PhotoService().isar;
    final story = await isar.collection<StoryEntity>().get(templateStoryId);
    if (story == null) {
      return null;
    }

    final relatedPhotos = story.photoIds.isEmpty
        ? <PhotoEntity>[]
        : await isar
              .collection<PhotoEntity>()
              .where()
              .anyOf(story.photoIds, (q, id) => q.idEqualTo(id))
              .findAll();

    final photoById = {for (final photo in relatedPhotos) photo.id: photo};
    final orderedPhotos = story.photoIds
        .map((id) => photoById[id])
        .whereType<PhotoEntity>()
        .map(
          (photo) => StoryTemplatePhotoContext(
            photoId: photo.id,
            tags: List<String>.from(photo.aiTags ?? const []),
            caption: photo.caption,
            formattedAddress: photo.formattedAddress,
          ),
        )
        .toList();

    return StoryTemplateContext(
      storyId: story.id,
      title: story.title,
      content: story.content,
      photos: orderedPhotos,
    );
  }

  /// 🤖 调用 LLM 生成故事内容
  Future<String?> _generateStoryContent({
    required StoryThemeSelection selection,
    required EventEntity event,
    required List<String> photoDescriptions,
    required StoryLength length,
    required String locationMode,
    StoryTemplateContext? templateContext,
  }) async {
    final llmService = LLMService();

    // 检查是否配置了 API Key
    if (!llmService.isApiKeyConfigured) {
      print("⚠️ LLM API Key 未配置，使用模拟模式");
      final mock = await _generateMockStoryContent(
        selection,
        photoDescriptions,
        length,
        templateContext,
      );
      print("===== STORY AI RESPONSE (MOCK) =====");
      print(mock);
      print("====================================");
      return mock;
    }

    try {
      // 构造 Prompt
      final prompt = StoryPromptHelper.buildStoryPrompt(
        selection: selection,
        event: event,
        photoDescriptions: photoDescriptions,
        isShort: length == StoryLength.short,
        locationMode: locationMode,
        templateContext: templateContext,
      );
      print("===== STORY AI REQUEST =====");
      print("theme: ${selection.normalizedThemeTitle}");
      if (templateContext != null) {
        print("templateStory: ${templateContext.title}");
      }
      print("length: ${length.name}");
      print("locationMode: $locationMode");
      print("prompt:\n$prompt");
      print("============================");

      // 调用第三方中转站 LLM API
      final content = await llmService.generateBlogText(prompt);
      print("===== STORY AI RESPONSE =====");
      print(content ?? 'null');
      print("=============================");

      return content;
    } catch (e) {
      print("❌ LLM 调用失败: $e，回退到模拟模式");
      return _generateMockStoryContent(
        selection,
        photoDescriptions,
        length,
        templateContext,
      );
    }
  }

  /// 🧪 模拟模式：生成假的故事内容（用于开发测试）
  Future<String> _generateMockStoryContent(
    StoryThemeSelection selection,
    List<String> photoDescriptions,
    StoryLength length,
    StoryTemplateContext? templateContext,
  ) async {
    return StoryPromptHelper.generateMockStoryContent(
      selection: selection,
      photoDescriptions: photoDescriptions,
      isShort: length == StoryLength.short,
      templateTitle: templateContext?.title,
    );
  }

  /// 📊 获取所有故事
  Future<List<StoryEntity>> getAllStories() async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryEntity>()
        .where()
        .sortByCreatedAtDesc()
        .findAll();
  }

  Stream<List<StoryEntity>> watchStories() {
    final isar = PhotoService().isar;
    return isar
        .collection<StoryEntity>()
        .where()
        .watch(fireImmediately: true)
        .map((stories) {
          final sorted = List<StoryEntity>.from(stories)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return sorted;
        });
  }

  /// 🔍 根据事件 ID 获取故事
  Future<List<StoryEntity>> getStoriesByEventId(int eventId) async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryEntity>()
        .filter()
        .eventIdEqualTo(eventId)
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 💾 更新故事内容（保存编辑）
  Future<bool> updateStory(StoryEntity story) async {
    final isar = PhotoService().isar;
    story.updatedAt = DateTime.now().millisecondsSinceEpoch;

    await isar.writeTxn(() async {
      await isar.collection<StoryEntity>().put(story);
    });

    print("💾 故事已更新：ID=${story.id}");
    return true;
  }

  StorySavePayload buildSavePayload(List<StoryEditBlock> blocks) {
    final normalizedBlocks = StoryEditBlock.normalizeOrder(blocks);
    return StorySavePayload(
      contentJson: StoryEntity.encodeEditBlocks(normalizedBlocks),
      content: StoryEntity.blocksToMarkdown(normalizedBlocks),
      photoIds: StoryEntity.derivePhotoIds(normalizedBlocks),
    );
  }

  Future<bool> updateStoryDraft({
    required StoryEntity story,
    required List<StoryEditBlock> blocks,
  }) async {
    final snapshot = StorySnapshot.capture(story);
    final payload = buildSavePayload(blocks);
    final isar = PhotoService().isar;

    try {
      final hasNoContentChange =
          story.title.trim() == snapshot.title &&
          payload.content == story.content &&
          payload.contentJson == (story.contentJson ?? '') &&
          _listEquals(payload.photoIds, story.photoIds);
      if (hasNoContentChange) {
        print("ℹ️ 故事草稿无变化，跳过写入：ID=${story.id}");
        return true;
      }

      story.contentJson = payload.contentJson;
      story.content = payload.content;
      story.title = story.title.trim();
      story.photoIds = payload.photoIds;
      story.photoCount = payload.photoIds.length;
      story.updatedAt = DateTime.now().millisecondsSinceEpoch;

      await isar.writeTxn(() async {
        await isar.collection<StoryEntity>().put(story);
      });

      print("💾 故事草稿已更新：ID=${story.id}");
      return true;
    } catch (e) {
      snapshot.restore(story);
      print("❌ 故事草稿保存失败，已回滚：$e");
      return false;
    }
  }

  Future<bool> deleteStory(Id storyId) async {
    final isar = PhotoService().isar;
    try {
      await isar.writeTxn(() async {
        await isar.collection<StoryEntity>().delete(storyId);
      });
      print("🗑️ 故事已删除：ID=$storyId");
      return true;
    } catch (e) {
      print("❌ 故事删除失败：$e");
      return false;
    }
  }

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  /// 📸 根据 photoIds 加载照片实体
  Future<List<PhotoEntity>> loadPhotos(List<int> photoIds) async {
    final isar = PhotoService().isar;
    final photos = await isar
        .collection<PhotoEntity>()
        .where()
        .anyOf(photoIds, (q, id) => q.idEqualTo(id))
        .sortByTimestamp()
        .findAll();

    // 优先基于 assetId 解析当前可用路径，避免读取临时文件失效
    for (final photo in photos) {
      final asset = await AssetEntity.fromId(photo.assetId);
      final file = await asset?.file;
      final latestPath = file?.path;
      if (latestPath != null &&
          latestPath.isNotEmpty &&
          latestPath != photo.path) {
        photo.path = latestPath;
      }
    }

    await isar.writeTxn(() async {
      await isar.collection<PhotoEntity>().putAll(photos);
    });

    return photos;
  }
}

class StorySavePayload {
  const StorySavePayload({
    required this.contentJson,
    required this.content,
    required this.photoIds,
  });

  final String contentJson;
  final String content;
  final List<int> photoIds;
}

class StorySnapshot {
  const StorySnapshot({
    required this.title,
    required this.content,
    required this.contentJson,
    required this.photoIds,
    required this.photoCount,
    required this.updatedAt,
  });

  final String title;
  final String content;
  final String? contentJson;
  final List<int> photoIds;
  final int photoCount;
  final int updatedAt;

  factory StorySnapshot.capture(StoryEntity story) {
    return StorySnapshot(
      title: story.title,
      content: story.content,
      contentJson: story.contentJson,
      photoIds: List<int>.from(story.photoIds),
      photoCount: story.photoCount,
      updatedAt: story.updatedAt,
    );
  }

  void restore(StoryEntity story) {
    story.title = title;
    story.content = content;
    story.contentJson = contentJson;
    story.photoIds = List<int>.from(photoIds);
    story.photoCount = photoCount;
    story.updatedAt = updatedAt;
  }
}
