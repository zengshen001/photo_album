import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import 'ocr_feature_flags.dart';

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
    final emotionSummary = _buildEmotionSummary(event);
    final festival = event.isFestivalEvent && event.festivalName != null
        ? event.festivalName
        : '无';
    final sceneTags = event.tags.isEmpty ? '无' : event.tags.join('、');
    final constraints = _buildSceneConstraints(event);
    final titleSpecificConstraints = _buildTitleSpecificConstraints(event);
    final ocrContext = _buildOptionalOcrContext(event);

    return '''
你是一个专业的摄影相册文案策划师。请为以下照片事件生成 3 到 5 个简短、富有创意、博客风格的中文标题。

事件信息：
- 时间: $dateStr
- 地点: $location
- 季节: $season
- 节日标签: $festival
- 场景标签: $sceneTags
- 主要标签: $tagsStr
- 平均欢乐值: $joyScore (范围 0.0-1.0，越高越快乐)
- 事件情绪画像: $emotionSummary
$ocrContext

要求：
1. 标题简洁有力（8-15 个字）
2. 富有情感和画面感
3. 不要使用引号包裹标题
4. 每个标题独占一行
5. 不要添加编号（如 1.、2. 等）
6. 结合地点和标签生成创意标题
7. 可以使用一些诗意或文艺的表达
$constraints
$titleSpecificConstraints

示例风格：
- 青岛 · 海风与微笑
- 舌尖上的成都
- 夏日海边的慢时光
- 猫咪日记 · 治愈时刻

请生成标题：
''';
  }

  static String buildPhotoCaptionPrompt(
    EventEntity event,
    List<PhotoEntity> photos,
  ) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateStr =
        '${date.year}年${date.month}月${date.day}日 - ${DateTime.fromMillisecondsSinceEpoch(event.endTime).month}月${DateTime.fromMillisecondsSinceEpoch(event.endTime).day}日';
    final location = event.city ?? event.province ?? '未知地点';
    final season = event.season;
    final festival = event.isFestivalEvent && event.festivalName != null
        ? event.festivalName
        : '无';
    final sceneTags = event.tags.isEmpty ? '无' : event.tags.join('、');
    final constraints = _buildSceneConstraints(event);
    final emotionSummary = _buildEmotionSummary(event);
    final ocrContext = _buildOptionalOcrContext(event);

    final photoLines = photos
        .map((photo) {
          final t = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
          final timeStr = '${t.month}月${t.day}日 ${t.hour}时';
          final tags = (photo.aiTags ?? const <String>[])
              .where((e) => e.trim().isNotEmpty)
              .take(5)
              .toList();

          final areaParts = [
            photo.province?.trim(),
            photo.city?.trim(),
            photo.district?.trim(),
          ].whereType<String>().where((s) => s.isNotEmpty).toList();
          final areaText = areaParts.isEmpty ? '' : areaParts.join('');

          final address = _sanitizeAddress(photo.formattedAddress);
          final locationText = [
            if (areaText.isNotEmpty) areaText,
            if (address.isNotEmpty) address,
          ].join(' ');

          return '{"photoId":${photo.id},"time":"$timeStr","location":"$locationText","tags":[${tags.map((t) => '"$t"').join(',')}],"faceCount":${photo.faceCount},"smileProb":${photo.smileProb.toStringAsFixed(2)}}';
        })
        .join('\n');

    return '''
你是一个中文摄影故事助手。只能基于输入信息生成，不要编造未提供事实。
请为以下“同一事件”中的每张照片生成一句短 caption（图注），要求：
1. 简洁（8-18字，最多30字）
2. 有画面感但不臆想具体人物身份或不存在的物体
3. 结合事件上下文（时间/地点/季节/节日）与该照片 tags/位置线索生成
4. 不要使用引号包裹 caption
5. 输出严格 JSON 数组，每个元素包含 photoId 与 caption

事件信息：
- 时间: $dateStr
- 地点: $location
- 季节: $season
- 节日标签: $festival
- 场景标签: $sceneTags
- 事件情绪画像: $emotionSummary
$ocrContext
$constraints

照片列表（每行一个 JSON 对象）：
$photoLines

输出示例：
[
  {"photoId": 1, "caption": "海边的清爽午后"},
  {"photoId": 2, "caption": "餐桌上的热气腾腾"}
]
''';
  }

  static String _buildSceneConstraints(EventEntity event) {
    final constraints = <String>[];
    if (event.isFestivalEvent && event.festivalName != null) {
      final festival = event.festivalName!;
      constraints.addAll([
        '本事件命中了节日聚类，节日为「$festival」。',
        '生成内容必须围绕「$festival」的回忆/氛围/场景展开。',
      ]);
    }
    if (event.tags.contains('🎓 毕业季')) {
      constraints.addAll(['本事件命中了场景「毕业季」。', '生成内容必须体现毕业、合照、告别或校园氛围。']);
    }
    if (constraints.isEmpty) {
      return '';
    }
    return '''

特殊约束（必须遵守）：
${constraints.map((item) => '- $item').join('\n')}''';
  }

  static String _buildTitleSpecificConstraints(EventEntity event) {
    final constraints = <String>[];
    if (event.isFestivalEvent && event.festivalName != null) {
      final festival = event.festivalName!;
      constraints.add('你生成的每个标题必须包含「$festival」字样。');
    }
    if (event.tags.contains('🎓 毕业季')) {
      constraints.add('你生成的每个标题必须包含「毕业季」字样。');
    }
    if (constraints.isEmpty) {
      return '';
    }
    return constraints.map((item) => '- $item').join('\n');
  }

  static String _buildEmotionSummary(EventEntity event) {
    final parts = <String>[];
    void addScore(String label, double? value) {
      if (value != null) {
        parts.add('$label=${value.toStringAsFixed(2)}');
      }
    }

    addScore('happy', event.avgHappyScore);
    addScore('calm', event.avgCalmScore);
    addScore('nostalgic', event.avgNostalgicScore);
    addScore('lively', event.avgLivelyScore);
    if (event.dominantEmotion != null && event.dominantEmotion!.isNotEmpty) {
      parts.add('dominant=${event.dominantEmotion}');
    }
    if (event.emotionDiversity != null) {
      parts.add('diversity=${event.emotionDiversity!.toStringAsFixed(2)}');
    }
    return parts.isEmpty ? '未知' : parts.join('，');
  }

  static String _buildOptionalOcrContext(EventEntity event) {
    if (!OcrFeatureFlags.enablePhotoOcr) {
      return '';
    }
    final summary = event.ocrSummary?.trim();
    if (summary == null || summary.isEmpty) {
      return '';
    }
    return '- 事件 OCR 线索: $summary';
  }

  static String _sanitizeAddress(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return '';
    var s = raw.replaceAll(RegExp(r'\d'), 'X');
    s = s.replaceAll(RegExp(r'(号|弄|室|单元|栋|座|楼|层|门牌).*'), r'$1');
    if (s.length > 40) {
      s = s.substring(0, 40);
    }
    return s;
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
        'max_tokens': 1500,
        'temperature': 0.85,
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
