import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import 'widgets/story_creation_sheet.dart';

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final Set<String> _selectedPhotoIds = {};
  bool _selectionMode = false;

  void _toggleSelection(Photo photo) {
    setState(() {
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
        if (_selectedPhotoIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedPhotoIds.add(photo.id);
        _selectionMode = true;
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
        selectedPhotos: selectedPhotos.isEmpty ? widget.event.photos : selectedPhotos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverPhoto = widget.event.photos.first;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectionMode) {
                      _selectedPhotoIds.clear();
                      _selectionMode = false;
                    } else {
                      _selectionMode = true;
                    }
                  });
                },
                child: Text(
                  _selectionMode ? '取消选择' : '选择',
                  style: TextStyle(
                    color: _selectionMode ? theme.colorScheme.primary : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16, right: 20),
              title: Text(
                widget.event.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))
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
                    child: Image.file(
                      File(coverPhoto.path),
                      fit: BoxFit.cover,
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
            padding: const EdgeInsets.all(2),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final photo = widget.event.photos[index];
                  final isSelected = _selectedPhotoIds.contains(photo.id);

                  return GestureDetector(
                    onTap: () {
                      if (_selectionMode) {
                        _toggleSelection(photo);
                      } else {
                        // View Image natively (optional placeholder logic)
                      }
                    },
                    onLongPress: () {
                      if (!_selectionMode) {
                        _toggleSelection(photo);
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(photo.path),
                          fit: BoxFit.cover,
                        ),
                        if (_selectionMode) ...[
                          Container(
                            color: isSelected 
                                ? Colors.black.withValues(alpha: 0.3) 
                                : Colors.white.withValues(alpha: 0.3),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Icon(
                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                              color: isSelected ? theme.colorScheme.primary : Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                childCount: widget.event.photos.length,
              ),
            ),
          ),
          // Bottom padding for FAB
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showStoryCreationSheet,
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
