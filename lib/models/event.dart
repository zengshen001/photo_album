import 'vo/photo.dart';
import 'ai_theme.dart';

class Event {
  final String id;
  final String title;
  final String season;
  final int year;
  final String location;
  final DateTime startDate;
  final DateTime endDate;
  final List<Photo> photos;
  final List<String> tags;
  final List<AITheme> aiThemes;
  final int analyzedPhotoCount;
  final bool isFestivalEvent;
  final String? festivalName;

  Event({
    required this.id,
    required this.title,
    required this.season,
    required this.year,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.photos,
    this.tags = const [],
    this.aiThemes = const [],
    this.analyzedPhotoCount = 0,
    this.isFestivalEvent = false,
    this.festivalName,
  });

  // Get cover photos (first 3)
  List<Photo> get coverPhotos => photos.take(3).toList();

  // Get formatted date range
  String get dateRangeText {
    final start = '${startDate.month}月${startDate.day}日';
    final end = '${endDate.month}月${endDate.day}日';
    return startDate.month == endDate.month && startDate.day == endDate.day
        ? start
        : '$start - $end';
  }

  // Get the display title prioritizing AI generated themes
  String get displayTitle {
    if (aiThemes.isNotEmpty) {
      return aiThemes.first.title;
    }
    return title;
  }

  int get totalPhotoCount => photos.length;

  bool get isAiAnalysisComplete =>
      totalPhotoCount > 0 && analyzedPhotoCount >= totalPhotoCount;

  bool get isAiAnalysisInProgress =>
      analyzedPhotoCount > 0 && analyzedPhotoCount < totalPhotoCount;

  String get aiAnalysisStatusText {
    if (totalPhotoCount == 0) {
      return 'AI 待分析';
    }
    if (isAiAnalysisComplete) {
      return aiThemes.isEmpty ? 'AI 已分析完成' : 'AI 已完成';
    }
    return 'AI 分析中 $analyzedPhotoCount/$totalPhotoCount';
  }
}
