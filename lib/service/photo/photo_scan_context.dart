import 'dart:math' as math;

class PhotoScanCounters {
  int skippedInvalidTime = 0;
  int insertedNoGps = 0;
  int skippedNonCamera = 0;
  int skippedScreenshot = 0;
  int insertedCount = 0;
  int scannedAssetCount = 0;
  int scannedPageCount = 0;

  void onPageScanned(int size) {
    scannedPageCount++;
    scannedAssetCount += size;
  }
}

class PhotoScanContext {
  final int pageSize;
  int offset = 0;
  int? remaining;

  PhotoScanContext({required this.pageSize, required int? maxScanCount})
    : remaining = maxScanCount;

  int? get currentPageSize {
    if (remaining == null) {
      return pageSize;
    }
    if (remaining! <= 0) {
      return null;
    }
    return math.min(pageSize, remaining!);
  }

  void onBatchProcessed(int batchSize) {
    offset += batchSize;
    if (remaining != null) {
      remaining = remaining! - batchSize;
    }
  }
}
