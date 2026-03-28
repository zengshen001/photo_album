import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../widgets/movie_poster_stack.dart';
import '../widgets/primary_button.dart';
import 'photo_selection_page.dart';

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  Future<void> _openPhotoSelection() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhotoSelectionPage(event: widget.event),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverPhoto = widget.event.coverPhotos.isNotEmpty
        ? widget.event.coverPhotos.first
        : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 420,
            title: Text(widget.event.title),
            flexibleSpace: FlexibleSpaceBar(
              background: MoviePosterStack(
                title: widget.event.title,
                subtitle: widget.event.tags.take(3).join(' · '),
                topBadge: '${widget.event.photos.length} 张',
                metaLine:
                    '${widget.event.dateRangeText} · ${widget.event.location}',
                path: coverPhoto?.path,
                assetId: coverPhoto?.id,
                borderRadius: 0,
                background: coverPhoto == null
                    ? Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1C1C1E), Color(0xFF3A3A3C)],
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '故事预设',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '从这个事件里挑选最精彩的照片，再选择一个叙事主题，让 AI 生成更有电影感的图文故事。',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[700],
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InfoPill(label: '${widget.event.photos.length} 张照片'),
                      _InfoPill(label: widget.event.dateRangeText),
                      _InfoPill(label: widget.event.location),
                    ],
                  ),
                  if (widget.event.tags.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.event.tags.take(8).map((tag) {
                        return _InfoPill(label: tag);
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  PrimaryButton(
                    text: '生成 AI 故事',
                    icon: Icons.auto_stories_outlined,
                    onPressed: _openPhotoSelection,
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.grey[800]),
      ),
    );
  }
}
