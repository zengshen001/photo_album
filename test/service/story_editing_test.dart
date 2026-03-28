import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/story_entity.dart';
import 'package:photo_album/models/vo/story_edit_block.dart';
import 'package:photo_album/service/story/story_service.dart';

void main() {
  group('StoryEntity editing migration', () {
    test(
      'resolveEditBlocks migrates legacy markdown when contentJson missing',
      () {
        final story = StoryEntity.create(
          title: '旧故事',
          subtitle: '兼容',
          content: '第一段\n\n![img](0)\n\n第二段\n\n![img](1)',
          eventId: 1,
          photoIds: [101, 202],
        );

        final blocks = story.resolveEditBlocks();

        expect(blocks.map((block) => block.type).toList(), [
          StoryEditBlockType.text,
          StoryEditBlockType.image,
          StoryEditBlockType.text,
          StoryEditBlockType.image,
        ]);
        expect(blocks[0].text, '第一段');
        expect(blocks[1].photoId, 101);
        expect(blocks[2].text, '第二段');
        expect(blocks[3].photoId, 202);
      },
    );

    test('resolveEditBlocks prefers contentJson when available', () {
      final story = StoryEntity.create(
        title: '新故事',
        subtitle: '结构化',
        content: '旧内容',
        eventId: 1,
        photoIds: [1, 2],
        contentJson: StoryEntity.encodeEditBlocks([
          const StoryEditBlock(
            type: StoryEditBlockType.text,
            text: '结构化段落',
            order: 0,
          ),
          const StoryEditBlock(
            type: StoryEditBlockType.image,
            photoId: 2,
            order: 1,
          ),
        ]),
      );

      final blocks = story.resolveEditBlocks();

      expect(blocks, hasLength(2));
      expect(blocks[0].text, '结构化段落');
      expect(blocks[1].photoId, 2);
    });

    test(
      'syncStructuredContent writes contentJson markdown and ordered photoIds',
      () {
        final story = StoryEntity.create(
          title: '保存',
          subtitle: '草稿',
          content: '',
          eventId: 7,
          photoIds: const [],
        );

        story.syncStructuredContent([
          const StoryEditBlock(
            type: StoryEditBlockType.text,
            text: '开头',
            order: 0,
          ),
          const StoryEditBlock(
            type: StoryEditBlockType.image,
            photoId: 9,
            order: 1,
          ),
          const StoryEditBlock(
            type: StoryEditBlockType.text,
            text: '结尾',
            order: 2,
          ),
          const StoryEditBlock(
            type: StoryEditBlockType.image,
            photoId: 5,
            order: 3,
          ),
        ]);

        expect(story.photoIds, [9, 5]);
        expect(story.content, '开头\n\n![img](0)\n\n结尾\n\n![img](1)');
        expect(StoryEntity.decodeEditBlocks(story.contentJson), hasLength(4));
      },
    );
  });

  group('StoryService editing save payload', () {
    test('buildSavePayload keeps image order in markdown and photoIds', () {
      final payload = StoryService().buildSavePayload([
        const StoryEditBlock(
          type: StoryEditBlockType.image,
          photoId: 30,
          order: 0,
        ),
        const StoryEditBlock(
          type: StoryEditBlockType.text,
          text: '中间段落',
          order: 1,
        ),
        const StoryEditBlock(
          type: StoryEditBlockType.image,
          photoId: 12,
          order: 2,
        ),
      ]);

      expect(payload.photoIds, [30, 12]);
      expect(payload.content, '![img](0)\n\n中间段落\n\n![img](1)');
      expect(StoryEntity.decodeEditBlocks(payload.contentJson), hasLength(3));
    });
  });
}
