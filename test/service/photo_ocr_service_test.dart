import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/ai/ocr_feature_flags.dart';
import 'package:photo_album/service/ai/photo_ocr_service.dart';

void main() {
  group('PhotoOcrService', () {
    test('cleanText removes noise and deduplicates lines', () {
      final cleaned = PhotoOcrService.cleanText('''
毕业典礼
12345
毕业典礼

计算机学院
  2026届  
''');

      expect(cleaned, contains('毕业典礼'));
      expect(cleaned, contains('计算机学院'));
      expect(cleaned, isNot(contains('12345')));
    });

    test('recognizeText is disabled by default', () async {
      expect(OcrFeatureFlags.enablePhotoOcr, isFalse);
      final service = const PhotoOcrService();
      final result = await service.recognizeText(File('/tmp/not_used.jpg'));

      expect(result.isEnabled, isFalse);
      expect(result.isProcessed, isFalse);
      expect(result.cleanedText, isNull);
    });
  });
}
