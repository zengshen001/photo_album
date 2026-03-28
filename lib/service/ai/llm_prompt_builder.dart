import '../../models/entity/event_entity.dart';

class LlmPromptBuilder {
  const LlmPromptBuilder._();

  static const String systemText = '你是一个中文摄影故事与标题助手。只能基于输入信息生成，不要编造未提供事实。';

  static String buildCreativeTitlePrompt(
    EventEntity event,
    List<String> topTags,
  ) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateStr =
        '${date.year}年${date.month}月${date.day}日 - ${DateTime.fromMillisecondsSinceEpoch(event.endTime).month}月${DateTime.fromMillisecondsSinceEpoch(event.endTime).day}日';

    final location = event.city ?? event.province ?? '未知地点';
    final season = event.season;
    final tagsStr = topTags.isNotEmpty ? topTags.join(', ') : '无';
    final joyScore = event.joyScore != null
        ? event.joyScore!.toStringAsFixed(2)
        : '未知';
    final festival = event.isFestivalEvent && event.festivalName != null
        ? event.festivalName
        : '无';

    return '''
你是一个专业的摄影相册文案策划师。请为以下照片事件生成 3 到 5 个简短、富有创意、博客风格的中文标题。

事件信息：
- 时间: $dateStr
- 地点: $location
- 季节: $season
- 节日标签: $festival
- 主要标签: $tagsStr
- 平均欢乐值: $joyScore (范围 0.0-1.0，越高越快乐)

要求：
1. 标题简洁有力（8-15 个字）
2. 富有情感和画面感
3. 不要使用引号包裹标题
4. 每个标题独占一行
5. 不要添加编号（如 1.、2. 等）
6. 结合地点和标签生成创意标题
7. 可以使用一些诗意或文艺的表达

示例风格：
- 青岛 · 海风与微笑
- 舌尖上的成都
- 夏日海边的慢时光
- 猫咪日记 · 治愈时刻

请生成标题：
''';
  }

  static Map<String, dynamic> buildRequestBody({
    required String modelName,
    required String prompt,
    required bool useChatCompletions,
  }) {
    if (useChatCompletions) {
      return {
        'model': modelName,
        'messages': [
          {'role': 'system', 'content': systemText},
          {'role': 'user', 'content': prompt},
        ],
      };
    }

    return {
      'model': modelName,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': systemText},
            {'type': 'input_text', 'text': prompt},
          ],
        },
      ],
    };
  }
}
