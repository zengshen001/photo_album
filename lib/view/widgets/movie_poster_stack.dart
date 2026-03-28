import 'dart:ui';

import 'package:flutter/material.dart';

import 'path_image_editorial.dart';

class MoviePosterStack extends StatelessWidget {
  const MoviePosterStack({
    super.key,
    required this.title,
    this.subtitle,
    this.topBadge,
    this.metaLine,
    this.path,
    this.assetId,
    this.background,
    this.borderRadius = 24,
    this.onTap,
    this.isSelected = false,
    this.padding = const EdgeInsets.all(18),
  }) : assert(path != null || background != null);

  final String title;
  final String? subtitle;
  final String? topBadge;
  final String? metaLine;
  final String? path;
  final String? assetId;
  final Widget? background;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool isSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      fit: StackFit.expand,
      children: [
        if (background != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: background,
          )
        else
          Positioned.fill(
            child: PathImageEditorial(
              path: path!,
              assetId: assetId,
              borderRadius: borderRadius,
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.12),
                  Colors.black.withValues(alpha: 0.82),
                ],
                stops: const [0.15, 0.52, 1],
              ),
            ),
          ),
        ),
        if (topBadge != null)
          Positioned(
            top: 16,
            right: 16,
            child: _GlassPill(
              label: topBadge!,
              icon: Icons.photo_library_outlined,
            ),
          ),
        Positioned(
          left: padding.left,
          right: padding.right,
          bottom: padding.bottom,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (metaLine != null) ...[
                _GlassPill(label: metaLine!),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
            ),
          ),
      ],
    );

    if (onTap == null) {
      return content;
    }

    return GestureDetector(onTap: onTap, child: content);
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
