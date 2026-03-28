import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/story.dart';
import '../../models/vo/photo.dart';
import '../../models/vo/story_edit_block.dart';
import '../../service/photo/photo_service.dart';
import '../../service/story/story_service.dart';
import '../widgets/path_image.dart';
import '../widgets/story_blog_view.dart';
import '../widgets/story_editable_list.dart';
import '../widgets/story_editor_toolbar.dart';

class StoryResultPage extends StatefulWidget {
  const StoryResultPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    this.sections = const [],
    this.storyEntityId,
    this.storyEntity,
    this.availablePhotos = const [],
  });

  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;
  final int? storyEntityId;
  final StoryEntity? storyEntity;
  final List<PhotoEntity> availablePhotos;

  factory StoryResultPage.fromStoryEntity({
    required StoryEntity storyEntity,
    required List<PhotoEntity> photos,
  }) {
    final heroPhoto = photos.isNotEmpty
        ? _photoEntityToPhoto(photos.first)
        : throw Exception('No photos');

    return StoryResultPage(
      title: storyEntity.title,
      subtitle: storyEntity.subtitle,
      heroImage: heroPhoto,
      storyEntityId: storyEntity.id,
      storyEntity: storyEntity,
      availablePhotos: photos,
    );
  }

  factory StoryResultPage.fromStory(Story story) {
    return StoryResultPage(
      title: story.title,
      subtitle: story.subtitle,
      heroImage: story.heroImage,
      sections: story.blocks
          .where((block) => block.photo != null)
          .map((block) => StorySection(text: block.text, photo: block.photo!))
          .toList(),
    );
  }

  static Photo _photoEntityToPhoto(PhotoEntity entity) {
    return Photo(
      id: entity.assetId,
      path: entity.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
      tags: entity.aiTags ?? const [],
      location: entity.city ?? entity.province,
    );
  }

  @override
  State<StoryResultPage> createState() => _StoryResultPageState();
}

class _StoryResultPageState extends State<StoryResultPage> {
  late final Map<int, PhotoEntity> _photoById;
  late List<StorySection> _sections;
  late List<StoryEditBlock> _draftBlocks;
  final List<List<StoryEditBlock>> _undoStack = [];
  final List<List<StoryEditBlock>> _redoStack = [];

  bool _isSaving = false;
  bool _hasSaved = false;
  bool _hasUnsavedChanges = false;
  StoryPageMode _mode = StoryPageMode.read;

  bool get _isEditable =>
      widget.storyEntityId != null &&
      widget.storyEntity != null &&
      widget.availablePhotos.isNotEmpty;

  StoryEntity get _storyEntity => widget.storyEntity!;

