import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import 'ai_service.dart'; // 导入 AI 服务

class PhotoService {
  late Isar _isar;

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  // 私有构造函数
  PhotoService._internal();

  // 暴露 isar 实例供其他服务使用
  Isar get isar => _isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [PhotoEntitySchema, EventEntitySchema], // 同时注册 EventEntity
      directory: dir.path,
    );
  }

  // 1️⃣ 扫描相册 (快速入库，带截图过滤)
  Future<void> scanAndSyncPhotos() async {
    // 权限检查
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) return;

    // 获取图片资源
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image, // 📸 只读图片，过滤视频
      onlyAll: true,
    );

    if (albums.isEmpty) return;

    // 假设取前 200 张做测试
    final List<AssetEntity> assets = await albums[0].getAssetListRange(
      start: 0,
      end: 200,
    );

    print("🚀 开始扫描相册...");

    await _isar.writeTxn(() async {
      for (final asset in assets) {
        // 增量更新检查
        final existing = await _isar
            .collection<PhotoEntity>()
            .filter()
            .assetIdEqualTo(asset.id)
            .findFirst();
        if (existing != null) continue;

        final file = await asset.file;
        if (file == null) continue;

        // 📐 获取图片尺寸并过滤截图
        final width = asset.width;
        final height = asset.height;

        // 计算宽高比，过滤极端比例的图片（可能是截图）
        final ratio = width / height;
        if (ratio < 0.45 || ratio > 2.2) {
          print("⏭️  跳过截图: ${file.path.split('/').last} (比例: ${ratio.toStringAsFixed(2)})");
          continue; // 跳过截图
        }

        final latLong = await asset.latlngAsync();
        // 检查是否有有效 GPS
        final hasGps =
            latLong != null && latLong.latitude != 0 && latLong.longitude != 0;

        final newPhoto = PhotoEntity()
          ..assetId = asset.id
          ..timestamp = asset.createDateTime.millisecondsSinceEpoch
          ..path = file.path
          ..width = width
          ..height = height
          ..latitude = latLong?.latitude
          ..longitude = latLong?.longitude
          // 如果没 GPS，直接标记为已处理，防止后续无效请求
          ..isLocationProcessed = !hasGps;

        await _isar.collection<PhotoEntity>().put(newPhoto);
      }
    });

    print("✅ 基础数据同步完成 (已过滤截图)");

    // 2️⃣ 🚀 启动 AI 视觉分析 (Slow Sync)
    // 不 await，完全独立在后台运行
    AIService().analyzePhotosInBackground();
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

    return {
      'total': total,
      'withGPS': withGPS,
      'aiAnalyzed': aiAnalyzed,
    };
  }
}
