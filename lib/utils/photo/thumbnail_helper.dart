import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ThumbnailHelper {
  static Future<File?> generateThumbnail({
    required String imagePath,
    required int maxWidth,
    required int maxHeight,
  }) async {
    try {
      // 读取原图
      final File imageFile = File(imagePath);
      if (!imageFile.existsSync()) {
        return null;
      }

      // 读取图片数据
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        return null;
      }

      // 计算缩略图尺寸
      final int width = originalImage.width;
      final int height = originalImage.height;

      int thumbnailWidth = maxWidth;
      int thumbnailHeight = maxHeight;

      if (width > height) {
        thumbnailHeight = (height * maxWidth / width).round();
      } else {
        thumbnailWidth = (width * maxHeight / height).round();
      }

      // 生成缩略图
      final img.Image thumbnail = img.copyResize(
        originalImage,
        width: thumbnailWidth,
        height: thumbnailHeight,
      );

      // 保存缩略图
      final String thumbnailPath = '${imagePath}_thumb.jpg';
      final File thumbnailFile = File(thumbnailPath);
      final Uint8List thumbnailBytes = img.encodeJpg(thumbnail, quality: 70);
      await thumbnailFile.writeAsBytes(thumbnailBytes);

      return thumbnailFile;
    } catch (e) {
      print('生成缩略图失败: $e');
      return null;
    }
  }

  static Future<void> clearThumbnails(String imagePath) async {
    try {
      final String thumbnailPath = '${imagePath}_thumb.jpg';
      final File thumbnailFile = File(thumbnailPath);
      if (thumbnailFile.existsSync()) {
        await thumbnailFile.delete();
      }
    } catch (e) {
      print('清除缩略图失败: $e');
    }
  }
}
