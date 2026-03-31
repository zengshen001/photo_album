import 'package:isar/isar.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../utils/event/smart_title_generator.dart';
import '../ai/llm_service.dart';

class EventSmartInfoService {
  final int minPhotosForDisplay;
  final int topTagLimit;

  const EventSmartInfoService({
    required this.minPhotosForDisplay,
    required this.topTagLimit,
  });

  Future<void> refreshEventSmartInfo({
    required Isar isar,
    required List<int> eventIds,
  }) async {
    if (eventIds.isEmpty) return;

    final uniqueEventIds = eventIds.toSet().toList();
    print("🧠 开始刷新 ${uniqueEventIds.length} 个事件的智能信息...");
    for (final eventId in uniqueEventIds) {
      await _refreshSingleEventSmartInfo(isar: isar, eventId: eventId);
    }
    print("🎉 智能信息刷新完成");
  }

  Future<void> _refreshSingleEventSmartInfo({
    required Isar isar,
    required int eventId,
  }) async {
    try {
      final event = await isar.collection<EventEntity>().get(eventId);
      if (event == null) {
        return;
      }
      if (!_isEventVisible(event)) {
        print("  ℹ️ 事件 $eventId 照片数(${event.photoCount})低于展示阈值，跳过智能信息刷新");
        return;
      }

      final analyzedPhotos = await _loadAnalyzedPhotosForEvent(
        isar: isar,
        eventId: eventId,
      );
      if (analyzedPhotos.isEmpty) {
        print("  ⚠️ 事件 $eventId 暂无已分析照片，跳过");
        return;
      }

      final stats = _calculateEventStats(analyzedPhotos);
      final progress = SmartTitleGenerator.calculateProgress(
        stats['analyzedCount'] as int,
        event.photoCount,
      );
      final shouldUseLlm = progress >= 100;

      // 生成 caption（仅在 AI 分析结束后生成）
      if (shouldUseLlm) {
        await _maybeGenerateCaptionsForEvent(
          isar: isar,
          event: event,
          analyzedPhotos: analyzedPhotos,
        );
      }

      if (shouldUseLlm && event.isLlmGenerated) {
        // 已有 LLM 标题，只更新统计信息，跳过 LLM 标题生成
        print("  ℹ️ 事件 $eventId 已有 LLM 标题，跳过重复生成");
        await _applyEventSmartInfoUpdate(
          isar: isar,
          eventId: eventId,
          stats: stats,
          progress: progress,
          shouldUseLlm: false, // 传递 false 避免重复生成 LLM 标题
        );
        return;
      }

      await _applyEventSmartInfoUpdate(
        isar: isar,
        eventId: eventId,
        stats: stats,
        progress: progress,
        shouldUseLlm: shouldUseLlm,
      );
    } catch (e) {
      print("  ❌ 刷新事件 $eventId 失败: $e");
    }
  }

  Future<void> _maybeGenerateCaptionsForEvent({
    required Isar isar,
    required EventEntity event,
    required List<PhotoEntity> analyzedPhotos,
  }) async {
    final needCaption = analyzedPhotos
        .where((p) => (p.caption?.trim().isEmpty ?? true))
        .toList();
    if (needCaption.isEmpty) {
      return;
    }

    final llmService = LLMService();
    final now = DateTime.now().millisecondsSinceEpoch;
    const chunkSize = 20;
    for (var i = 0; i < needCaption.length; i += chunkSize) {
      final chunk = needCaption.sublist(
        i,
        (i + chunkSize) > needCaption.length
            ? needCaption.length
            : i + chunkSize,
      );

      final captions = llmService.isApiKeyConfigured
          ? await llmService.generatePhotoCaptions(event, chunk)
          : await llmService.generatePhotoCaptionsMock(event, chunk);

      if (captions.isEmpty) {
        continue;
      }

      await isar.writeTxn(() async {
        for (final photo in chunk) {
          final caption = captions[photo.id];
          if (caption == null || caption.trim().isEmpty) {
            continue;
          }
          photo.caption = caption.trim();
          photo.captionUpdatedAt = now;
          await isar.collection<PhotoEntity>().put(photo);
        }
      });
    }
  }

  bool _isEventVisible(EventEntity event) {
    return event.photoCount >= minPhotosForDisplay;
  }

  Future<List<PhotoEntity>> _loadAnalyzedPhotosForEvent({
    required Isar isar,
    required int eventId,
  }) {
    return isar
        .collection<PhotoEntity>()
        .filter()
        .eventIdEqualTo(eventId)
        .isAiAnalyzedEqualTo(true)
        .findAll();
  }

