import 'dart:io';
import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../service/event/event_service.dart';
import '../../service/photo/photo_service.dart';
import '../widgets/ai_backdrop.dart';
import 'event_detail_page.dart';

class AlbumFeedPage extends StatefulWidget {
  const AlbumFeedPage({super.key});

  @override
  State<AlbumFeedPage> createState() => _AlbumFeedPageState();
}

class _AlbumFeedPageState extends State<AlbumFeedPage> {
  Stream<List<Event>>? _eventsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final isar = PhotoService().isar;
    _eventsStream = EventService().watchEvents().asyncMap((entities) async {
      final uiEvents = <Event>[];
      for (final e in entities) {
        uiEvents.add(await e.toUIModel(isar));
      }
      return uiEvents;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AIBackdrop(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text('回忆'),
              surfaceTintColor: Colors.transparent,
              backgroundColor: Colors.white.withValues(alpha: 0.7),
              pinned: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '清空数据',
                  onPressed: () => _showClearDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: '扫描相册',
                  onPressed: () => _scanPhotos(context),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              sliver: SliverToBoxAdapter(
                child: AIPanel(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.95),
                              theme.colorScheme.secondary.withValues(
                                alpha: 0.75,
                              ),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI 回忆整理',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '只做静态视觉升级，不新增加载流程，保持浏览和选图响应速度。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF475569),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            StreamBuilder<List<Event>>(
              stream: _eventsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    child: Center(child: Text('加载失败 ${snapshot.error}')),
                  );
                }

                final events = snapshot.data;
                if (events == null || events.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: AIPanel(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        child: const Text('暂无聚类回忆，点击右上角重新扫描'),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ).copyWith(bottom: 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final event = events[index];
                      return _EventFeedCard(event: event);
                    }, childCount: events.length),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClearDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空所有数据'),
        content: const Text('确定要删除数据库中的所有相册、事件和故事吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await PhotoService().clearAllCachedData();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('数据已清空')));
      }
    }
  }

  Future<void> _scanPhotos(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await PhotoService().scanAndSyncPhotos();
      await EventService().runClustering();
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('相册扫描与聚类完成')));
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('扫描失败: $e')));
    }
  }
}

class _EventFeedCard extends StatelessWidget {
  final Event event;

  const _EventFeedCard({required this.event});

  @override
  Widget build(BuildContext context) {
    if (event.photos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final coverPhoto = event.photos.first;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventDetailPage(event: event)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        height: 380,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Hero Cover
              Hero(
                tag: 'event_cover_${event.id}',
                child: Image.file(
                  File(coverPhoto.path),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const ColoredBox(color: Color(0xFFE5E5EA)),
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          event.isAiAnalysisComplete &&
                                  event.aiThemes.isNotEmpty
                              ? 'AI 发现 ${event.aiThemes.length} 个主题'
                              : event.aiAnalysisStatusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 180,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 20,
                bottom: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.displayTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (event.isAiAnalysisInProgress) ...[
                      Text(
                        event.aiAnalysisStatusText,
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.location,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.calendar_today,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          event.dateRangeText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
