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
    if (blocks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '当前草稿还没有内容块，请先插入文字或图片。',
                style: Theme.of(context).textTheme.bodyLarge,
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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('块 ${index + 1}'),
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
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          block.text,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(height: 1.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (block.hasPhoto && photo != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
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
                        OutlinedButton.icon(
                          onPressed: () => onEditText(index),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('编辑文字'),
                        ),
                      if (block.hasPhoto)
                        OutlinedButton.icon(
                          onPressed: () => onReplaceImage(index),
                          icon: const Icon(Icons.image_search),
                          label: const Text('替换图片'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => onInsertTextAfter(index),
                        icon: const Icon(Icons.subject),
                        label: const Text('插入文字'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => onInsertImageAfter(index),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
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
