import 'ai_theme.dart';

enum StoryThemeSource { aiRecommend, custom }

enum StoryThemeTone {
  warm('温暖'),
  humorous('幽默'),
  documentary('纪实'),
  lyrical('抒情');

  const StoryThemeTone(this.label);

  final String label;
}

class StoryThemeSelection {
  const StoryThemeSelection({
    required this.themeTitle,
    required this.subtitle,
    required this.source,
    this.themeId,
    this.tone = StoryThemeTone.warm,
  });

  final String? themeId;
  final String themeTitle;
  final String subtitle;
  final StoryThemeSource source;
  final StoryThemeTone tone;

  bool get isValid {
    final length = normalizedThemeTitle.length;
    return length >= 2 && length <= 30;
  }

  String get normalizedThemeTitle => themeTitle.trim();
  String get normalizedSubtitle => subtitle.trim();

  StoryThemeSelection copyWith({
    String? themeId,
    String? themeTitle,
    String? subtitle,
    StoryThemeSource? source,
    StoryThemeTone? tone,
    bool clearThemeId = false,
  }) {
    return StoryThemeSelection(
      themeId: clearThemeId ? null : (themeId ?? this.themeId),
      themeTitle: themeTitle ?? this.themeTitle,
      subtitle: subtitle ?? this.subtitle,
      source: source ?? this.source,
      tone: tone ?? this.tone,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeId': themeId,
      'themeTitle': themeTitle,
      'subtitle': subtitle,
      'source': source.name,
      'tone': tone.name,
    };
  }

  factory StoryThemeSelection.fromJson(Map<String, dynamic> json) {
    return StoryThemeSelection(
      themeId: json['themeId'] as String?,
      themeTitle: (json['themeTitle'] as String? ?? '').trim(),
      subtitle: (json['subtitle'] as String? ?? '').trim(),
      source: StoryThemeSource.values.byName(
        json['source'] as String? ?? StoryThemeSource.custom.name,
      ),
      tone: StoryThemeTone.values.byName(
        json['tone'] as String? ?? StoryThemeTone.warm.name,
      ),
    );
  }

  factory StoryThemeSelection.fromAITheme(
    AITheme theme, {
    StoryThemeTone tone = StoryThemeTone.warm,
  }) {
    return StoryThemeSelection(
      themeId: theme.id,
      themeTitle: theme.title,
      subtitle: theme.subtitle,
      source: StoryThemeSource.aiRecommend,
      tone: tone,
    );
  }
}
