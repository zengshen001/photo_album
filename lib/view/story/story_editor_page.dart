import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/vo/story_edit_block.dart';
import '../../service/story/story_service.dart';

class StoryEditorPage extends StatefulWidget {
  final StoryEntity story;

  const StoryEditorPage({super.key, required this.story});

  @override
  State<StoryEditorPage> createState() => _StoryEditorPageState();
}

class _StoryEditorPageState extends State<StoryEditorPage> {
  late List<StoryEditBlock> _blocks;
  Map<int, PhotoEntity> _photoMap = {};
  bool _isLoadingPhotos = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _blocks = widget.story.resolveEditBlocks();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final photoIds = widget.story.photoIds;
    if (photoIds.isNotEmpty) {
      final photos = await StoryService().loadPhotos(photoIds);
      setState(() {
        _photoMap = {for (final p in photos) p.id: p};
        _isLoadingPhotos = false;
      });
    } else {
      setState(() {
        _isLoadingPhotos = false;
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
      _blocks = StoryEditBlock.normalizeOrder(_blocks);
    });
  }

  void _updateBlockText(int index, String text) {
    _blocks[index] = _blocks[index].copyWith(text: text);
  }

  Future<void> _saveStory() async {
    setState(() => _isSaving = true);
    final success = await StoryService().updateStoryDraft(
      story: widget.story,
      blocks: _blocks,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('故事已保存')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        title: const Text('编辑故事'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveStory,
              child: const Text(
                '完成',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: _isLoadingPhotos
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.story.title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.story.subtitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
                        .copyWith(bottom: 120),
                    itemCount: _blocks.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final block = _blocks[index];
                      return _buildBlockItem(block, index, theme);
                    },
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 8,
                        color: Colors.transparent,
                        shadowColor: Colors.black26,
                        child: child,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBlockItem(StoryEditBlock block, int index, ThemeData theme) {
    return Container(
      key: ValueKey('block_${block.order}_$index'),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (block.hasPhoto && _photoMap.containsKey(block.photoId)) ...[
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.file(
                    File(_photoMap[block.photoId]!.path),
                    fit: BoxFit.cover,
                    height: 250,
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextFormField(
                  initialValue: block.text,
                  onChanged: (val) => _updateBlockText(index, val),
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '添加描述...',
                  ),
                  maxLines: null,
                ),
              ),
            ],
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.drag_indicator,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
