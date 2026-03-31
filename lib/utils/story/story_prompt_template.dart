import '../../models/entity/event_entity.dart';
import '../../models/story_theme_selection.dart';
import '../../models/vo/story_template_context.dart';

class StoryPromptTemplate {
  const StoryPromptTemplate._();

  static String buildStoryPrompt({
    required StoryThemeSelection selection,
    required EventEntity event,
    required List<String> photoDescriptions,
    required bool isShort,
    required String locationMode,
    StoryTemplateContext? templateContext,
  }) {
    final location = event.city ?? event.province ?? '某地';
    final dateStart = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateEnd = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    final dateRange =
        dateStart.month == dateEnd.month && dateStart.day == dateEnd.day
        ? '${dateStart.month}月${dateStart.day}日'
        : '${dateStart.month}月${dateStart.day}日 - ${dateEnd.month}月${dateEnd.day}日';

    final wordCount = isShort ? '200-300' : '400-600';
    final wordCountMin = isShort ? '200' : '400';
    final minImages = (photoDescriptions.length / 2).ceil();
    final eventCenter = event.avgLatitude != null && event.avgLongitude != null
        ? '${event.avgLatitude!.toStringAsFixed(6)},${event.avgLongitude!.toStringAsFixed(6)}'
        : '未知';

    final templatePhotoLines =
        templateContext?.photos
            .map((photo) => '- ${photo.toPromptLine()}')
            .join('\n') ??
        '';

    final templateInfo = templateContext == null
        ? ''
        : '''
选中的模板故事：${templateContext.title}
模板故事ID：${templateContext.storyId}
模板完整正文：
${templateContext.content}
模板关联图片描述：
$templatePhotoLines
请优先参考该故事的叙事节奏、段落组织、图文穿插方式和信息密度来生成新故事，但不要照搬原文。
''';

    return '''
你是一位专业的生活记录博客作家。请根据以下信息撰写一篇第一人称的故事/博客。

故事主题：${selection.normalizedThemeTitle}
主题来源：${selection.source.name}
叙事语气：${selection.tone.label}
事件时间：$dateRange
地点：$location
事件中心坐标：$eventCenter
位置线索模式：$locationMode
$templateInfo

照片描述（共 ${photoDescriptions.length} 张）：
${photoDescriptions.map((d) => '- $d').join('\n')}

要求：
1. 使用第一人称叙述（"我"、"我们"）
2. 文章总字数：**$wordCount 字，最少不得低于 $wordCountMin 字（硬性要求）**
3. 分成 3-5 个自然段落，每段正文不少于 60 字
4. **重要**：在合适的位置插入图片占位符 `![img](index)`，其中 index 是照片编号（0 到 ${photoDescriptions.length - 1}）
5. 图片占位符应该独立成行，前后留空行
6. 至少插入 $minImages 张图片
7. 文字要有画面感和情感，整体语气保持"${selection.tone.label}"
8. 主题“${selection.normalizedThemeTitle}”必须贯穿全文，开头点题，正文持续围绕主题展开，结尾再次回扣主题
9. 若内容容易跑题，优先收束到主题相关的人物、场景、情绪与记忆，不要写成泛泛流水账
10. 使用 Markdown 格式
11. 图片尽量穿插在正文中前段和中段，结尾段落后面不要再放图片，整篇文章不能以图片占位符收尾
12. 不要添加标题（UI 中已单独显示）
13. 若照片有地址/行政区/坐标线索，可据此推断更具体景区或片区
14. 严禁编造未提供的地名；证据不足时使用"附近区域/片区"描述
15. 若位置线索模式为 `time-tag-only`，仅根据时间与标签叙事，不要强行给景区名
16. **自查**：生成完毕后检查字数，若正文不足 $wordCountMin 字，请继续补充段落直到达标

示例格式：
第一段文字内容...

![img](0)

第二段文字内容...

![img](1)

最后一段结尾内容...

请生成故事正文（不包括标题）：
''';
  }
}
