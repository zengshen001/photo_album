import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../widgets/path_image.dart';
import '../widgets/primary_button.dart';
import 'config_page.dart';

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final Set<String> _selectedPhotoIds = {};

  @override
  void initState() {
    super.initState();
    // Select all photos by default
    _selectedPhotoIds.addAll(widget.event.photos.map((p) => p.id));
  }

  void _togglePhotoSelection(Photo photo) {
    setState(() {
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
      } else {
        _selectedPhotoIds.add(photo.id);
      }
    });
  }

  void _navigateToConfigPage() {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片')));
      return;
    }

    final selectedPhotos = widget.event.photos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigPage(
          event: widget.event,
          selectedPhotos: selectedPhotos,
          recommendedThemes: widget.event.aiThemes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(title: Text('选择照片'), pinned: true),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.event.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _InfoPill(
                            icon: Icons.calendar_today_outlined,
                            label: widget.event.dateRangeText,
                          ),
                          _InfoPill(
                            icon: Icons.location_on_outlined,
                            label: widget.event.location,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '已选择 ${_selectedPhotoIds.length} / ${widget.event.photos.length} 张照片',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '先专注筛选照片，下一步再选择 AI 主题并生成故事。',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final photo = widget.event.photos[index];
                final isSelected = _selectedPhotoIds.contains(photo.id);

                return GestureDetector(
                  onTap: () => _togglePhotoSelection(photo),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: PathImage(path: photo.path, fit: BoxFit.cover),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                          color: isSelected
                              ? Colors.transparent
                              : Colors.black.withValues(alpha: 0.18),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: const [],
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }, childCount: widget.event.photos.length),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PrimaryButton(
            text: '下一步：生成故事',
            icon: Icons.auto_stories_outlined,
            onPressed: () async => _navigateToConfigPage(),
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[800]),
          ),
        ],
      ),
    );
  }
}
