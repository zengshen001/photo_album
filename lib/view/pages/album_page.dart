import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../models/entity/event_entity.dart';
import '../../models/event.dart';
import '../../service/ai/ai_service.dart';
import '../../service/event/event_service.dart';
import '../../service/photo/photo_service.dart';
import '../widgets/event_card.dart';
import '../widgets/primary_button.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  bool _isRefreshing = false;

  late Stream<List<EventEntity>> _eventsStream;

  // 🔄 刷新数据：扫描相册 + 运行聚类
  Future<void> _refreshData({bool clearCacheFirst = false}) async {
    if (_isRefreshing) return; // 防止重复点击

    setState(() => _isRefreshing = true);

    try {
      if (clearCacheFirst) {
        await PhotoService().clearAllCachedData();
      }

      // 1. 扫描相册（仅入库原始可用数据）
      final scanSummary = await PhotoService().scanAndSyncPhotos();

      final hasPhotoSetChanged =
          clearCacheFirst ||
          scanSummary.insertedCount > 0 ||
          scanSummary.removedCount > 0;

      if (hasPhotoSetChanged) {
        // 2. 仅在照片集合变化时重跑聚类（避免“纯刷新”造成事件抖动）
        await EventService().runClustering();

        // 3. 聚类完成后再做 AI 分析，确保 eventId 已建立
        await AIService().analyzePhotosInBackground();
      } else {
        developer.log('本次无照片增删，跳过聚类与 AI 分析，保留现有事件结果');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clearCacheFirst
                  ? '✅ 已清空缓存并完成重扫：新增${scanSummary.insertedCount}张，可用总数${scanSummary.totalAfter}张'
                  : '✅ 数据已更新：新增${scanSummary.insertedCount}张，可用总数${scanSummary.totalAfter}张',
            ),
          ),
        );
      }
    } on PhotoScanException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('⚠️ ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 更新失败: $e')));
      }
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _resetCacheAndRescan() async {
    if (_isRefreshing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('刷新缓存并重扫'),
          content: const Text('将清空 Isar 中的照片、事件、故事数据，并重新扫描相册。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _refreshData(clearCacheFirst: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _eventsStream = EventService().watchEvents();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: StreamBuilder<List<EventEntity>>(
        stream: _eventsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const CustomScrollView(
              slivers: [
                SliverAppBar.large(title: Text('相册'), pinned: true),
                SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            );
          }

          if (snapshot.hasError) {
            return CustomScrollView(
              slivers: [
                _buildLargeAppBar(),
                SliverFillRemaining(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 48,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '加载相册失败',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 180,
                          child: PrimaryButton(
                            text: '重新加载',
                            icon: Icons.refresh,
                            onPressed: _refreshData,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final eventEntities = snapshot.data ?? [];

          if (eventEntities.isEmpty) {
            return CustomScrollView(
              slivers: [
                _buildLargeAppBar(),
                SliverFillRemaining(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.photo_library_outlined,
                          size: 52,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '还没有相册事件',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '点击右上角扫描，从你的照片里自动聚类出值得讲述的瞬间。',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        PrimaryButton(
                          text: '扫描相册',
                          icon: Icons.add_photo_alternate_outlined,
                          onPressed: _refreshData,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return FutureBuilder<Map<String, List<Event>>>(
            future: _groupEvents(eventEntities),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final groupedEvents = groupSnapshot.data!;

              return RefreshIndicator(
                onRefresh: _refreshData,
                child: CustomScrollView(
                  slivers: [
                    _buildLargeAppBar(),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                        child: Text(
                          '你的照片故事',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    ...groupedEvents.entries.map((entry) {
                      return SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                entry.key,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ...entry.value.map(
                              (event) => EventCard(event: event),
                            ),
                          ]),
                        ),
                      );
                    }),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLargeAppBar() {
    return SliverAppBar.large(
      pinned: true,
      title: const Text('相册'),
      actions: [
        IconButton(
          icon: const Icon(Icons.cleaning_services),
          onPressed: _isRefreshing ? null : _resetCacheAndRescan,
          tooltip: '清空缓存并重扫',
        ),
        IconButton(
          icon: _isRefreshing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onPressed: _isRefreshing ? null : _refreshData,
          tooltip: '扫描相册并聚类',
        ),
      ],
    );
  }

  Future<Map<String, List<Event>>> _groupEvents(
    List<EventEntity> eventEntities,
  ) async {
    final grouped = <String, List<Event>>{};
    final isar = PhotoService().isar;

    for (final entity in eventEntities) {
      final event = await entity.toUIModel(isar);

      final key = '${event.year} · ${event.season}';

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(event);
    }

    return grouped;
  }
}
