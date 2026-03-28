import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../widgets/path_image_editorial.dart';
import '../widgets/primary_button.dart';
import 'theme_selection_page.dart';

class PhotoSelectionPage extends StatefulWidget {
  const PhotoSelectionPage({super.key, required this.event});

  final Event event;

  @override
  State<PhotoSelectionPage> createState() => _PhotoSelectionPageState();
}

class _PhotoSelectionPageState extends State<PhotoSelectionPage> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.event.photos.map((photo) => photo.id).toSet();
  }

  Future<void> _toggleSelection(Photo photo) async {
    await HapticFeedback.lightImpact();
    setState(() {
      if (_selectedIds.contains(photo.id)) {
        _selectedIds.remove(photo.id);
      } else {
        _selectedIds.add(photo.id);
      }
    });
  }

  Future<void> _goNext() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片')));
      return;
    }

    final selectedPhotos = widget.event.photos
        .where((photo) => _selectedIds.contains(photo.id))
        .toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ThemeSelectionPage(
          event: widget.event,
          selectedPhotos: selectedPhotos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedIds.length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: const Text('选择照片'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: _GlassCountPill(label: '$selectedCount selected'),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                '选择 $selectedCount 张精彩图片用于生成故事',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 96,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final photo = widget.event.photos[index];
              final isSelected = _selectedIds.contains(photo.id);

              return GestureDetector(
                onTap: () => _toggleSelection(photo),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    Positioned.fill(
                      child: PathImageEditorial(
                        path: photo.path,
                        borderRadius: 0,
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      color: isSelected
                          ? Colors.transparent
                          : Colors.black.withValues(alpha: 0.14),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _SelectionBadge(isSelected: isSelected),
                    ),
                  ],
                ),
              );
            }, childCount: widget.event.photos.length),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              _GlassCountPill(label: '$selectedCount selected'),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  text: '下一步',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _goNext,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xAA007AFF)
                : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: isSelected ? 0.55 : 0.24),
            ),
          ),
          child: Icon(
            Icons.check_rounded,
            size: 16,
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _GlassCountPill extends StatelessWidget {
  const _GlassCountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
