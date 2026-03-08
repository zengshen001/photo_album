import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:isar/isar.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/entity/event_entity.dart';
import '../../utils/photo/ai_score_helper.dart';
import 'ai_tag_dictionary.dart';
import '../photo/photo_service.dart';
import '../event/event_service.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  // 🧠 核心方法：批量分析未处理的照片（包含人脸检测和情感分析）
  Future<void> analyzePhotosInBackground({int batchSize = 10}) async {
    final isar = PhotoService().isar;
    final eligibleEventIds = await _loadEligibleEventIds(isar);

    if (eligibleEventIds.isEmpty) {
      print("ℹ️ 没有满足展示阈值的事件，跳过 AI 分析");
      return;
    }

    // 2. 初始化 ML Kit 组件
    final ImageLabelerOptions labelerOptions = ImageLabelerOptions(
      confidenceThreshold: 0.6, // 置信度 > 0.6 才要
    );
    final imageLabeler = ImageLabeler(options: labelerOptions);

    // 🎭 初始化人脸检测器（启用分类以获取 smilingProbability）
    final FaceDetectorOptions faceOptions = FaceDetectorOptions(
      enableClassification: true, // 关键：启用微笑分类
      enableTracking: false,
    );
    final faceDetector = FaceDetector(options: faceOptions);

    var totalAnalyzed = 0;
    final affectedEventIds = <int>{};

    while (true) {
      final photos = await _loadPendingPhotos(
        isar: isar,
        eligibleEventIds: eligibleEventIds,
        batchSize: batchSize,
      );

      if (photos.isEmpty) {
        break;
      }

      print("🤖 开始 AI 视觉分析（含情感分析），本批次: ${photos.length} 张");

      for (final photo in photos) {
        final result = await _analyzeSinglePhoto(
          photo: photo,
          imageLabeler: imageLabeler,
          faceDetector: faceDetector,
          isar: isar,
        );
        _collectAffectedEventId(affectedEventIds, result.eventId);

        totalAnalyzed++;

        // ⏳ 休息一下，防止 UI 掉帧 (AI 运算很吃 CPU)
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    // 6. 关闭资源
    imageLabeler.close();
    faceDetector.close();

    // 🔔 批量通知 EventService 刷新智能信息
    if (affectedEventIds.isNotEmpty) {
      print("🔔 通知 EventService 刷新 ${affectedEventIds.length} 个事件");
      await EventService().refreshEventSmartInfo(affectedEventIds.toList());
    }

    print("✅ 所有照片 AI 分析完成，总计处理: $totalAnalyzed 张");
  }

  Future<Set<int>> _loadEligibleEventIds(Isar isar) async {
    final visibleEvents = await isar
        .collection<EventEntity>()
        .where()
        .findAll();
    return visibleEvents
        .where((event) => event.photoCount >= EventService.minPhotosForDisplay)
        .map((event) => event.id)
        .toSet();
  }

  Future<List<PhotoEntity>> _loadPendingPhotos({
    required Isar isar,
    required Set<int> eligibleEventIds,
    required int batchSize,
  }) async {
    final pendingPhotos = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(false)
        .limit(batchSize * 4)
        .findAll();

    return pendingPhotos
        .where(
          (photo) =>
              photo.eventId != null && eligibleEventIds.contains(photo.eventId),
        )
        .take(batchSize)
        .toList();
  }

  Future<_AiAnalysisResult> _analyzeSinglePhoto({
    required PhotoEntity photo,
    required ImageLabeler imageLabeler,
    required FaceDetector faceDetector,
    required Isar isar,
  }) async {
    final file = File(photo.path);
    if (!file.existsSync()) {
      await _markFailedAsAnalyzed(
        photoId: photo.id,
        reason: "文件不存在，跳过: ${photo.path}",
        isar: isar,
      );
      return _AiAnalysisResult(eventId: photo.eventId);
    }

    try {
      final inputImage = InputImage.fromFile(file);
      final labels = await imageLabeler.processImage(inputImage);
      final validTags = labels
          .map((label) => AITagDictionary.zhCn[label.label] ?? label.label)
          .toList();

      final faces = await faceDetector.processImage(inputImage);
      final faceCount = faces.length;
      var maxSmileProb = 0.0;
      for (final face in faces) {
        if (face.smilingProbability != null &&
            face.smilingProbability! > maxSmileProb) {
          maxSmileProb = face.smilingProbability!;
        }
      }

      final joyScore = AIScoreHelper.calculateJoyScore(
        faceCount: faceCount,
        maxSmileProb: maxSmileProb,
        tags: validTags,
      );

      await _markAsAnalyzed(
        photo.id,
        validTags,
        faceCount,
        maxSmileProb,
        joyScore,
        isar,
      );

      final fileName = photo.path.split('/').last;
      print(
        "✅ [AI] $fileName -> 标签:$validTags 人脸:$faceCount 欢乐:${joyScore.toStringAsFixed(2)}",
      );
      return _AiAnalysisResult(eventId: photo.eventId);
    } catch (e) {
      await _markFailedAsAnalyzed(
        photoId: photo.id,
        reason: "AI 分析失败: $e",
        isar: isar,
      );
      return _AiAnalysisResult(eventId: photo.eventId);
    }
  }

  /// 失败兜底策略：将照片标记为已分析，避免后续批处理无限重试同一张失败照片。
  Future<void> _markFailedAsAnalyzed({
    required Id photoId,
    required String reason,
    required Isar isar,
  }) async {
    print("❌ $reason");
    await _markAsAnalyzed(photoId, [], 0, 0.0, 0.0, isar);
  }

  void _collectAffectedEventId(Set<int> affectedEventIds, int? eventId) {
    if (eventId != null) {
      affectedEventIds.add(eventId);
    }
  }

  // 将 AI 分析结果写入数据库（增强版）
  Future<void> _markAsAnalyzed(
    Id id,
    List<String> tags,
    int faceCount,
    double smileProb,
    double joyScore,
    Isar isar,
  ) async {
    await isar.writeTxn(() async {
      final p = await isar.collection<PhotoEntity>().get(id);
      if (p != null) {
        p.aiTags = tags;
        p.isAiAnalyzed = true;
        p.faceCount = faceCount;
        p.smileProb = smileProb;
        p.joyScore = joyScore;
        await isar.collection<PhotoEntity>().put(p);
      }
    });
  }

  // 📊 工具方法：获取 AI 分析进度
  Future<Map<String, int>> getAnalysisProgress() async {
    final isar = PhotoService().isar;

    final total = await isar.collection<PhotoEntity>().count();
    final analyzed = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .count();

    return {'total': total, 'analyzed': analyzed, 'pending': total - analyzed};
  }
}

class _AiAnalysisResult {
  final int? eventId;
  const _AiAnalysisResult({required this.eventId});
}
