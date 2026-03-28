import 'dart:io';
import 'package:flutter/material.dart';

import '../../models/entity/story_entity.dart';
import '../../service/story/story_service.dart';
import '../widgets/ai_backdrop.dart';
import 'story_editor_page.dart';

class StoriesPage extends StatefulWidget {
  const StoriesPage({super.key});

  @override
  State<StoriesPage> createState() => _StoriesPageState();
}

class _StoriesPageState extends State<StoriesPage> {
  List<StoryEntity>? _stories;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  Future<void> _loadStories() async {
    final stories = await StoryService().getAllStories();
    if (mounted) {
      setState(() {
        _stories = stories;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '故事集',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: AIBackdrop(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final stories = _stories ?? [];

    if (stories.isEmpty) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: _loadStories,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        itemCount: stories.length,
        itemBuilder: (context, index) {
          return _buildStoryCard(context, stories[index]);
        },
      ),
    );
  }

  Widget _buildStoryCard(BuildContext context, StoryEntity story) {
    final theme = Theme.of(context);
    // 尝试取出第一张照片用于封面
    final firstPhotoId = story.photoIds.isNotEmpty ? story.photoIds.first : null;

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoryEditorPage(story: story),
          ),
        );
        // 返回后刷新列表（可能有保存）
        _loadStories();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xF7FFFFFF), Color(0xEAF6FBFF)],
          ),
          border: Border.all(color: const Color(0xFFDAE7FF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x100F172A),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 封面图（如果第一张照片可用）
            if (firstPhotoId != null)
              _StoryCardCover(photoId: firstPhotoId, story: story),
            // 文字信息区
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (story.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      story.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${story.photoCount} 张照片',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        story.createdAtText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AIPanel(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'AI 故事正在等素材',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '目前还没有故事，去回忆里选几张照片，几秒内就能生成一篇初稿。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF475569), height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 故事卡片封面图组件（异步加载照片路径）
class _StoryCardCover extends StatefulWidget {
  final int photoId;
  final StoryEntity story;

  const _StoryCardCover({required this.photoId, required this.story});

  @override
  State<_StoryCardCover> createState() => _StoryCardCoverState();
}

class _StoryCardCoverState extends State<_StoryCardCover> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    final photos = await StoryService().loadPhotos([widget.photoId]);
    if (mounted && photos.isNotEmpty) {
      setState(() => _path = photos.first.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) {
      return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        height: 160,
        width: double.infinity,
      ),
    );
  }
}
