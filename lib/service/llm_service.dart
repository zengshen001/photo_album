import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/entity/event_entity.dart';

/// LLM 服务 - 使用 Google Gemini API 生成创意标题
class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  // 🔑 Gemini API Key（请在这里填入你的 API Key）
  // 获取方式：https://makersuite.google.com/app/apikey
  static const String _apiKey = "YOUR_GEMINI_API_KEY_HERE";

  // 配置 Gemini 模型
  static const String _modelName = "gemini-1.5-flash"; // 使用快速模型

  /// 🎨 核心方法：生成创意标题
  ///
  /// 参数:
  /// - [event]: 事件实体
  /// - [topTags]: 高频标签列表（前5个）
  ///
  /// 返回: 3-5 个博客风格的创意标题列表
  Future<List<String>> generateCreativeTitles(
    EventEntity event,
    List<String> topTags,
  ) async {
    try {
      // 1. 构造 Prompt
      final prompt = _buildPrompt(event, topTags);

      // 2. 调用 Gemini API
      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
      );

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      // 3. 解析返回结果
      final text = response.text;
      if (text == null || text.isEmpty) {
        print("⚠️ LLM 返回为空，使用兜底逻辑");
        return _getFallbackTitles(event);
      }

      // 4. 清洗文本（去除引号、编号等）
      final titles = _parseResponse(text);

      if (titles.isEmpty) {
        print("⚠️ LLM 解析失败，使用兜底逻辑");
        return _getFallbackTitles(event);
      }

      print("✅ LLM 成功生成 ${titles.length} 个标题");
      return titles;
    } catch (e) {
      print("❌ LLM 调用失败: $e");
      // 网络错误或 API 错误，返回兜底标题
      return _getFallbackTitles(event);
    }
  }

  /// 📝 构造 Prompt
  String _buildPrompt(EventEntity event, List<String> topTags) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateStr =
        '${date.year}年${date.month}月${date.day}日 - ${DateTime.fromMillisecondsSinceEpoch(event.endTime).month}月${DateTime.fromMillisecondsSinceEpoch(event.endTime).day}日';

    final location = event.city ?? event.province ?? '未知地点';
    final season = event.season;
    final tagsStr = topTags.isNotEmpty ? topTags.join(', ') : '无';
    final joyScore =
        event.joyScore != null ? event.joyScore!.toStringAsFixed(2) : '未知';

    return '''
你是一个专业的摄影相册文案策划师。请为以下照片事件生成 3 到 5 个简短、富有创意、博客风格的中文标题。

事件信息：
- 时间: $dateStr
- 地点: $location
- 季节: $season
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

  /// 🔍 解析 LLM 返回的文本
  List<String> _parseResponse(String text) {
    // 按行分割
    final lines = text.split('\n');

    // 清洗每一行
    final titles = <String>[];
    for (final line in lines) {
      var cleaned = line.trim();

      // 跳过空行
      if (cleaned.isEmpty) continue;

      // 移除编号（1. 2. 一、二、等）
      cleaned = cleaned.replaceFirst(RegExp(r'^[\d]+\.?\s+'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'^[一二三四五六七八九十]+[、.\s]+'), '');

      // 移除前后引号
      if (cleaned.startsWith('"') || cleaned.startsWith("'")) {
        cleaned = cleaned.substring(1);
      }
      if (cleaned.endsWith('"') || cleaned.endsWith("'")) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }

      // 移除多余空格
      cleaned = cleaned.trim();

      // 跳过过长或过短的标题
      if (cleaned.length < 3 || cleaned.length > 30) continue;

      titles.add(cleaned);
    }

    // 限制返回数量（3-5 个）
    return titles.take(5).toList();
  }

  /// 🛡️ 兜底标题生成（当 LLM 失败时）
  List<String> _getFallbackTitles(EventEntity event) {
    final location = event.city ?? event.province ?? '未知地点';
    final dateRange = event.dateRangeText;

    return [
      '$location · $dateRange',
      '$location 的记忆',
      '时光印记 · $location',
    ];
  }

  /// 🧪 测试方法：模拟 LLM 调用（用于开发测试，无需真实 API Key）
  Future<List<String>> generateCreativeTitlesMock(
    EventEntity event,
    List<String> topTags,
  ) async {
    // 模拟网络延迟
    await Future.delayed(const Duration(seconds: 1));

    final location = event.city ?? event.province ?? '未知地点';

    // 根据标签生成模拟标题
    if (topTags.contains('美食')) {
      return [
        '$location · 舌尖上的记忆',
        '美食之旅 · $location',
        '寻味 $location',
        '美食地图 · $location',
      ];
    } else if (topTags.contains('海滩') || topTags.contains('大海')) {
      return [
        '$location · 海风与阳光',
        '夏日海边的慢时光',
        '蓝色记忆 · $location',
        '海的呼唤',
      ];
    } else if (topTags.contains('猫') || topTags.contains('狗')) {
      return [
        '毛孩子的快乐时光',
        '萌宠日记 · $location',
        '治愈时刻',
        '毛茸茸的陪伴',
      ];
    } else {
      return [
        '$location · ${event.dateRangeText}',
        '$location 的故事',
        '时光印记',
        '美好瞬间 · $location',
      ];
    }
  }

  /// 📊 检查 API Key 是否已配置
  bool get isApiKeyConfigured =>
      _apiKey.isNotEmpty && _apiKey != "YOUR_GEMINI_API_KEY_HERE";

  /// 📝 生成博客文本内容
  ///
  /// 参数:
  /// - [prompt]: 完整的博客生成 Prompt
  ///
  /// 返回: 生成的 Markdown 格式博客正文
  Future<String?> generateBlogText(String prompt) async {
    try {
      // 调用 Gemini API
      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
      );

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      final text = response.text;
      if (text == null || text.isEmpty) {
        print("⚠️ LLM 返回为空");
        return null;
      }

      print("✅ LLM 成功生成博客内容");
      return text.trim();
    } catch (e) {
      print("❌ LLM 博客生成失败: $e");
      return null;
    }
  }
}
