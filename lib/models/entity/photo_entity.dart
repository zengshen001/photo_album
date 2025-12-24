import 'package:isar/isar.dart';

part 'photo_entity.g.dart';

@Collection()
class PhotoEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String assetId;

  late String path;
  late int timestamp;

  // 📍 地理坐标 (WGS84 标准坐标)
  double? latitude;
  double? longitude;

  // 🏙️ 地址信息 (高德解析结果)
  @Index()
  String? province; // 省：北京市 / 山东省

  @Index()
  String? city; // 市：北京市 / 青岛市 (直辖市这里可能为空或与省相同)

  String? district; // 区：朝阳区 / 市南区
  String? formattedAddress; // 完整地址：北京市朝阳区xx街道...

  String? adcode; // 城市编码 (如 110101)，用于精确数据分析

  // 状态标记
  bool isLocationProcessed = false;

  // 🤖 AI 分析相关
  List<String>? aiTags; // AI 识别的标签（美食、海滩等）
  bool isAiAnalyzed = false; // AI 分析状态标记
}
