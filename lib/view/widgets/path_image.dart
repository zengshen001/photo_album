import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class PathImage extends StatelessWidget {
  final String path;
  final String? assetId;
  final BoxFit fit;
  final double? width;
  final double? height;

  const PathImage({
    super.key,
    required this.path,
    this.assetId,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedAssetId = assetId?.trim();
    if (normalizedAssetId != null && normalizedAssetId.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: _loadAssetThumbnail(normalizedAssetId),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              fit: fit,
              width: width,
              height: height,
              errorBuilder: (_, _, _) => _buildFromPath(),
            );
          }
          return _buildFromPath();
        },
      );
    }

    return _buildFromPath();
  }

  Future<Uint8List?> _loadAssetThumbnail(String normalizedAssetId) async {
    final asset = await AssetEntity.fromId(normalizedAssetId);
    if (asset == null) {
      return null;
    }
    return asset.thumbnailDataWithSize(const ThumbnailSize(1200, 1200));
  }

  Widget _buildFromPath() {
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme.toLowerCase();

    if (scheme == 'http' || scheme == 'https') {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }

    final file = _resolveLocalFile(uri);
    return Image.file(
      file,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  File _resolveLocalFile(Uri? uri) {
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File.fromUri(uri);
    }
    return File(path);
  }

  Widget _fallback() {
    return Container(
      color: Colors.grey.shade300,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
