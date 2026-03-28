import 'dart:io';
import 'package:flutter/material.dart';


import '../../models/event.dart';
import '../../service/event/event_service.dart';
import '../../service/photo/photo_service.dart';
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('回忆'),
            surfaceTintColor: Colors.transparent,
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            pinned: true,
          ),
          StreamBuilder<List<Event>>(
            stream: _eventsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              
              if (snapshot.hasError) {
                return SliverFillRemaining(
                  child: Center(child: Text('加载失败 ${snapshot.error}')),
                );
              }

              final events = snapshot.data;
              if (events == null || events.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text('暂无聚类回忆，点击右上角重新扫描'),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(bottom: 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final event = events[index];
                      return _EventFeedCard(event: event);
                    },
                    childCount: events.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          EventService().runClustering();
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class _EventFeedCard extends StatelessWidget {
  final Event event;

  const _EventFeedCard({required this.event});

  @override
  Widget build(BuildContext context) {
    if (event.photos.isEmpty) return const SizedBox.shrink();
    
    // Choose cover
    final coverPhoto = event.photos.first;
    
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EventDetailPage(event: event),
          ),
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
            )
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
              
              // Gradient Overlay
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
              
              // Title & Meta details
              Positioned(
                left: 20,
                bottom: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
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
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.white70, size: 16),
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
                        const Icon(Icons.calendar_today, color: Colors.white70, size: 14),
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
