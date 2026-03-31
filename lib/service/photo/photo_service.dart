import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../utils/photo/photo_filter_helper.dart';
import 'photo_asset_mapper.dart';
import 'photo_scan_context.dart';

class PhotoService {
  late Isar _isar;
  final ValueNotifier<int> _localDataVersion = ValueNotifier<int>(0);

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  // 私有构造函数
  PhotoService._internal();

  // 暴露 isar 实例供其他服务使用
  Isar get isar => _isar;
  ValueListenable<int> get localDataVersion => _localDataVersion;

  void markLocalDataChanged() {
    _localDataVersion.value++;
  }

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [PhotoEntitySchema, EventEntitySchema, StoryEntitySchema], // 注册所有实体
      directory: dir.path,
      inspector: kDebugMode,
    );
  }

  Future<void> clearAllCachedData() async {
    await _isar.writeTxn(() async {
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
    });

    markLocalDataChanged();

    print("🗑️ 已清空全部本地 Isar 数据（照片/事件/故事）");
  }

  // 1️⃣ 扫描相册 (分页入库，带截图过滤)
  Future<PhotoScanSummary> scanAndSyncPhotos({
    int pageSize = 200,
    int? maxScanCount,
  }) async {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', '必须大于 0');
    }
    if (maxScanCount != null && maxScanCount <= 0) {
      throw ArgumentError.value(maxScanCount, 'maxScanCount', '必须大于 0');
    }

    final totalBefore = await _isar.collection<PhotoEntity>().count();

    // 权限检查
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '未获得相册访问权限，请在系统设置中允许访问照片。',
      );
    }

    // 获取图片资源
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image, // 📸 只读图片，过滤视频
      onlyAll: true,
    );

    if (albums.isEmpty) {
      throw const PhotoScanException(PhotoScanError.noAlbum, '未找到可读取的相册。');
    }

    // 先做反向同步：清理系统相册已删除/已不可访问的照片
    final removedCount = await _removeUnavailablePhotos();

    print("🚀 开始扫描相册（分页模式）...");

    final counters = PhotoScanCounters();

    final targetAlbum = albums.first;
    final context = PhotoScanContext(
      pageSize: pageSize,
      maxScanCount: maxScanCount,
    );

    while (true) {
      final currentPageSize = context.currentPageSize;
      if (currentPageSize == null || currentPageSize <= 0) {
        break;
      }

      final batch = await targetAlbum.getAssetListRange(
        start: context.offset,
        end: context.offset + currentPageSize,
      );
      if (batch.isEmpty) {
        break;
      }

      counters.onPageScanned(batch.length);
      print(
        "📦 扫描第${counters.scannedPageCount}页: 起始=${context.offset} "
        "本页=${batch.length} 累计=${counters.scannedAssetCount}",
      );

      await _scanPage(batch: batch, counters: counters);

      context.onBatchProcessed(batch.length);
      if (batch.length < currentPageSize) {
        break;
      }
    }

    print(
      "✅ 基础数据同步完成: 扫描页数=${counters.scannedPageCount} "
      "扫描总量=${counters.scannedAssetCount} 删除=$removedCount "
      "入库=${counters.insertedCount} 其中无GPS入库=${counters.insertedNoGps} "
      "跳过[无时间=${counters.skippedInvalidTime} 截图=${counters.skippedScreenshot}]",
    );

    final totalAfter = await _isar.collection<PhotoEntity>().count();
    if (totalAfter == 0) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '未找到可用照片：请确认相册中存在包含有效时间的图片资源。',
      );
    }

    // AI 分析由上层流程在聚类后触发，确保 eventId 已建立
    markLocalDataChanged();
    return PhotoScanSummary(
      totalBefore: totalBefore,
      totalAfter: totalAfter,
      removedCount: removedCount,
      insertedCount: counters.insertedCount,
      skippedInvalidTime: counters.skippedInvalidTime,
      insertedNoGps: counters.insertedNoGps,
      skippedNonCamera: counters.skippedNonCamera,
      skippedScreenshot: counters.skippedScreenshot,
    );
  }

  Future<void> _scanPage({
    required List<AssetEntity> batch,
    required PhotoScanCounters counters,
  }) async {
    for (final asset in batch) {
      await _processAsset(asset: asset, counters: counters);
    }
  }

  Future<void> _processAsset({
    required AssetEntity asset,
    required PhotoScanCounters counters,
  }) async {
    final file = await asset.file;
    final latLong = await asset.latlngAsync();
    // 过滤顺序：已入库 -> 时间 -> 尺寸 -> 截图 -> GPS，保证统计口径稳定。
    final existing = await _isar
        .collection<PhotoEntity>()
        .filter()
        .assetIdEqualTo(asset.id)
        .findFirst();
    if (existing != null || file == null) {
      return;
    }

    final timestamp = asset.createDateTime.millisecondsSinceEpoch;
    if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
      counters.skippedInvalidTime++;
      return;
    }

    final width = asset.width;
    final height = asset.height;
    if (width <= 0 || height <= 0) {
      counters.skippedNonCamera++;
      return;
    }

    if (PhotoFilterHelper.isLikelyScreenshotByRatio(width, height)) {
      counters.skippedScreenshot++;
      print("⏭️  跳过截图: ${file.path.split('/').last} (宽=$width 高=$height)");
      return;
    }

    final hasGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );
    if (!hasGps) counters.insertedNoGps++;

    final newPhoto = PhotoAssetMapper.toEntity(
      assetId: asset.id,
      timestamp: timestamp,
      filePath: file.path,
      width: width,
      height: height,
      latitude: hasGps ? latLong!.latitude : null,
      longitude: hasGps ? latLong!.longitude : null,
    );

    await _isar.writeTxn(() async {
      await _isar.collection<PhotoEntity>().put(newPhoto);
    });
    counters.insertedCount++;
  }

  Future<int> _removeUnavailablePhotos() async {
    final localPhotos = await _isar.collection<PhotoEntity>().where().findAll();
    if (localPhotos.isEmpty) {
      return 0;
    }

    final removedIds = <int>[];
    for (final photo in localPhotos) {
      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        removedIds.add(photo.id);
      }
    }

    if (removedIds.isEmpty) {
      return 0;
    }

    await _isar.writeTxn(() async {
      await _isar.collection<PhotoEntity>().deleteAll(removedIds);
    });

    print("🧹 已清理系统相册中删除/不可访问的照片: ${removedIds.length} 张");
    return removedIds.length;
  }

  // 📊 获取照片统计信息
  Future<Map<String, int>> getPhotoStats() async {
    final total = await _isar.collection<PhotoEntity>().count();
    final withGPS = await _isar
        .collection<PhotoEntity>()
        .filter()
        .latitudeIsNotNull()
        .count();
    final aiAnalyzed = await _isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .count();

    return {'total': total, 'withGPS': withGPS, 'aiAnalyzed': aiAnalyzed};
  }
}

enum PhotoScanError { permissionDenied, noAlbum, noEligiblePhoto }

class PhotoScanException implements Exception {
  final PhotoScanError code;
  final String message;

  const PhotoScanException(this.code, this.message);

  @override
  String toString() {
    return message;
  }
}

class PhotoScanSummary {
  final int totalBefore;
  final int totalAfter;
  final int removedCount;
  final int insertedCount;
  final int skippedInvalidTime;
  final int insertedNoGps;
  final int skippedNonCamera;
  final int skippedScreenshot;

  const PhotoScanSummary({
    required this.totalBefore,
    required this.totalAfter,
    required this.removedCount,
    required this.insertedCount,
    required this.skippedInvalidTime,
    required this.insertedNoGps,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });
}
