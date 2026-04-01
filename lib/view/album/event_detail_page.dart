import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/entity/event_entity.dart';
import '../../service/photo/photo_service.dart';
import '../widgets/ai_backdrop.dart';
import '../../widgets/lazy_load_image.dart';
import 'widgets/story_creation_sheet.dart';

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late final Set<String> _selectedPhotoIds;
  String? _editedTitle;

  @override
  void initState() {
    super.initState();
    // Default to selecting all photos
    _selectedPhotoIds = widget.event.photos.map((p) => p.id).toSet();
  }

  void _toggleSelection(Photo photo) {
    setState(() {
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
      } else {
        _selectedPhotoIds.add(photo.id);
      }
    });
  }

  void _showStoryCreationSheet() {
    final selectedPhotos = widget.event.photos
        .where((p) => _selectedPhotoIds.contains(p.id))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StoryCreationSheet(
        event: widget.event,
        selectedPhotos: selectedPhotos.isEmpty
            ? widget.event.photos
            : selectedPhotos,
      ),
    );
  }

  Future<void> _editTitle() async {
    final controller = TextEditingController(
      text: _editedTitle ?? widget.event.displayTitle,
    );
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑回忆标题'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '输入新的标题'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    final title = (newTitle ?? '').trim();
    if (title.isEmpty) {
      return;
    }

    final id = int.tryParse(widget.event.id);
    if (id == null) {
      return;
    }

    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      final latest = await isar.collection<EventEntity>().get(id);
      if (latest == null) {
        return;
      }
      latest.title = title;
      latest.aiThemes = [title];
      latest.isLlmGenerated = true;
      await isar.collection<EventEntity>().put(latest);
    });

    PhotoService().markLocalDataChanged();
    if (!mounted) {
      return;
    }
    setState(() {
      _editedTitle = title;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPhotoIds.length == widget.event.photos.length) {
        _selectedPhotoIds.clear();
      } else {
        _selectedPhotoIds.addAll(widget.event.photos.map((p) => p.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverPhoto = widget.event.photos.first;

    final displayTitle = _editedTitle ?? widget.event.displayTitle;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AIBackdrop(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              stretch: true,
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              surfaceTintColor: Colors.transparent,
              actions: [
                IconButton(
                  tooltip: '编辑标题',
                  onPressed: _editTitle,
                  icon: const Icon(Icons.edit_outlined),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.92),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _toggleSelectAll,
                  child: Text(
                    _selectedPhotoIds.length == widget.event.photos.length
                        ? '取消全选'
                        : '全选',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(
                  left: 20,
                  bottom: 16,
                  right: 20,
                ),
                title: Text(
                  displayTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                stretchModes: const [StretchMode.zoomBackground],
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'event_cover_${widget.event.id}',
                      child: LazyLoadImage(
                        path: coverPhoto.path,
                        fit: BoxFit.cover,
                        loadImmediately: true,
                        useThumbnail: true,
                        thumbnailWidth: 800,
                        thumbnailHeight: 600,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 88,
                      child: AIPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.event.isAiAnalysisComplete
                                    ? '已选择 ${_selectedPhotoIds.length}/${widget.event.photos.length} 张照片，可直接生成 AI 故事。'
                                    : '${widget.event.aiAnalysisStatusText}，已选择 ${_selectedPhotoIds.length}/${widget.event.photos.length} 张照片。',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 120,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.6),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final photo = widget.event.photos[index];
                  final isSelected = _selectedPhotoIds.contains(photo.id);

                  return GestureDetector(
                    onTap: () => _toggleSelection(photo),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LazyLoadImage(
                            path: photo.path,
                            fit: BoxFit.cover,
                            thumbnailWidth: 300,
                            thumbnailHeight: 300,
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            color: isSelected
                                ? Colors.black.withValues(alpha: 0.28)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: isSelected
                                  ? theme.colorScheme.secondary
                                  : Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }, childCount: widget.event.photos.length),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_selectedPhotoIds.isEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('至少需要选择一张图片才能生成故事噢')));
            return;
          }
          _showStoryCreationSheet();
        },
        elevation: 4,
        highlightElevation: 8,
        icon: const Icon(Icons.auto_awesome),
        label: Text(
          _selectedPhotoIds.isEmpty
              ? '生成故事'
              : '生成故事 (${_selectedPhotoIds.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
