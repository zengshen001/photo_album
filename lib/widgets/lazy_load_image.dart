import 'dart:io';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../utils/photo/thumbnail_helper.dart';

class LazyLoadImage extends StatefulWidget {
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
  State<LazyLoadImage> createState() => _LazyLoadImageState();
}

class _LazyLoadImageState extends State<LazyLoadImage> {
  bool _isVisible = false;
  bool _isLoading = false;
  String? _thumbnailPath;
  final _visibilityKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final shouldLoadImage = widget.loadImmediately || _isVisible;

    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.1 && !_isVisible) {
          setState(() {
            _isVisible = true;
            if (widget.useThumbnail) {
              _generateThumbnail();
            }
          });
        }
      },
      child: shouldLoadImage ? _buildImage() : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: const Color(0xFFE5E5EA),
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E8E93)),
            ),
          ),
        );
  }

  void _generateThumbnail() async {
    if (!widget.useThumbnail) return;

    try {
      final thumbnailFile = await ThumbnailHelper.generateThumbnail(
        imagePath: widget.path,
        maxWidth: widget.thumbnailWidth,
        maxHeight: widget.thumbnailHeight,
      );

      if (thumbnailFile != null) {
        setState(() {
          _thumbnailPath = thumbnailFile.path;
        });
      }
    } catch (e) {
      print('生成缩略图失败: $e');
    }
  }

  Widget _buildImage() {
    if (!_isLoading) {
      _isLoading = true;
    }

    final imagePath = _thumbnailPath ?? widget.path;

    return Image.file(
      File(imagePath),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ??
            Container(
              width: widget.width,
              height: widget.height,
              color: const Color(0xFFE5E5EA),
              child: const Icon(Icons.error_outline, color: Color(0xFF8E8E93)),
            );
      },
    );
  }
}
