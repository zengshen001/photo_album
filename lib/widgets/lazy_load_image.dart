import 'dart:io';
import 'package:flutter/material.dart';

class LazyLoadImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final bool loadImmediately;
  final bool useThumbnail;
  final int thumbnailWidth;
  final int thumbnailHeight;

  const LazyLoadImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.loadImmediately = false,
    this.useThumbnail = true,
    this.thumbnailWidth = 300,
    this.thumbnailHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    final placeholderWidget =
        placeholder ??
        Container(width: width, height: height, color: const Color(0xFFE5E5EA));

    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: useThumbnail ? thumbnailWidth : null,
      cacheHeight: useThumbnail ? thumbnailHeight : null,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) {
          return placeholderWidget;
        }
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            Container(
              width: width,
              height: height,
              color: const Color(0xFFE5E5EA),
              child: const Icon(Icons.error_outline, color: Color(0xFF8E8E93)),
            );
      },
    );
  }
}
