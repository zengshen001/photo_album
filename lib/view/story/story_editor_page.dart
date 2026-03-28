import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/vo/story_edit_block.dart';
import '../../service/story/story_service.dart';
import '../widgets/ai_backdrop.dart';

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
  bool _isEditing = false;
  bool _hasUnsavedChanges = false;

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
      _hasUnsavedChanges = true;
    });
  }

  void _updateBlockText(int index, String text) {
    _blocks[index] = _blocks[index].copyWith(text: text);
    _hasUnsavedChanges = true;
  }

  /// 在指定位置后面插入一个新的纯文字块
  void _addTextBlockAfter(int index) {
    setState(() {
      _blocks.insert(
        index + 1,
        StoryEditBlock(
          type: StoryEditBlockType.text,
          text: '',
          order: index + 1,
        ),
      );
      _blocks = StoryEditBlock.normalizeOrder(_blocks);
      _hasUnsavedChanges = true;
    });
  }

  /// 删除指定索引的块
  void _deleteBlock(int index) {
    if (_blocks.length <= 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少保留一个内容块')));
      return;
    }
    setState(() {
      _blocks.removeAt(index);
      _blocks = StoryEditBlock.normalizeOrder(_blocks);
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _saveStory() async {
    setState(() => _isSaving = true);
    final success = await StoryService().updateStoryDraft(
      story: widget.story,
      blocks: _blocks,
    );
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (success) _hasUnsavedChanges = false;
    });
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('故事已保存')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有未保存的更改'),
        content: const Text('是否保存后离开？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop(true);
              await _saveStory();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final nav = Navigator.of(context);
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) nav.pop();
        }
      },
      child: AIBackdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEditing ? '编辑故事' : widget.story.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_isEditing && widget.story.subtitle.isNotEmpty)
                  Text(
                    widget.story.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
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
              else ...[
                // 有改动时始终显示保存按钮
                if (_hasUnsavedChanges)
                  TextButton(
                    onPressed: _saveStory,
                    child: const Text(
                      '保存',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                IconButton(
                  icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
                  onPressed: () {
                    setState(() => _isEditing = !_isEditing);
                  },
                ),
              ],
            ],
          ),
          body: _isLoadingPhotos
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: _isEditing
                          ? ReorderableListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ).copyWith(bottom: 40),
                              itemCount: _blocks.length,
                              onReorder: _onReorder,
                              itemBuilder: (context, index) {
                                final block = _blocks[index];
                                return _buildEditBlockItem(block, index, theme);
                              },
                              proxyDecorator: (child, index, animation) {
                                return Material(
                                  elevation: 8,
                                  color: Colors.transparent,
                                  shadowColor: Colors.black26,
                                  child: child,
                                );
                              },
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ).copyWith(bottom: 40),
                              itemCount: _blocks.length,
                              itemBuilder: (context, index) {
                                final block = _blocks[index];
                                return _buildReadBlockItem(block, theme);
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildReadBlockItem(StoryEditBlock block, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (block.hasPhoto && _photoMap.containsKey(block.photoId)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_photoMap[block.photoId]!.path),
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (block.text.isNotEmpty)
            Text(
              block.text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.8,
                color: Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditBlockItem(StoryEditBlock block, int index, ThemeData theme) {
    return Container(
      key: ValueKey('block_${block.order}_$index'),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF7FFFFFF), Color(0xEAF7FBFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFDCE8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图片区域
          if (block.hasPhoto && _photoMap.containsKey(block.photoId))
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Image.file(
                File(_photoMap[block.photoId]!.path),
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            ),
          // 文字编辑区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
          // 操作栏：拖拽手柄 / 新增块 / 删除块
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 新增文字块
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  iconSize: 20,
                  color: Colors.blueGrey[400],
                  tooltip: '在此后插入新块',
                  onPressed: () => _addTextBlockAfter(index),
                ),
                // 删除当前块
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  iconSize: 20,
                  color: Colors.red[300],
                  tooltip: '删除此块',
                  onPressed: () => _showDeleteConfirm(index),
                ),
                // 拖拽手柄（ReorderableListView 需要）
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: Colors.blueGrey[300],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(int index) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除内容块'),
        content: const Text('确认删除这段内容？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red[400]),
            onPressed: () {
              Navigator.of(context).pop();
              _deleteBlock(index);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
