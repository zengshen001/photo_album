import 'package:dio/dio.dart'; // 引入 Dio
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/entity/photo_entity.dart';
import 'ai_service.dart'; // 导入 AI 服务

class PhotoService {
  late Isar _isar;
  final Dio _dio = Dio();

  // 🔑 你的高德 Web 服务 Key (一定要去申请一个填在这里)
  static const String _amapWebKey = "你的高德Key填在这里";

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  // 私有构造函数
  PhotoService._internal();

  // 暴露 isar 实例供其他服务使用
  Isar get isar => _isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open([PhotoEntitySchema], directory: dir.path);
  }

  // 1️⃣ 扫描相册 (快速入库，不含地址)
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

        final latLong = await asset.latlngAsync();
        // 检查是否有有效 GPS
        final hasGps =
            latLong != null && latLong.latitude != 0 && latLong.longitude != 0;

        final newPhoto = PhotoEntity()
          ..assetId = asset.id
          ..timestamp = asset.createDateTime.millisecondsSinceEpoch
          ..path = file.path
          ..latitude = latLong?.latitude
          ..longitude = latLong?.longitude
          // 如果没 GPS，直接标记为已处理，防止后续无效请求
          ..isLocationProcessed = !hasGps;

        await _isar.collection<PhotoEntity>().put(newPhoto);
      }
    });

    print("✅ 基础数据同步完成，开始调用高德 API 解析地址...");

    // 2️⃣ 启动后台解析任务
    _resolveAddressWithAmap();

    // 3️⃣ 🚀 启动 AI 视觉分析 (Slow Sync)
    // 同样不 await，完全独立在后台运行
    AIService().analyzePhotosInBackground();
  }

  // 🌏 后台任务：高德逆地理编码 (优化版)
  Future<void> _resolveAddressWithAmap() async {
    // 1. 查出需要解析的照片
    final photos = await _isar
        .collection<PhotoEntity>()
        .filter()
        .latitudeIsNotNull()
        .isLocationProcessedEqualTo(false)
        .limit(20) // ⚡️ 降低单次并发量，高德个人开发者 QPS 限制较严(通常 < 50)
        .findAll();

    if (photos.isEmpty) return;

    print("🌏 开始解析 ${photos.length} 张照片地址...");

    for (final photo in photos) {
      bool success = false;

      try {
        // 文档: https://lbs.amap.com/api/webservice/guide/api/georegeo
        final response = await _dio.get(
          "https://restapi.amap.com/v3/geocode/regeo",
          queryParameters: {
            "key": _amapWebKey,
            "location": "${photo.longitude},${photo.latitude}",
            "extensions": "base",
            "radius": 1000,
            // ✨ 关键修复：告诉高德传入的是 GPS (WGS84) 坐标
            // 高德会自动纠偏，解决几百米的位移误差
            "coordsys": "gps",
          },
        );

        if (response.statusCode == 200 && response.data['status'] == '1') {
          final regeocode = response.data['regeocode'];
          final addressComponent = regeocode['addressComponent'];

          await _isar.writeTxn(() async {
            // 重新获取对象以防并发修改
            final p = await _isar.collection<PhotoEntity>().get(photo.id);
            if (p != null) {
              p.formattedAddress = regeocode['formatted_address'];

              // 处理直辖市 city 为空的情况
              final rawProvince = addressComponent['province'];
              final rawCity = addressComponent['city'];

              p.province = rawProvince is String ? rawProvince : "";

              // 如果 city 是空的（如北京、上海），用 province 填充
              if (rawCity is String && rawCity.isNotEmpty) {
                p.city = rawCity;
              } else {
                p.city = p.province;
              }

              p.district = addressComponent['district'] is String
                  ? addressComponent['district']
                  : "";
              p.adcode = addressComponent['adcode'] is String
                  ? addressComponent['adcode']
                  : "";

              // 标记为成功
              p.isLocationProcessed = true;
              await _isar.collection<PhotoEntity>().put(p);
            }
          });
          success = true;
          print("📍 [精准修正] 解析成功: ${regeocode['formatted_address']}");
        } else {
          print("⚠️ 高德 API 业务错误: ${response.data['info']}");
          // 如果是 key 过期或额度耗尽，可以在这里做额外处理
        }
      } catch (e) {
        print("❌ 网络请求失败: $e");
      }

      // 🛑 如果处理失败，这次循环不标记为 true，
      // 这样下次启动 App 时（或者用户手动刷新时）还会尝试重新解析。

      // ⏳ 必须延时！
      // 高德免费版 Web 服务限制较严，不加延时极易触发 "USER_DAILY_QUERY_OVER_LIMIT"
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }
}
