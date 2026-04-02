import 'package:flutter_test/flutter_test.dart';

import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/service/ai/llm_prompt_builder.dart';

void main() {
  test('buildCreativeTitlePrompt includes graduation constraints', () {
    final event = EventEntity()
      ..title = 't'
      ..startTime = DateTime(2022, 6, 18, 9, 0).millisecondsSinceEpoch
      ..endTime = DateTime(2022, 6, 18, 10, 0).millisecondsSinceEpoch
      ..tags = ['🎓 毕业季'];

    final prompt = LlmPromptBuilder.buildCreativeTitlePrompt(event, const []);
    expect(prompt, contains('场景标签: 🎓 毕业季'));
    expect(prompt, contains('必须包含「毕业季」'));
  });

  test('buildCreativeTitlePrompt includes festival constraints', () {
    final event = EventEntity()
      ..title = 't'
      ..startTime = DateTime(2024, 6, 10, 9, 0).millisecondsSinceEpoch
      ..endTime = DateTime(2024, 6, 10, 10, 0).millisecondsSinceEpoch
      ..isFestivalEvent = true
      ..festivalName = '端午';

    final prompt = LlmPromptBuilder.buildCreativeTitlePrompt(event, const []);
    expect(prompt, contains('节日为「端午」'));
    expect(prompt, contains('必须包含「端午」'));
  });
}
