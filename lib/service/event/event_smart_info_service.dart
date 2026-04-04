import 'package:isar/isar.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../utils/concurrency/concurrency_pool.dart';
import '../../utils/event/event_festival_rules.dart';
import '../../utils/event/event_scenario_rules.dart';
import '../../utils/event/smart_title_generator.dart';
import '../ai/llm_service.dart';
import '../photo/photo_service.dart';

class EventSmartInfoService {
  final int minPhotosForDisplay;
  final int topTagLimit;
  final ConcurrencyPool pool;

  EventSmartInfoService({
    required this.minPhotosForDisplay,
    required this.topTagLimit,
    required this.pool,
  });

  Future<void> refreshEventSmartInfo({
    required Isar isar,
    required List<int> eventIds,
  }) async {
    if (eventIds.isEmpty) return;

    final uniqueEventIds = eventIds.toSet().toList();
    print("🧠 开始刷新 ${uniqueEventIds.length} 个事件的智能信息...");
    await Future.wait(
      uniqueEventIds.map(
        (eventId) => pool.withPermit(
          () => _refreshSingleEventSmartInfo(isar: isar, eventId: eventId),
          timeout: const Duration(minutes: 3),
        ),
      ),
    );
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
      final mergedTags = _mergeEventTags(
        event: event,
        scenarioTags: (stats['scenarioTags'] as List<String>?) ?? const [],
      );
      stats['scenarioTags'] = mergedTags;
      event.tags = mergedTags;
      final progress = SmartTitleGenerator.calculateProgress(
        stats['analyzedCount'] as int,
        event.photoCount,
      );
      final shouldUseLlm = progress >= 100;

      Future<void>? captionFuture;
      if (shouldUseLlm) {
        captionFuture = _maybeGenerateCaptionsForEvent(
          isar: isar,
          event: event,
          analyzedPhotos: analyzedPhotos,
        );
      }

      if (shouldUseLlm && event.isLlmGenerated) {
        // 已有 LLM 标题，只更新统计信息，避免重复生成并覆盖现有标题列表
        print("  ℹ️ 事件 $eventId 已有 LLM 标题，跳过重复生成");
        if (captionFuture != null) {
          await captionFuture;
        }
        await _normalizeStoredTitlesIfNeeded(isar: isar, event: event);
        await _applyEventStatsUpdate(
          isar: isar,
          eventId: eventId,
          stats: stats,
        );
        return;
      }

      final generatedTitles = shouldUseLlm
          ? await _generateLlmThemesWithFallback(event, stats)
          : _generateLocalThemes(event, stats, progress);

      if (captionFuture != null) {
        await captionFuture;
      }

      await _applyEventSmartInfoUpdate(
        isar: isar,
        eventId: eventId,
        stats: stats,
        progress: progress,
        generatedTitles: generatedTitles,
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

    final chunks = <List<PhotoEntity>>[];
    for (var i = 0; i < needCaption.length; i += chunkSize) {
      chunks.add(
        needCaption.sublist(
          i,
          (i + chunkSize) > needCaption.length
              ? needCaption.length
              : i + chunkSize,
        ),
      );
    }

    final results = await Future.wait(
      chunks.map(
        (chunk) => pool.withPermit(() async {
          final captions = llmService.isApiKeyConfigured
              ? await llmService.generatePhotoCaptions(event, chunk)
              : await llmService.generatePhotoCaptionsMock(event, chunk);
          return captions;
        }, timeout: const Duration(seconds: 45)),
      ),
    );

    final merged = <int, String>{};
    for (final m in results) {
      merged.addAll(m);
    }
    if (merged.isEmpty) {
      return;
    }

    var didUpdate = false;
    await isar.writeTxn(() async {
      for (final photo in needCaption) {
        final caption = merged[photo.id];
        if (caption == null || caption.trim().isEmpty) {
          continue;
        }
        final latest = await isar.collection<PhotoEntity>().get(photo.id);
        if (latest == null) {
          continue;
        }
        if (!(latest.caption?.trim().isEmpty ?? true)) {
          continue;
        }
        latest.caption = caption.trim();
        latest.captionUpdatedAt = now;
        await isar.collection<PhotoEntity>().put(latest);
        didUpdate = true;
      }
    });
    if (didUpdate) {
      PhotoService().markLocalDataChanged();
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
    required _GeneratedThemes generatedTitles,
  }) async {
    await isar.writeTxn(() async {
      final latestEvent = await isar.collection<EventEntity>().get(eventId);
      if (latestEvent == null) {
        return;
      }

      latestEvent.joyScore = stats['avgJoyScore'];
      latestEvent.avgHappyScore = stats['avgHappyScore'] as double?;
      latestEvent.avgCalmScore = stats['avgCalmScore'] as double?;
      latestEvent.avgNostalgicScore = stats['avgNostalgicScore'] as double?;
      latestEvent.avgLivelyScore = stats['avgLivelyScore'] as double?;
      latestEvent.dominantEmotion = stats['dominantEmotion'] as String?;
      latestEvent.emotionDiversity = stats['emotionDiversity'] as double?;
      latestEvent.analyzedPhotoCount = stats['analyzedCount'] as int;
      latestEvent.coverPhotoId = stats['firstPhotoId'] as int?;
      latestEvent.tags =
          (stats['scenarioTags'] as List<String>?)?.toList() ?? const [];

      if (!latestEvent.isLlmGenerated) {
        latestEvent.aiThemes = generatedTitles.titles;
        latestEvent.isLlmGenerated = generatedTitles.fromLlm;
        if (latestEvent.aiThemes != null && latestEvent.aiThemes!.isNotEmpty) {
          latestEvent.title = latestEvent.aiThemes!.first;
        }
      }

      await isar.collection<EventEntity>().put(latestEvent);
      print(
        "  ✅ 事件 $eventId 已更新：封面=${latestEvent.coverPhotoId} "
        "欢乐=${latestEvent.joyScore?.toStringAsFixed(2)} "
        "主情绪=${latestEvent.dominantEmotion ?? '-'} 进度=$progress%",
      );
    });
  }

  Future<void> _applyEventStatsUpdate({
    required Isar isar,
    required int eventId,
    required Map<String, dynamic> stats,
  }) async {
    await isar.writeTxn(() async {
      final latestEvent = await isar.collection<EventEntity>().get(eventId);
      if (latestEvent == null) {
        return;
      }

      latestEvent.joyScore = stats['avgJoyScore'];
      latestEvent.avgHappyScore = stats['avgHappyScore'] as double?;
      latestEvent.avgCalmScore = stats['avgCalmScore'] as double?;
      latestEvent.avgNostalgicScore = stats['avgNostalgicScore'] as double?;
      latestEvent.avgLivelyScore = stats['avgLivelyScore'] as double?;
      latestEvent.dominantEmotion = stats['dominantEmotion'] as String?;
      latestEvent.emotionDiversity = stats['emotionDiversity'] as double?;
      latestEvent.analyzedPhotoCount = stats['analyzedCount'] as int;
      latestEvent.coverPhotoId = stats['firstPhotoId'] as int?;
      latestEvent.tags =
          (stats['scenarioTags'] as List<String>?)?.toList() ?? const [];
      await isar.collection<EventEntity>().put(latestEvent);
    });
  }

  _GeneratedThemes _generateLocalThemes(
    EventEntity event,
    Map<String, dynamic> stats,
    int progress,
  ) {
    final titles = _normalizeTitlesForEvent(
      event,
      _generateLocalThemeCandidates(event, stats),
    );
    final title = titles.isEmpty
        ? _generateLocalTitle(event, stats)
        : titles.first;
    print("  🏠 [本地] 生成规则标题: $title (进度: $progress%)");
    return _GeneratedThemes(
      titles: titles.isEmpty ? [title] : titles,
      fromLlm: false,
    );
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
      final normalizedTitles = _normalizeTitlesForEvent(event, titles);
      if (!llmService.isApiKeyConfigured) {
        print("  ⚠️ LLM API Key 未配置，使用模拟模式");
      }
      print("  🎨 [LLM] 生成 ${normalizedTitles.length} 个创意标题");
      return _GeneratedThemes(titles: normalizedTitles, fromLlm: true);
    } catch (llmError) {
      print("  ❌ LLM 生成失败: $llmError，回退到本地规则");
      final titles = _normalizeTitlesForEvent(
        event,
        _generateLocalThemeCandidates(event, stats),
      );
      return _GeneratedThemes(
        titles: titles.isEmpty ? [_generateLocalTitle(event, stats)] : titles,
        fromLlm: false,
      );
    }
  }

