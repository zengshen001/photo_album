class LlmResponseParser {
  const LlmResponseParser._();

  static List<String> parseTitleLines(String text) {
    final lines = text.split('\n');
    final titles = <String>[];
    for (final line in lines) {
      var cleaned = line.trim();
      if (cleaned.isEmpty) continue;

      cleaned = cleaned.replaceFirst(RegExp(r'^[\d]+\.?\s+'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'^[一二三四五六七八九十]+[、.\s]+'), '');

      if (cleaned.startsWith('"') || cleaned.startsWith("'")) {
        cleaned = cleaned.substring(1);
      }
      if (cleaned.endsWith('"') || cleaned.endsWith("'")) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }

      cleaned = cleaned.trim();
      if (cleaned.length < 3 || cleaned.length > 30) continue;
      titles.add(cleaned);
    }
    return titles.take(5).toList();
  }

  static String? extractText(Map<String, dynamic> data) {
    final direct = data['output_text'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final output = data['output'];
    if (output is List) {
      final buffer = StringBuffer();
      for (final item in output) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final content = item['content'];
        if (content is! List) {
          continue;
        }
        for (final part in content) {
          if (part is! Map<String, dynamic>) {
            continue;
          }
          final text = part['text'];
          if (text is String) {
            buffer.write(text);
          }
        }
      }
      final result = buffer.toString().trim();
      if (result.isNotEmpty) {
        return result;
      }
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      return null;
    }

    final content = message['content'];
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map<String, dynamic> && item['text'] is String) {
          buffer.write(item['text'] as String);
        }
      }
      final result = buffer.toString();
      return result.isEmpty ? null : result;
    }
    return null;
  }
}
