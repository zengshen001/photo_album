import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/vo/story_edit_block.dart';
import 'path_image.dart';

class StoryEditableList extends StatelessWidget {
  const StoryEditableList({
    super.key,
    required this.blocks,
    required this.photoById,
    required this.onReorder,
    required this.onEditText,
    required this.onReplaceImage,
    required this.onInsertTextAfter,
    required this.onInsertImageAfter,
    required this.onDeleteBlock,
  });

  final List<StoryEditBlock> blocks;
  final Map<int, PhotoEntity> photoById;
  final ReorderCallback onReorder;
  final ValueChanged<int> onEditText;
  final ValueChanged<int> onReplaceImage;
  final ValueChanged<int> onInsertTextAfter;
  final ValueChanged<int> onInsertImageAfter;
  final ValueChanged<int> onDeleteBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (blocks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '当前草稿还没有内容块，请先插入文字或图片。',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ),
      );
    }

    return SliverReorderableList(
      itemCount: blocks.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final block = blocks[index];
        final photo = block.photoId == null ? null : photoById[block.photoId!];

        return Padding(
          key: ValueKey('story_block_${index}_${block.order}_${block.photoId}'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '块 ${index + 1}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                      IconButton(
                        onPressed: () => onDeleteBlock(index),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                  if (block.hasText) ...[
                    InkWell(
                      onTap: () => onEditText(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          block.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (block.hasPhoto && photo != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: PathImage(
                        path: photo.path,
                        assetId: photo.assetId,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (block.hasText)
                        ActionChip(
                          side: BorderSide.none,
                          backgroundColor: const Color(0xFFF2F2F7),
                          onPressed: () => onEditText(index),
                          avatar: const Icon(Icons.edit_note, size: 18),
                          label: const Text('编辑文字'),
                        ),
                      if (block.hasPhoto)
                        ActionChip(
                          side: BorderSide.none,
                          backgroundColor: const Color(0xFFF2F2F7),
                          onPressed: () => onReplaceImage(index),
                          avatar: const Icon(Icons.image_search, size: 18),
                          label: const Text('替换图片'),
                        ),
                      ActionChip(
                        side: BorderSide.none,
                        backgroundColor: const Color(0xFFF2F2F7),
                        onPressed: () => onInsertTextAfter(index),
                        avatar: const Icon(Icons.subject, size: 18),
                        label: const Text('插入文字'),
                      ),
                      ActionChip(
                        side: BorderSide.none,
                        backgroundColor: const Color(0xFFF2F2F7),
                        onPressed: () => onInsertImageAfter(index),
                        avatar: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 18,
                        ),
                        label: const Text('插入图片'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
