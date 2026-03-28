import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/vo/story_edit_block.dart';
import 'path_image.dart';

class StoryBlogView extends StatelessWidget {
  const StoryBlogView({
    super.key,
    required this.blocks,
    required this.photoById,
    this.emptyHint = '暂无可展示内容',
  });

  final List<StoryEditBlock> blocks;
  final Map<int, PhotoEntity> photoById;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Text(
            emptyHint,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
          ),
        ),
      );
    }

    var leadTextConsumed = false;

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final block = blocks[index];
        final photo = block.photoId == null ? null : photoById[block.photoId!];
        final children = <Widget>[];

        if (block.hasText) {
          final style = !leadTextConsumed
              ? Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.8)
              : Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8);
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(block.text.trim(), style: style),
            ),
          );
          leadTextConsumed = true;
        }

        if (photo != null) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: PathImage(
                  path: photo.path,
                  assetId: photo.assetId,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        }

        if (children.isEmpty) {
          return const SizedBox.shrink();
        }

        children.add(const SizedBox(height: 18));
        return Column(children: children);
      }, childCount: blocks.length),
    );
  }
}
