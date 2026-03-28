import 'package:flutter/material.dart';

import 'path_image.dart';

class PathImageEditorial extends StatelessWidget {
  const PathImageEditorial({
    super.key,
    required this.path,
    this.assetId,
    this.width,
    this.height,
    this.borderRadius = 22,
    this.fit = BoxFit.cover,
  });

  final String path;
  final String? assetId;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: PathImage(
        path: path,
        assetId: assetId,
        width: width,
        height: height,
        fit: fit,
      ),
    );
  }
}
