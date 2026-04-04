import 'package:flutter_test/flutter_test.dart';

import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/ai/llm_prompt_builder.dart';

void main() {
  test('buildCreativeTitlePrompt includes graduation constraints', () {
    final event = EventEntity()
      ..title = 't'
      ..startTime = DateTime(2022, 6, 18, 9, 0).millisecondsSinceEpoch
      ..endTime = DateTime(2022, 6, 18, 10, 0).millisecondsSinceEpoch
      ..tags = ['🎓 毕业季']
      ..avgHappyScore = 0.72
      ..avgNostalgicScore = 0.84
      ..dominantEmotion = 'nostalgic';

    final prompt = LlmPromptBuilder.buildCreativeTitlePrompt(event, const []);
    expect(prompt, contains('场景标签: 🎓 毕业季'));
    expect(prompt, contains('必须包含「毕业季」'));
    expect(prompt, contains('事件情绪画像:'));
    expect(prompt, contains('dominant=nostalgic'));
  });

  test('buildCreativeTitlePrompt includes festival constraints', () {
    final event = EventEntity()
      ..title = 't'
      ..startTime = DateTime(2024, 6, 10, 9, 0).millisecondsSinceEpoch
      ..endTime = DateTime(2024, 6, 10, 10, 0).millisecondsSinceEpoch
      ..isFestivalEvent = true
      ..festivalName = '端午'
      ..avgHappyScore = 0.61
      ..avgLivelyScore = 0.73
      ..dominantEmotion = 'lively';

    final prompt = LlmPromptBuilder.buildCreativeTitlePrompt(event, const []);
    expect(prompt, contains('节日为「端午」'));
    expect(prompt, contains('必须包含「端午」'));
    expect(prompt, contains('dominant=lively'));
  });

  test('buildPhotoCaptionPrompt includes advanced scene tags', () {
    final event = EventEntity()
      ..title = 't'
      ..startTime = DateTime(2024, 6, 10, 9, 0).millisecondsSinceEpoch
      ..endTime = DateTime(2024, 6, 10, 10, 0).millisecondsSinceEpoch
      ..isFestivalEvent = true
      ..festivalName = '端午'
      ..tags = ['🥟 端午', '🏮 古城漫游']
      ..avgHappyScore = 0.58
      ..avgCalmScore = 0.32
      ..avgNostalgicScore = 0.67
      ..avgLivelyScore = 0.74
      ..dominantEmotion = 'lively'
      ..emotionDiversity = 0.04;
    final photo = PhotoEntity()
      ..id = 1
      ..assetId = 'asset_1'
      ..path = '/tmp/1.jpg'
      ..timestamp = DateTime(2024, 6, 10, 9, 30).millisecondsSinceEpoch
      ..width = 100
      ..height = 100
      ..aiTags = ['美食', '建筑'];

    final prompt = LlmPromptBuilder.buildPhotoCaptionPrompt(event, [photo]);
    expect(prompt, contains('场景标签: 🥟 端午、🏮 古城漫游'));
    expect(prompt, contains('节日为「端午」'));
    expect(prompt, contains('事件情绪画像:'));
    expect(prompt, contains('diversity=0.04'));
  });
}
