import 'package:dio/dio.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import 'llm_client.dart';
import 'llm_error.dart';
import 'llm_prompt_builder.dart';
import 'llm_response_parser.dart';

/// LLM 服务 - 通过 OpenAI 兼容第三方中转站生成内容
class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;

  LLMService._internal({
    String? apiKey,
    String? baseUrl,
    String? apiPath,
    String? modelName,
    Dio? dio,
  }) : _apiKey = apiKey ?? _defaultApiKey,
       _baseUrl = baseUrl ?? _defaultBaseUrl,
       _apiPath = apiPath ?? _defaultApiPath,
       _modelName = modelName ?? _defaultModelName,
       _client = LlmClient(dio: dio);

  factory LLMService.forTest({
    required String apiKey,
    required String baseUrl,
    String apiPath = '/chat/completions',
    String modelName = 'deepseek-ai/DeepSeek-V3.2',
    Dio? dio,
  }) {
    return LLMService._internal(
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      modelName: modelName,
      dio: dio,
    );
  }

  // 通过 --dart-define 配置，避免硬编码凭证
  static const String _defaultApiKey = String.fromEnvironment(
    'LLM_API_KEY',
    defaultValue: '',
  );
  static const String _defaultBaseUrl = String.fromEnvironment(
    'LLM_BASE_URL',
    defaultValue: 'https://api-inference.modelscope.cn/v1',
  );
  static const String _defaultApiPath = String.fromEnvironment(
    'LLM_API_PATH',
    defaultValue: '/chat/completions',
  );
  static const String _defaultModelName = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'deepseek-ai/DeepSeek-V3.2',
  );

  final String _apiKey;
  final String _baseUrl;
  final String _apiPath;
  final String _modelName;
  final LlmClient _client;

  /// 🎨 核心方法：生成创意标题
  Future<List<String>> generateCreativeTitles(
    EventEntity event,
    List<String> topTags,
  ) async {
    try {
      final prompt = LlmPromptBuilder.buildCreativeTitlePrompt(event, topTags);
      final text = await _chatCompletion(prompt);

      if (text == null || text.isEmpty) {
        print("⚠️ LLM 返回为空，使用兜底逻辑");
        return _getFallbackTitles(event);
      }

      final titles = LlmResponseParser.parseTitleLines(text);
      if (titles.isEmpty) {
        print("⚠️ LLM 解析失败，使用兜底逻辑");
        return _getFallbackTitles(event);
      }

      print("✅ LLM 成功生成 ${titles.length} 个标题");
      return titles;
    } on LlmException catch (e) {
      print("❌ LLM 调用失败(${e.type}): ${e.message}");
      return _getFallbackTitles(event);
    } catch (e) {
      print("❌ LLM 调用失败: $e");
      return _getFallbackTitles(event);
    }
  }

  /// 🛡️ 兜底标题生成（当 LLM 失败时）
  List<String> _getFallbackTitles(EventEntity event) {
    final location = event.city ?? event.province ?? '未知地点';
    final dateRange = event.dateRangeText;
    if (event.tags.contains('🎓 毕业季')) {
      return ['毕业季 · $location', '毕业季的合照时刻', '$location · 毕业季回忆'];
    }
    if (event.isFestivalEvent && event.festivalName != null) {
      final festival = event.festivalName!;
      return [
        '$festival回忆 · $location',
        '$location 的$festival时光',
        '$festival里的人间烟火',
      ];
    }

    return ['$location · $dateRange', '$location 的记忆', '时光印记 · $location'];
  }

  /// 🧪 测试方法：模拟 LLM 调用（用于开发测试，无需真实 API Key）
  Future<List<String>> generateCreativeTitlesMock(
    EventEntity event,
    List<String> topTags,
  ) async {
    await Future.delayed(const Duration(seconds: 1));

    final location = event.city ?? event.province ?? '未知地点';

    if (event.tags.contains('🎓 毕业季')) {
      return ['毕业季 · $location', '毕业季的合照时刻', '$location · 毕业季回忆', '把毕业季写成故事'];
    }

    if (event.isFestivalEvent && event.festivalName != null) {
      final festival = event.festivalName!;
      return [
        '$festival回忆 · $location',
        '$location 的$festival时光',
        '$festival里的热闹瞬间',
        '$festival漫游记',
      ];
    }

    if (topTags.contains('美食')) {
      return [
        '$location · 舌尖上的记忆',
        '美食之旅 · $location',
        '寻味 $location',
        '美食地图 · $location',
      ];
    } else if (topTags.contains('海滩') || topTags.contains('大海')) {
      return ['$location · 海风与阳光', '夏日海边的慢时光', '蓝色记忆 · $location', '海的呼唤'];
    } else if (topTags.contains('猫') || topTags.contains('狗')) {
      return ['毛孩子的快乐时光', '萌宠日记 · $location', '治愈时刻', '毛茸茸的陪伴'];
    } else {
      return [
        '$location · ${event.dateRangeText}',
        '$location 的故事',
        '时光印记',
        '美好瞬间 · $location',
      ];
    }
  }

  Future<Map<int, String>> generatePhotoCaptions(
    EventEntity event,
    List<PhotoEntity> photos,
  ) async {
    final fallback = _getFallbackCaptions(event, photos);
    try {
      final prompt = LlmPromptBuilder.buildPhotoCaptionPrompt(event, photos);
      final text = await _chatCompletion(prompt);
      if (text == null || text.isEmpty) {
        return fallback;
      }
      final parsed = LlmResponseParser.parsePhotoCaptionJson(text);
      if (parsed.isEmpty) {
        return fallback;
      }
      final merged = Map<int, String>.from(fallback);
      merged.addAll(parsed);
      return merged;
    } on LlmException catch (e) {
      print("❌ LLM caption 生成失败(${e.type}): ${e.message}");
      return fallback;
    } catch (e) {
      print("❌ LLM caption 生成失败: $e");
      return fallback;
    }
  }

  Future<Map<int, String>> generatePhotoCaptionsMock(
    EventEntity event,
    List<PhotoEntity> photos,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _getFallbackCaptions(event, photos);
  }

  Map<int, String> _getFallbackCaptions(
    EventEntity event,
    List<PhotoEntity> photos,
  ) {
    final eventLocation = event.city ?? event.province ?? '';
    final result = <int, String>{};
    for (final photo in photos) {
      final topTag = (photo.aiTags ?? const <String>[]).firstWhere(
        (t) => t.trim().isNotEmpty,
        orElse: () => '',
      );
      final location = (photo.city ?? photo.province ?? eventLocation).trim();
      final parts = <String>[
        if (location.isNotEmpty) location,
        if (topTag.isNotEmpty) topTag,
      ];
      var caption = parts.isEmpty ? '美好瞬间' : parts.join('·');
      if (caption.length < 4 && topTag.isNotEmpty) {
        caption = '$topTag时光';
      }
      if (caption.length > 30) {
        caption = caption.substring(0, 30);
      }
      result[photo.id] = caption;
    }
    return result;
  }

  /// 📊 检查 API Key 是否已配置
  bool get isApiKeyConfigured =>
      _apiKey.trim().isNotEmpty && _baseUrl.trim().isNotEmpty;

  /// 📝 生成博客文本内容
  Future<String?> generateBlogText(String prompt) async {
    try {
      final text = await _chatCompletion(prompt);
      if (text == null || text.isEmpty) {
        print("⚠️ LLM 返回为空");
        return null;
      }

      print("✅ LLM 成功生成博客内容");
      return text.trim();
    } on LlmException catch (e) {
      print("❌ LLM 博客生成失败(${e.type}): ${e.message}");
      return null;
    } catch (e) {
      print("❌ LLM 博客生成失败: $e");
      return null;
    }
  }

  Future<String?> _chatCompletion(String prompt) async {
    final isChatCompletions = _apiPath.contains('/chat/completions');
    final requestBody = LlmPromptBuilder.buildRequestBody(
      modelName: _modelName,
      prompt: prompt,
      useChatCompletions: isChatCompletions,
    );

    final response = await _client.postCompletion(
      baseUrl: _baseUrl,
      apiPath: _apiPath,
      apiKey: _apiKey,
      requestBody: requestBody,
    );

    print('📥 [LLM RESPONSE STATUS] ${response.statusCode}');
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const LlmException(
        type: LlmFailureType.protocol,
        message: 'LLM 返回格式异常（非 JSON 对象）',
      );
    }
    final text = LlmResponseParser.extractText(data);
    if (text == null || text.isEmpty) {
      throw const LlmException(
        type: LlmFailureType.emptyResponse,
        message: 'LLM 返回为空或无法解析',
      );
    }
    return text;
  }
}