  Future<void> _applyEventSmartInfoUpdate({
    required Isar isar,
    required int eventId,
    required Map<String, dynamic> stats,
    required int progress,
    required bool shouldUseLlm,
  }) async {
    await isar.writeTxn(() async {
      final latestEvent = await isar.collection<EventEntity>().get(eventId);
      if (latestEvent == null) {
        return;
      }

      latestEvent.joyScore = stats['avgJoyScore'];
      latestEvent.analyzedPhotoCount = stats['analyzedCount'] as int;
      latestEvent.coverPhotoId = stats['bestPhotoId'] as int?;
      latestEvent.tags = _extractTopTags(stats, topTagLimit);

      final generatedTitles = shouldUseLlm
          ? await _generateLlmThemesWithFallback(latestEvent, stats)
          : _generateLocalThemes(latestEvent, stats, progress);

      latestEvent.aiThemes = generatedTitles.titles;
      latestEvent.isLlmGenerated = generatedTitles.fromLlm;
      if (latestEvent.aiThemes != null && latestEvent.aiThemes!.isNotEmpty) {
        latestEvent.title = latestEvent.aiThemes!.first;
      }

      await isar.collection<EventEntity>().put(latestEvent);
      print(
        "  ✅ 事件 $eventId 已更新：封面=${latestEvent.coverPhotoId} "
        "欢乐=${latestEvent.joyScore?.toStringAsFixed(2)} 进度=$progress%",
      );
    });
  }

  _GeneratedThemes _generateLocalThemes(
    EventEntity event,
    Map<String, dynamic> stats,
    int progress,
  ) {
    final title = _generateLocalTitle(event, stats);
    print("  🏠 [本地] 生成规则标题: $title (进度: $progress%)");
    return _GeneratedThemes(titles: [title], fromLlm: false);
  }

  Future<_GeneratedThemes> _generateLlmThemesWithFallback(
    EventEntity event,
    Map<String, dynamic> stats,
  ) async {
    final topTags = _extractTopTags(stats, topTagLimit);
    final llmService = LLMService();

    try {
      final titles = llmService.isApiKeyConfigured
          ? await llmService.generateCreativeTitles(event, topTags)
          : await llmService.generateCreativeTitlesMock(event, topTags);
      if (!llmService.isApiKeyConfigured) {
        print("  ⚠️ LLM API Key 未配置，使用模拟模式");
      }
      print("  🎨 [LLM] 生成 ${titles.length} 个创意标题");
      return _GeneratedThemes(titles: titles, fromLlm: true);
    } catch (llmError) {
      print("  ❌ LLM 生成失败: $llmError，回退到本地规则");
      return _GeneratedThemes(
        titles: [_generateLocalTitle(event, stats)],
        fromLlm: false,
      );
    }
  }

  String _generateLocalTitle(EventEntity event, Map<String, dynamic> stats) {
    if (event.isFestivalEvent && event.festivalName != null) {
      return '${event.festivalName}回忆';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final topTag = stats['topTag'] as String?;
    final joyScore = stats['avgJoyScore'] as double?;

    return SmartTitleGenerator.generate(
      date: date,
      city: event.city,
      province: event.province,
      topTag: topTag,
      joyScore: joyScore,
    );
  }

  List<String> _extractTopTags(Map<String, dynamic> stats, int count) {
    final tagCounts = stats['tagCounts'] as Map<String, int>?;
    if (tagCounts == null || tagCounts.isEmpty) return [];

    final sortedTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedTags.take(count).map((e) => e.key).toList();
  }

  Map<String, dynamic> _calculateEventStats(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      return {
        'analyzedCount': 0,
        'avgJoyScore': null,
        'topTag': null,
        'topTagRatio': 0.0,
        'tagCounts': <String, int>{},
        'bestPhotoId': null,
      };
    }

    final analyzedCount = photos.length;
    final joyScores = photos
        .where((p) => p.joyScore != null)
        .map((p) => p.joyScore!)
        .toList();

    final avgJoyScore = joyScores.isNotEmpty
        ? joyScores.reduce((a, b) => a + b) / joyScores.length
        : null;

    final Map<String, int> tagCounts = {};
    for (final photo in photos) {
      if (photo.aiTags != null) {
        for (final tag in photo.aiTags!) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }

    String? topTag;
    double topTagRatio = 0.0;
    if (tagCounts.isNotEmpty) {
      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topTag = sortedTags.first.key;
      topTagRatio = sortedTags.first.value / analyzedCount;
    }

    int? bestPhotoId;
    double maxJoy = 0.0;
    for (final photo in photos) {
      if (photo.joyScore != null && photo.joyScore! > maxJoy) {
        maxJoy = photo.joyScore!;
        bestPhotoId = photo.id;
      }
    }

    return {
      'analyzedCount': analyzedCount,
      'avgJoyScore': avgJoyScore,
      'topTag': topTag,
      'topTagRatio': topTagRatio,
      'tagCounts': tagCounts,
      'bestPhotoId': bestPhotoId,
    };
  }
}

class _GeneratedThemes {
  final List<String> titles;
  final bool fromLlm;

  const _GeneratedThemes({required this.titles, required this.fromLlm});
}
