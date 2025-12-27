import 'package:isar/isar.dart';
import '../models/entity/story_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import 'photo_service.dart';
import 'llm_service.dart';
import '../view/pages/config_page.dart'; // for StoryLength enum

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
  /// - [title]: 故事主题/标题
  /// - [subtitle]: 副标题/切入点
  /// - [length]: 故事篇幅（短/中）
  ///
  /// 返回: 生成的故事实体（失败返回 null）
  Future<StoryEntity?> generateStory({
    required EventEntity event,
    required List<PhotoEntity> selectedPhotos,
    required String title,
    required String subtitle,
    required StoryLength length,
  }) async {
    try {
      if (selectedPhotos.isEmpty) {
        print("⚠️ 没有选中照片，无法生成故事");
        return null;
      }

      // 1. 按时间顺序排序照片（确保故事的连贯性）
      final sortedPhotos = List<PhotoEntity>.from(selectedPhotos)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      print("📝 开始生成故事：${sortedPhotos.length} 张照片");

      // 2. 构造照片描述文本（供 LLM 理解）
      final photoDescriptions = _buildPhotoDescriptions(sortedPhotos);

      // 3. 调用 LLM 生成故事内容
      final content = await _generateStoryContent(
        title: title,
        subtitle: subtitle,
        event: event,
        photoDescriptions: photoDescriptions,
        length: length,
      );

      if (content == null) {
        print("❌ LLM 生成失败");
        return null;
      }

      // 4. 创建并保存故事实体
      final story = StoryEntity.create(
        title: title,
        subtitle: subtitle,
        content: content,
        eventId: event.id,
        photoIds: sortedPhotos.map((p) => p.id).toList(),
      );

      // 保存到数据库
      final isar = PhotoService().isar;
      await isar.writeTxn(() async {
        await isar.collection<StoryEntity>().put(story);
      });

      print("✅ 故事生成成功：ID=${story.id}");
      return story;
    } catch (e) {
      print("❌ 故事生成异常: $e");
      return null;
    }
  }

  /// 📝 构造照片描述文本
  List<String> _buildPhotoDescriptions(List<PhotoEntity> photos) {
    final descriptions = <String>[];
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final time = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      final timeStr = '${time.month}月${time.day}日 ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
      final tags = photo.aiTags?.join(', ') ?? '无标签';
      final location = photo.city ?? photo.province ?? '';

      final desc = "Image $i: 拍摄于 $timeStr${location.isNotEmpty ? '，地点：$location' : ''}，标签：$tags";
      descriptions.add(desc);
    }
    return descriptions;
  }

  /// 🤖 调用 LLM 生成故事内容
  Future<String?> _generateStoryContent({
    required String title,
    required String subtitle,
    required EventEntity event,
    required List<String> photoDescriptions,
    required StoryLength length,
  }) async {
    final llmService = LLMService();

    // 检查是否配置了 API Key
    if (!llmService.isApiKeyConfigured) {
      print("⚠️ Gemini API Key 未配置，使用模拟模式");
      return _generateMockStoryContent(title, subtitle, photoDescriptions, length);
    }

    try {
      // 构造 Prompt
      final prompt = _buildStoryPrompt(title, subtitle, event, photoDescriptions, length);

      // 调用 Gemini API
      final content = await llmService.generateBlogText(prompt);

      return content;
    } catch (e) {
      print("❌ LLM 调用失败: $e，回退到模拟模式");
      return _generateMockStoryContent(title, subtitle, photoDescriptions, length);
    }
  }

  /// 📝 构造 LLM Prompt
  String _buildStoryPrompt(
    String title,
    String subtitle,
    EventEntity event,
    List<String> photoDescriptions,
    StoryLength length,
  ) {
    final location = event.city ?? event.province ?? '某地';
    final dateStart = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateEnd = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    final dateRange = dateStart.month == dateEnd.month && dateStart.day == dateEnd.day
        ? '${dateStart.month}月${dateStart.day}日'
        : '${dateStart.month}月${dateStart.day}日 - ${dateEnd.month}月${dateEnd.day}日';

    final wordCount = length == StoryLength.short ? '150-250' : '300-500';
    final minImages = (photoDescriptions.length / 2).ceil();

    return '''
你是一位专业的生活记录博客作家。请根据以下信息撰写一篇第一人称的故事/博客。

故事主题：$title
副标题/切入点：$subtitle
事件时间：$dateRange
地点：$location

照片描述（共 ${photoDescriptions.length} 张）：
${photoDescriptions.map((d) => '- $d').join('\n')}

要求：
1. 使用第一人称叙述（"我"、"我们"）
2. 文章长度：$wordCount 字
3. 分成 2-4 个自然段落
4. **重要**：在合适的位置插入图片占位符 `![img](index)`，其中 index 是照片编号（0 到 ${photoDescriptions.length - 1}）
5. 图片占位符应该独立成行，前后留空行
6. 至少插入 $minImages 张图片
7. 文字要有画面感和情感，体现"$subtitle"的主题
8. 使用 Markdown 格式
9. 每个段落之后紧跟一张相关的照片
10. 不要添加标题（我们会在UI中单独显示）

示例格式：
第一段文字内容...

![img](0)

第二段文字内容...

![img](1)

请生成故事正文（不包括标题）：
''';
  }

  /// 🧪 模拟模式：生成假的故事内容（用于开发测试）
  Future<String> _generateMockStoryContent(
    String title,
    String subtitle,
    List<String> photoDescriptions,
    StoryLength length,
  ) async {
    // 模拟网络延迟
    await Future.delayed(const Duration(seconds: 2));

    final buffer = StringBuffer();
    final isShort = length == StoryLength.short;

    buffer.writeln('今天是个特别的日子，我们开启了一段关于"$title"的旅程。$subtitle，每一刻都值得珍藏。\n');

    if (photoDescriptions.isNotEmpty) {
      buffer.writeln('![img](0)\n');
    }

    buffer.writeln('一路走来，看到了许多美丽的风景。阳光洒在身上，微风轻拂，心情格外舒畅。\n');

    // 短篇只插入 2-3 张图片，中篇插入更多
    final step = isShort ? 2 : 1;
    for (int i = 1; i < photoDescriptions.length; i += step) {
      buffer.writeln('![img]($i)\n');

      if (i < photoDescriptions.length - 1) {
        buffer.writeln('时光飞逝，但这些美好的瞬间将永远留在心中。每一个画面都诉说着不同的故事。\n');
      }
    }

    if (photoDescriptions.length > 1 && !isShort) {
      buffer.writeln('![img](${photoDescriptions.length - 1})\n');
    }

    buffer.writeln('这是一段美好的回忆，期待下一次的相遇。');

    return buffer.toString();
  }

  /// 📊 获取所有故事
  Future<List<StoryEntity>> getAllStories() async {
    final isar = PhotoService().isar;
    return await isar.collection<StoryEntity>()
        .where()
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 🔍 根据事件 ID 获取故事
  Future<List<StoryEntity>> getStoriesByEventId(int eventId) async {
    final isar = PhotoService().isar;
    return await isar.collection<StoryEntity>()
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

  /// 🗑️ 删除故事
  Future<bool> deleteStory(int storyId) async {
    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      await isar.collection<StoryEntity>().delete(storyId);
    });
    print("🗑️ 故事已删除：ID=$storyId");
    return true;
  }

  /// 📸 根据 photoIds 加载照片实体
  Future<List<PhotoEntity>> loadPhotos(List<int> photoIds) async {
    final isar = PhotoService().isar;
    final photos = await isar.collection<PhotoEntity>()
        .where()
        .anyOf(photoIds, (q, id) => q.idEqualTo(id))
        .sortByTimestamp()
        .findAll();
    return photos;
  }
}