  @override
  void initState() {
    super.initState();
    _photoById = {for (final photo in widget.availablePhotos) photo.id: photo};
    _sections = List.from(widget.sections);
    _draftBlocks = _isEditable
        ? StoryEditBlock.normalizeOrder(_storyEntity.resolveEditBlocks())
        : const <StoryEditBlock>[];
    _mode = StoryPageMode.read;

    if (_isEditable &&
        (_storyEntity.contentJson == null ||
            _storyEntity.contentJson!.trim().isEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _migrateLegacyStory();
      });
    }
  }

  Future<void> _migrateLegacyStory() async {
    if (_isSaving || !_isEditable) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final success = await StoryService().updateStoryDraft(
      story: _storyEntity,
      blocks: _draftBlocks,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
      _hasSaved = success;
      _hasUnsavedChanges = false;
    });

    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('旧版故事已迁移为可编辑草稿')));
    }
  }

  List<StoryEditBlock> _cloneBlocks(List<StoryEditBlock> blocks) {
    return blocks.map((block) => block.copyWith()).toList();
  }

  void _pushHistory() {
    _undoStack.add(_cloneBlocks(_draftBlocks));
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _replaceDraft(List<StoryEditBlock> blocks, {bool markDirty = true}) {
    setState(() {
      _draftBlocks = StoryEditBlock.normalizeOrder(blocks);
      if (markDirty) {
        _hasUnsavedChanges = true;
      }
    });
  }

  void _applyDraftMutation(List<StoryEditBlock> blocks) {
    _pushHistory();
    _replaceDraft(blocks);
  }

  void _undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(_cloneBlocks(_draftBlocks));
    final previous = _undoStack.removeLast();
    _replaceDraft(previous);
  }

  void _redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(_cloneBlocks(_draftBlocks));
    final next = _redoStack.removeLast();
    _replaceDraft(next);
  }

  void _toggleEditMode() {
    if (!_isEditable) {
      return;
    }

    setState(() {
      _mode = _mode == StoryPageMode.read
          ? StoryPageMode.edit
          : StoryPageMode.read;
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _draftBlocks.length) {
      return;
    }
    final updated = _cloneBlocks(_draftBlocks);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    _applyDraftMutation(updated);
  }

  Future<void> _editTextBlock(int index) async {
    final block = _draftBlocks[index];
    final controller = TextEditingController(text: block.text);

    final action = await showModalBottomSheet<_TextEditorAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '编辑文字',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _TextEditorAction.delete),
                      child: const Text('删除'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _TextEditorAction.mergePrev),
                      child: const Text('并入上段'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _TextEditorAction.mergeNext),
                      child: const Text('并入下段'),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _TextEditorAction.split),
                      child: const Text('按空行拆分'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _TextEditorAction.save),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }

    final updatedText = controller.text.trim();
    final updated = _cloneBlocks(_draftBlocks);

    switch (action) {
      case _TextEditorAction.save:
        updated[index] = block.copyWith(text: updatedText);
        _applyDraftMutation(updated);
        return;
      case _TextEditorAction.delete:
        updated.removeAt(index);
        _applyDraftMutation(updated);
        return;
      case _TextEditorAction.split:
        final parts = updatedText
            .split(RegExp(r'\n\s*\n'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
        if (parts.length <= 1) {
          updated[index] = block.copyWith(text: updatedText);
        } else {
          updated.removeAt(index);
          updated.insertAll(
            index,
            parts.map(
              (part) => StoryEditBlock(
                type: StoryEditBlockType.text,
                text: part,
                order: 0,
              ),
            ),
          );
        }
        _applyDraftMutation(updated);
        return;
      case _TextEditorAction.mergePrev:
        if (index == 0 ||
            _draftBlocks[index - 1].type != StoryEditBlockType.text) {
          _showMessage('上一块不是文字，无法合并');
          return;
        }
        updated[index - 1] = updated[index - 1].copyWith(
          text: '${updated[index - 1].text.trim()}\n\n${updatedText.trim()}'
              .trim(),
        );
        updated.removeAt(index);
        _applyDraftMutation(updated);
        return;
      case _TextEditorAction.mergeNext:
        if (index >= _draftBlocks.length - 1 ||
            _draftBlocks[index + 1].type != StoryEditBlockType.text) {
          _showMessage('下一块不是文字，无法合并');
          return;
        }
        updated[index + 1] = updated[index + 1].copyWith(
          text: '${updatedText.trim()}\n\n${updated[index + 1].text.trim()}'
              .trim(),
        );
        updated.removeAt(index);
        _applyDraftMutation(updated);
        return;
    }
  }

  Future<void> _editImageBlock(int index) async {
    final action = await showModalBottomSheet<_ImageEditorAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _ImageEditorAction.replace),
                  icon: const Icon(Icons.image_search),
                  label: const Text('替换图片'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _ImageEditorAction.insertAfter),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('后插图片'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _ImageEditorAction.removePhoto),
                  icon: const Icon(Icons.hide_image_outlined),
                  label: const Text('移除图片'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null) {
      return;
    }
    switch (action) {
      case _ImageEditorAction.replace:
        final selected = await _pickPhoto(
          initialPhotoId: _draftBlocks[index].photoId,
        );
        if (selected == null) {
          return;
        }
        final updated = _cloneBlocks(_draftBlocks);
        updated[index] = updated[index].withPhoto(selected.id);
        _applyDraftMutation(updated);
        return;
      case _ImageEditorAction.insertAfter:
        await _insertImageAfter(index);
        return;
      case _ImageEditorAction.removePhoto:
        final updated = _cloneBlocks(_draftBlocks);
        final block = updated[index];
        if (block.type == StoryEditBlockType.image || !block.hasText) {
          updated.removeAt(index);
        } else {
          updated[index] = block.withoutPhoto();
        }
        _applyDraftMutation(updated);
        return;
    }
  }

  Future<void> _insertImageAfter(int index) async {
    final selected = await _pickPhoto();
    if (selected == null) {
      return;
    }

    final updated = _cloneBlocks(_draftBlocks);
    updated.insert(
      index + 1,
      StoryEditBlock(
        type: StoryEditBlockType.image,
        photoId: selected.id,
        order: 0,
      ),
    );
    _applyDraftMutation(updated);
  }

  void _insertTextAfter(int index) {
    final updated = _cloneBlocks(_draftBlocks);
    updated.insert(
      index + 1,
      const StoryEditBlock(
        type: StoryEditBlockType.text,
        text: '请编辑这一段文字',
        order: 0,
      ),
    );
    _applyDraftMutation(updated);
  }

  void _deleteBlock(int index) {
    final updated = _cloneBlocks(_draftBlocks);
    updated.removeAt(index);
    _applyDraftMutation(updated);
  }

  Future<PhotoEntity?> _pickPhoto({int? initialPhotoId}) async {
    return showModalBottomSheet<PhotoEntity>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '选择图片',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 360,
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: widget.availablePhotos.length,
                    itemBuilder: (context, index) {
                      final photo = widget.availablePhotos[index];
                      final isSelected = photo.id == initialPhotoId;
                      return InkWell(
                        onTap: () => Navigator.pop(context, photo),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: PathImage(
                                path: photo.path,
                                assetId: photo.assetId,
                                fit: BoxFit.cover,
                              ),
                            ),
                            if (isSelected)
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveStory() async {
    if (_isSaving) {
      return;
    }

    if (!_isEditable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前故事不支持保存编辑')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final isar = PhotoService().isar;
      final story = await isar.collection<StoryEntity>().get(
        widget.storyEntityId!,
      );
      if (story == null) {
        throw Exception('Story not found');
      }

      final success = await StoryService().updateStoryDraft(
        story: story,
        blocks: _draftBlocks,
      );

      if (!mounted) {
        return;
      }

      if (!success) {
        throw Exception('draft save failed');
      }

      setState(() {
        widget.storyEntity!
          ..content = story.content
          ..contentJson = story.contentJson
          ..photoIds = List<int>.from(story.photoIds)
          ..photoCount = story.photoCount
          ..updatedAt = story.updatedAt;
        _hasSaved = true;
        _hasUnsavedChanges = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('故事草稿已保存')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _closePage() async {
    if (_isEditable && _hasUnsavedChanges) {
      final shouldLeave = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('未保存改动'),
            content: const Text('当前有未保存的修改，确认直接离开吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('直接离开'),
              ),
            ],
          );
        },
      );
      if (shouldLeave != true) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, _hasSaved);
      return;
    }
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _shareStory() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Photo _resolveHeroImage() {
    if (!_isEditable) {
      return widget.heroImage;
    }

    for (final block in _draftBlocks) {
      final photoId = block.photoId;
      if (photoId == null) {
        continue;
      }
      final photo = _photoById[photoId];
      if (photo != null) {
        return StoryResultPage._photoEntityToPhoto(photo);
      }
    }

    return widget.heroImage;
  }

  Widget _buildReadOnlyBody(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final section = _sections[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  section.text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PathImage(
                  path: section.photo.path,
                  assetId: section.photo.id,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        );
      }, childCount: _sections.length),
    );
  }

  Widget _buildBlogBody() {
    return StoryBlogView(
      blocks: _draftBlocks,
      photoById: _photoById,
      emptyHint: '故事内容为空，请切换到编辑模式补充内容。',
    );
  }

  Widget _buildEditableBody(BuildContext context) {
    if (_draftBlocks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前草稿还没有内容块',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          _applyDraftMutation([
                            const StoryEditBlock(
                              type: StoryEditBlockType.text,
                              text: '请编辑这一段文字',
                              order: 0,
                            ),
                          ]);
                        },
                        icon: const Icon(Icons.subject),
                        label: const Text('新增文字'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final selected = await _pickPhoto();
                          if (selected == null) {
                            return;
                          }
                          _applyDraftMutation([
                            StoryEditBlock(
                              type: StoryEditBlockType.image,
                              photoId: selected.id,
                              order: 0,
                            ),
                          ]);
                        },
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('新增图片'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return StoryEditableList(
      blocks: _draftBlocks,
      photoById: _photoById,
      onReorder: _onReorder,
      onEditText: _editTextBlock,
      onReplaceImage: _editImageBlock,
      onInsertTextAfter: _insertTextAfter,
      onInsertImageAfter: (index) => _insertImageAfter(index),
      onDeleteBlock: _deleteBlock,
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroImage = _resolveHeroImage();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            leading: IconButton(
              onPressed: () async => _closePage(),
              icon: const Icon(Icons.close),
            ),
            actions: [
              IconButton(
                onPressed: _shareStory,
                icon: const Icon(Icons.share),
                tooltip: '分享',
              ),
              if (_isEditable)
                IconButton(
                  onPressed: _toggleEditMode,
                  icon: const Icon(Icons.edit),
                  tooltip: '切换编辑模式',
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 3,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PathImage(
                    path: heroImage.path,
                    assetId: heroImage.id,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.subtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (_isEditable && _mode == StoryPageMode.read)
            _buildBlogBody()
          else if (_isEditable && _mode == StoryPageMode.edit)
            _buildEditableBody(context)
          else
            _buildReadOnlyBody(context),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: _isEditable
          ? (_mode == StoryPageMode.edit
                ? StoryEditorToolbar(
                    canUndo: _undoStack.isNotEmpty,
                    canRedo: _redoStack.isNotEmpty,
                    isSaving: _isSaving,
                    hasUnsavedChanges: _hasUnsavedChanges,
                    onUndo: _undo,
                    onRedo: _redo,
                    onSave: _saveStory,
                  )
                : null)
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () async => _closePage(),
                    icon: const Icon(Icons.close),
                    label: const Text('关闭'),
                  ),
                  TextButton.icon(
                    onPressed: _shareStory,
                    icon: const Icon(Icons.share),
                    label: const Text('分享'),
                  ),
                ],
              ),
            ),
    );
  }
}

class StorySection {
  const StorySection({required this.text, required this.photo});

  final String text;
  final Photo photo;
}

enum _TextEditorAction { save, delete, split, mergePrev, mergeNext }

enum _ImageEditorAction { replace, insertAfter, removePhoto }

enum StoryPageMode { read, edit }
