class StoryMockGenerator {
  const StoryMockGenerator._();

  static Future<String> generate({
    required String title,
    required String subtitle,
    required List<String> photoDescriptions,
    required bool isShort,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final buffer = StringBuffer();
    buffer.writeln('今天是个特别的日子，我们开启了一段关于"$title"的旅程。$subtitle，每一刻都值得珍藏。\n');

    if (photoDescriptions.isNotEmpty) {
      buffer.writeln('![img](0)\n');
    }

    buffer.writeln('一路走来，看到了许多美丽的风景。阳光洒在身上，微风轻拂，心情格外舒畅。\n');

    final step = isShort ? 2 : 1;
    for (var i = 1; i < photoDescriptions.length; i += step) {
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
}