  String _generateLocalTitle(EventEntity event, Map<String, dynamic> stats) {
    if (event.isFestivalEvent && event.festivalName != null) {
      return '${event.festivalName}回忆';
    }

    if (event.tags.contains('🎓 毕业季')) {
      final location = event.city ?? event.province ?? '未知地点';
      return '毕业季 · $location';
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

  List<String> _generateLocalThemeCandidates(
    EventEntity event,
    Map<String, dynamic> stats,
  ) {
    final location = event.city ?? event.province ?? '未知地点';
    final dateRange = event.dateRangeText;
    final titles = <String>[];

    if (event.isFestivalEvent && event.festivalName != null) {
      final festival = event.festivalName!;
      titles.addAll([
        '$festival回忆 · $location',
        '$location 的$festival时光',
        '$festival里的热闹瞬间',
        '$festival漫游记',
      ]);
      return _uniqueTitles(titles).take(5).toList();
    }

    if (event.tags.contains('🎓 毕业季')) {
      titles.addAll([
        '毕业季 · $location',
        '毕业季的合照时刻',
        '$location · 毕业季回忆',
        '把毕业季写成故事',
      ]);
      return _uniqueTitles(titles).take(5).toList();
    }

    final topTag = stats['topTag'] as String?;
    if (topTag != null && topTag.trim().isNotEmpty) {
      final templates = SmartTitleGenerator.getTemplatesForTag(topTag);
      if (templates != null && templates.isNotEmpty) {
        titles.addAll(
          templates
              .map((t) => t.replaceAll('{city}', location))
              .where((t) => t.trim().isNotEmpty)
              .take(4),
        );
      }
      titles.add('$topTag时光 · $location');
    }

    titles.add('$location · $dateRange');
    titles.add('${event.season}的$location');

    final unique = _uniqueTitles(titles);
    if (unique.length >= 3) {
      return unique.take(5).toList();
    }
    return unique;
  }

  Future<void> _normalizeStoredTitlesIfNeeded({
    required Isar isar,
    required EventEntity event,
  }) async {
    final currentTitles = (event.aiThemes ?? const <String>[])
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final sourceTitles = currentTitles.isEmpty ? [event.title] : currentTitles;
    final normalized = _normalizeTitlesForEvent(event, sourceTitles);
    if (normalized.isEmpty) {
      return;
    }

    final sameLength = normalized.length == currentTitles.length;
    final sameItems =
        sameLength &&
        currentTitles.asMap().entries.every(
          (entry) => normalized[entry.key] == entry.value,
        );
    final sameTitle = event.title == normalized.first;
    if (sameItems && sameTitle) {
      return;
    }

    await isar.writeTxn(() async {
      final latest = await isar.collection<EventEntity>().get(event.id);
      if (latest == null) {
        return;
      }
      latest.aiThemes = normalized;
      latest.title = normalized.first;
      await isar.collection<EventEntity>().put(latest);
    });
  }

  List<String> _normalizeTitlesForEvent(
    EventEntity event,
    List<String> titles,
  ) {
    final festivalName = event.isFestivalEvent
        ? event.festivalName?.trim()
        : null;
    final requireGraduation = _hasGraduationTag(event.tags);
    final normalized = <String>[];

    for (final raw in titles) {
      var title = raw.trim();
      if (title.isEmpty) {
        continue;
      }
      if (festivalName != null &&
          festivalName.isNotEmpty &&
          !title.contains(festivalName)) {
        title = '$festivalName · $title';
      }
      if (requireGraduation && !title.contains('毕业季')) {
        title = '毕业季 · $title';
      }
      normalized.add(title);
    }

    return _uniqueTitles(normalized);
  }

  bool _hasGraduationTag(List<String> tags) {
    return tags.any((tag) => tag.contains('毕业季'));
  }

  List<String> _uniqueTitles(List<String> input) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in input) {
      final s = item.trim();
      if (s.isEmpty) continue;
      if (seen.add(s)) {
        result.add(s);
      }
    }
    return result;
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
        'avgHappyScore': null,
        'avgCalmScore': null,
        'avgNostalgicScore': null,
        'avgLivelyScore': null,
        'dominantEmotion': null,
        'emotionDiversity': null,
        'topTag': null,
        'topTagRatio': 0.0,
        'tagCounts': <String, int>{},
        'firstPhotoId': null,
        'scenarioTags': <String>[],
      };
    }

    final analyzedCount = photos.length;
    photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final joyScores = photos
        .where((p) => p.joyScore != null)
        .map((p) => p.joyScore!)
        .toList();

    final avgJoyScore = joyScores.isNotEmpty
        ? joyScores.reduce((a, b) => a + b) / joyScores.length
        : null;
    final avgHappyScore = _averageNullable(
      photos.map((p) => p.happyScore).toList(),
    );
    final avgCalmScore = _averageNullable(
      photos.map((p) => p.calmScore).toList(),
    );
    final avgNostalgicScore = _averageNullable(
      photos.map((p) => p.nostalgicScore).toList(),
    );
    final avgLivelyScore = _averageNullable(
      photos.map((p) => p.livelyScore).toList(),
    );

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

    final dominantEmotion = _dominantEmotion(
      happy: avgHappyScore,
      calm: avgCalmScore,
      nostalgic: avgNostalgicScore,
      lively: avgLivelyScore,
    );
    final emotionDiversity = _emotionDiversity(
      happy: avgHappyScore,
      calm: avgCalmScore,
      nostalgic: avgNostalgicScore,
      lively: avgLivelyScore,
    );

    return {
      'analyzedCount': analyzedCount,
      'avgJoyScore': avgJoyScore,
      'avgHappyScore': avgHappyScore,
      'avgCalmScore': avgCalmScore,
      'avgNostalgicScore': avgNostalgicScore,
      'avgLivelyScore': avgLivelyScore,
      'dominantEmotion': dominantEmotion,
      'emotionDiversity': emotionDiversity,
      'topTag': topTag,
      'topTagRatio': topTagRatio,
      'tagCounts': tagCounts,
      'firstPhotoId': photos.first.id,
      'scenarioTags': EventScenarioRules.generateAdvancedTags(photos),
    };
  }

  List<String> _mergeEventTags({
    required EventEntity event,
    required List<String> scenarioTags,
  }) {
    return {
      ...EventFestivalRules.buildFestivalTags(
        isFestivalEvent: event.isFestivalEvent,
        festivalName: event.festivalName,
      ),
      ...scenarioTags,
    }.toList();
  }

  double? _averageNullable(List<double?> values) {
    final nonNull = values.whereType<double>().toList();
    if (nonNull.isEmpty) {
      return null;
    }
    return nonNull.reduce((a, b) => a + b) / nonNull.length;
  }

  String? _dominantEmotion({
    required double? happy,
    required double? calm,
    required double? nostalgic,
    required double? lively,
  }) {
    final entries = <MapEntry<String, double>>[
      if (happy != null) MapEntry('happy', happy),
      if (calm != null) MapEntry('calm', calm),
      if (nostalgic != null) MapEntry('nostalgic', nostalgic),
      if (lively != null) MapEntry('lively', lively),
    ];
    if (entries.isEmpty) {
      return null;
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  double? _emotionDiversity({
    required double? happy,
    required double? calm,
    required double? nostalgic,
    required double? lively,
  }) {
    final values = [
      happy,
      calm,
      nostalgic,
      lively,
    ].whereType<double>().toList();
    if (values.isEmpty) {
      return null;
    }
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) => (value - mean) * (value - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return variance.clamp(0.0, 1.0);
  }
}

class _GeneratedThemes {
  final List<String> titles;
  final bool fromLlm;

  const _GeneratedThemes({required this.titles, required this.fromLlm});
}
