import 'package:isar/isar.dart';
import 'photo_entity.dart';
import '../event.dart';
import '../vo/photo.dart';

part 'event_entity.g.dart';

@Collection()
class EventEntity {
  Id id = Isar.autoIncrement;

  // 📅 事件基本信息
  late String title; // 事件标题，默认为日期（如 "8月15日-8月18日"）
  late int startTime; // 开始时间戳 (毫秒)
  late int endTime; // 结束时间戳 (毫秒)

  // 📍 聚类中心点坐标 (可能为空，如果所有照片都没有GPS)
  double? avgLatitude;
  double? avgLongitude;

  // 🏙️ 地理位置信息 (从高德解析)
  String? city; // 城市名称（如 "青岛市"）
  String? province; // 省份（如 "山东省"）

  // 📸 关联的照片
  List<int> photoIds = []; // 关联的 PhotoEntity 的 id 列表

  // 🖼️ 封面图
  int? coverPhotoId; // 封面图的 PhotoEntity id (可为空，自动取第一张)

  // 🏷️ 标签和主题
  List<String> tags = []; // 聚合的标签（从照片 AI 标签统计得出）

  // 📊 统计信息
  int photoCount = 0; // 照片数量（冗余字段，方便查询）

  // 🎨 季节推导 (根据月份自动计算)
  String get season {
    final date = DateTime.fromMillisecondsSinceEpoch(startTime);
    final month = date.month;
    if (month >= 3 && month <= 5) return '春天';
    if (month >= 6 && month <= 8) return '夏天';
    if (month >= 9 && month <= 11) return '秋天';
    return '冬天';
  }

  // 📅 年份
  int get year {
    final date = DateTime.fromMillisecondsSinceEpoch(startTime);
    return date.year;
  }

  // 🌆 位置描述（优先使用 city，如果为空则返回 "未知地点"）
  String get location => city ?? province ?? '未知地点';

  // 📆 格式化日期范围
  String get dateRangeText {
    final start = DateTime.fromMillisecondsSinceEpoch(startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(endTime);
    final startStr = '${start.month}月${start.day}日';
    final endStr = '${end.month}月${end.day}日';

    if (start.month == end.month && start.day == end.day) {
      return startStr;
    }
    return '$startStr - $endStr';
  }

  // 🔄 转换为 UI 层的 Event 模型
  Future<Event> toUIModel(Isar isar) async {
    // 1. 根据 photoIds 查询出所有照片
    final photoEntities = await isar.collection<PhotoEntity>()
        .where()
        .anyOf(photoIds, (q, id) => q.idEqualTo(id))
        .sortByTimestamp() // 按时间顺序排列
        .findAll();

    // 2. 转换为 UI 层的 Photo 对象
    final photos = photoEntities.map((entity) {
      return Photo(
        id: entity.assetId, // 使用 assetId 作为 Photo 的 id
        path: entity.path,
        dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
        tags: entity.aiTags ?? [],
        location: entity.city ?? entity.province,
      );
    }).toList();

    // 3. 构造 Event 对象
    return Event(
      id: id.toString(),
      title: title,
      season: season,
      year: year,
      location: location,
      startDate: DateTime.fromMillisecondsSinceEpoch(startTime),
      endDate: DateTime.fromMillisecondsSinceEpoch(endTime),
      photos: photos,
      tags: tags,
      aiThemes: [], // AI 主题暂时为空，后续可以根据标签生成
    );
  }

  // 📊 从照片列表生成事件的工厂方法
  static EventEntity fromPhotos(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      throw ArgumentError('Cannot create event from empty photo list');
    }

    // 按时间排序
    photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final event = EventEntity()
      ..startTime = photos.first.timestamp
      ..endTime = photos.last.timestamp
      ..photoIds = photos.map((p) => p.id).toList()
      ..photoCount = photos.length
      ..coverPhotoId = photos.first.id;

    // 计算中心坐标
    final photosWithGPS =
        photos.where((p) => p.latitude != null && p.longitude != null).toList();
    if (photosWithGPS.isNotEmpty) {
      event.avgLatitude =
          photosWithGPS.map((p) => p.latitude!).reduce((a, b) => a + b) /
              photosWithGPS.length;
      event.avgLongitude =
          photosWithGPS.map((p) => p.longitude!).reduce((a, b) => a + b) /
              photosWithGPS.length;
    }

    // 聚合标签（取出现频率最高的前5个）
    final tagCounts = <String, int>{};
    for (var photo in photos) {
      if (photo.aiTags != null) {
        for (var tag in photo.aiTags!) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }
    final sortedTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    event.tags = sortedTags.take(5).map((e) => e.key).toList();

    // 生成默认标题（日期范围）
    final start = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    if (start.month == end.month && start.day == end.day) {
      event.title = '${start.month}月${start.day}日';
    } else {
      event.title = '${start.month}月${start.day}日 - ${end.month}月${end.day}日';
    }

    return event;
  }
}
