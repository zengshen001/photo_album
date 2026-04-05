import 'dart:io';

import 'ocr_feature_flags.dart';

class PhotoOcrResult {
  final bool isEnabled;
  final bool isProcessed;
  final String? rawText;
  final String? cleanedText;

  const PhotoOcrResult({
    required this.isEnabled,
    required this.isProcessed,
    required this.rawText,
    required this.cleanedText,
  });

  const PhotoOcrResult.disabled()
    : isEnabled = false,
      isProcessed = false,
      rawText = null,
      cleanedText = null;
}

class PhotoOcrService {
  const PhotoOcrService();

  Future<PhotoOcrResult> recognizeText(File file) async {
    if (!OcrFeatureFlags.enablePhotoOcr) {
      return const PhotoOcrResult.disabled();
    }

    // OCR 预埋实现位：当前默认关闭，不改变现有运行逻辑。
    // 启用时建议接入 google_mlkit_text_recognition，并使用下述流程：
    //
    // import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
    //
    // final inputImage = InputImage.fromFile(file);
    // final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    // final recognized = await recognizer.processImage(inputImage);
    // await recognizer.close();
    // final rawText = recognized.text.trim();
    // final cleaned = cleanText(rawText);
    // return PhotoOcrResult(
    //   isEnabled: true,
    //   isProcessed: true,
    //   rawText: rawText.isEmpty ? null : rawText,
    //   cleanedText: cleaned.isEmpty ? null : cleaned,
    // );

    return const PhotoOcrResult.disabled();
  }

  static String cleanText(String input) {
    final lines = input
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => line.length >= 2)
        .where((line) => !RegExp(r'^\d+$').hasMatch(line))
        .toList();

    final unique = <String>{};
    final cleaned = <String>[];
    for (final line in lines) {
      final normalized = line.replaceAll(RegExp(r'\s+'), ' ');
      if (unique.add(normalized)) {
        cleaned.add(normalized);
      }
    }
    return cleaned.take(8).join(' | ');
  }
}
