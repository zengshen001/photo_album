import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/photo/photo_scan_context.dart';

void main() {
  group('PhotoScanContext', () {
    test('computes page size and remaining correctly', () {
      final context = PhotoScanContext(pageSize: 200, maxScanCount: 450);

      expect(context.currentPageSize, 200);
      expect(context.offset, 0);

      context.onBatchProcessed(200);
      expect(context.currentPageSize, 200);
      expect(context.offset, 200);

      context.onBatchProcessed(200);
      expect(context.currentPageSize, 50);
      expect(context.offset, 400);

      context.onBatchProcessed(50);
      expect(context.currentPageSize, isNull);
      expect(context.offset, 450);
    });
  });

  group('PhotoScanCounters', () {
    test('accumulates page stats', () {
      final counters = PhotoScanCounters();
      counters.onPageScanned(120);
      counters.onPageScanned(80);

      expect(counters.scannedPageCount, 2);
      expect(counters.scannedAssetCount, 200);
    });
  });
}
