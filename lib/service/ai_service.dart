import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:isar/isar.dart';
import '../models/entity/photo_entity.dart';
import 'photo_service.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  // 简单的标签翻译字典 (毕设演示够用了，也可以接翻译API)
  final Map<String, String> _tagTranslation = {
    'Food': '美食',
    'Dish': '菜肴',
    'Cuisine': '料理',
    'Meal': '餐食',
    'Beach': '海滩',
    'Sea': '大海',
    'Ocean': '海洋',
    'Sky': '天空',
    'Cloud': '云',
    'Sunset': '日落',
    'Sunrise': '日出',
    'Plant': '植物',
    'Tree': '树木',
    'Flower': '花朵',
    'Grass': '草地',
    'Garden': '花园',
    'Person': '人像',
    'People': '人群',
    'Face': '面孔',
    'Child': '儿童',
    'Baby': '婴儿',
    'Cat': '猫',
    'Dog': '狗',
    'Pet': '宠物',
    'Animal': '动物',
    'Bird': '鸟',
    'Building': '建筑',
    'City': '城市',
    'Architecture': '建筑物',
    'Tower': '塔',
    'Bridge': '桥',
    'Mountain': '山',
    'Hill': '山丘',
    'Forest': '森林',
    'Landscape': '风景',
    'Car': '汽车',
    'Vehicle': '车辆',
    'Road': '道路',
    'Street': '街道',
    'Water': '水',
    'Lake': '湖',
    'River': '河',
    'Snow': '雪',
    'Winter': '冬天',
    'Summer': '夏天',
    'Spring': '春天',
    'Autumn': '秋天',
    'Fall': '秋天',
    'Night': '夜晚',
    'Evening': '傍晚',
    'Morning': '早晨',
    'Daytime': '白天',
    'Indoor': '室内',
    'Outdoor': '户外',
    'Room': '房间',
    'Bedroom': '卧室',
    'Kitchen': '厨房',
    'Restaurant': '餐厅',
    'Table': '桌子',
    'Chair': '椅子',
    'Furniture': '家具',
    'Window': '窗户',
    'Door': '门',
    'Wall': '墙',
    'Ceiling': '天花板',
    'Floor': '地板',
    'Art': '艺术',
    'Painting': '绘画',
    'Sculpture': '雕塑',
    'Museum': '博物馆',
    'Sport': '运动',
    'Game': '游戏',
    'Ball': '球',
    'Playground': '操场',
    'Park': '公园',
    'Festival': '节日',
    'Party': '派对',
    'Concert': '音乐会',
    'Stage': '舞台',
    'Light': '灯光',
    'Darkness': '黑暗',
    'Shadow': '阴影',
    'Reflection': '倒影',
    'Mirror': '镜子',
    'Glass': '玻璃',
    'Book': '书',
    'Paper': '纸',
    'Pen': '笔',
    'Computer': '电脑',
    'Phone': '手机',
    'Screen': '屏幕',
    'Technology': '科技',
    'Drink': '饮料',
    'Coffee': '咖啡',
    'Tea': '茶',
    'Wine': '酒',
    'Bottle': '瓶子',
    'Cup': '杯子',
    'Fruit': '水果',
    'Vegetable': '蔬菜',
    'Dessert': '甜点',
    'Cake': '蛋糕',
    'Bread': '面包',
    'Smile': '微笑',
    'Happy': '快乐',
    'Fun': '有趣',
    'Beautiful': '美丽',
    'Colorful': '色彩斑斓',
  };

  // 🧠 核心方法：批量分析未处理的照片
  Future<void> analyzePhotosInBackground() async {
    final isar = PhotoService().isar;

    // 1. 捞出所有还没分析过 AI 的照片
    // 每次限制 10 张，避免一次性占用太多内存
    final photos = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(false) // 只找 false 的
        .limit(10)
        .findAll();

    if (photos.isEmpty) {
      print("✅ 所有照片 AI 分析完成");
      return;
    }

    print("🤖 开始 AI 视觉分析，本批次: ${photos.length} 张");

    // 2. 初始化 ML Kit Labeler
    final ImageLabelerOptions options = ImageLabelerOptions(
      confidenceThreshold: 0.6, // 置信度 > 0.6 才要
    );
    final imageLabeler = ImageLabeler(options: options);

    for (final photo in photos) {
      // 检查文件是否存在
      final file = File(photo.path);
      if (!file.existsSync()) {
        // 文件丢了，标记为已处理以免死循环
        await _markAsAnalyzed(photo.id, [], isar);
        print("⚠️ 文件不存在，跳过: ${photo.path}");
        continue;
      }

      try {
        // 3. 识别
        final inputImage = InputImage.fromFile(file);
        final labels = await imageLabeler.processImage(inputImage);

        // 4. 提取标签并翻译
        List<String> validTags = [];
        for (ImageLabel label in labels) {
          final text = label.label;
          // 如果有中文映射就用中文，没有就保留英文
          final translated = _tagTranslation[text] ?? text;
          validTags.add(translated);
        }

        // 5. 存入数据库
        await _markAsAnalyzed(photo.id, validTags, isar);
        final fileName = photo.path.split('/').last;
        print("✅ [AI] $fileName -> $validTags");
      } catch (e) {
        print("❌ AI 分析失败: $e");
        // 失败了也暂时标记为 true，避免死循环
        // 实际项目中可以记录错误次数，重试机制等
        await _markAsAnalyzed(photo.id, [], isar);
      }

      // ⏳ 休息一下，防止 UI 掉帧 (AI 运算很吃 CPU)
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 6. 关闭资源
    imageLabeler.close();

    // 🔄 递归调用：如果还有没处理的，继续下一批
    // 这样形成一个后台队列，直到所有照片处理完
    analyzePhotosInBackground();
  }

  // 将 AI 分析结果写入数据库
  Future<void> _markAsAnalyzed(Id id, List<String> tags, Isar isar) async {
    await isar.writeTxn(() async {
      final p = await isar.collection<PhotoEntity>().get(id);
      if (p != null) {
        p.aiTags = tags;
        p.isAiAnalyzed = true;
        await isar.collection<PhotoEntity>().put(p);
      }
    });
  }

  // 📊 工具方法：获取 AI 分析进度
  Future<Map<String, int>> getAnalysisProgress() async {
    final isar = PhotoService().isar;

    final total = await isar.collection<PhotoEntity>().count();
    final analyzed =
        await isar.collection<PhotoEntity>().filter().isAiAnalyzedEqualTo(true).count();

    return {
      'total': total,
      'analyzed': analyzed,
      'pending': total - analyzed,
    };
  }
}
