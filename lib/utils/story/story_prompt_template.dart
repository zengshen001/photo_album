import '../../models/entity/event_entity.dart';

class StoryPromptTemplate {
  const StoryPromptTemplate._();

  static String buildStoryPrompt({
    required String title,
    required String subtitle,
    required EventEntity event,
    required List<String> photoDescriptions,
    required bool isShort,
    required String locationMode,
  }) {
    final location = event.city ?? event.province ?? '某地';
    final dateStart = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateEnd = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    final dateRange =
        dateStart.month == dateEnd.month && dateStart.day == dateEnd.day
        ? '${dateStart.month}月${dateStart.day}日'
        : '${dateStart.month}月${dateStart.day}日 - ${dateEnd.month}月${dateEnd.day}日';

    final wordCount = isShort ? '150-250' : '300-500';
    final minImages = (photoDescriptions.length / 2).ceil();
    final eventCenter = event.avgLatitude != null && event.avgLongitude != null
        ? '${event.avgLatitude!.toStringAsFixed(6)},${event.avgLongitude!.toStringAsFixed(6)}'
        : '未知';

    return '''
你是一位专业的生活记录博客作家。请根据以下信息撰写一篇第一人称的故事/博客。

故事主题：$title
副标题/切入点：$subtitle
事件时间：$dateRange
地点：$location
事件中心坐标：$eventCenter
位置线索模式：$locationMode

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
11. 若照片有地址/行政区/坐标线索，可据此推断更具体景区或片区
12. 严禁编造未提供的地名；证据不足时使用“附近区域/片区”描述
13. 若位置线索模式为 `time-tag-only`，仅根据时间与标签叙事，不要强行给景区名

示例格式：
第一段文字内容...

![img](0)

第二段文字内容...

![img](1)

请生成故事正文（不包括标题）：
''';
  }
}
