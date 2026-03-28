import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';

import '../../models/ai_theme.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/event.dart';
import '../../models/story_length.dart';
import '../../models/story_theme_selection.dart';
import '../../models/vo/photo.dart';
import '../../service/photo/photo_service.dart';
import '../../service/story/story_service.dart';
import '../../service/story/story_theme_preference_service.dart';
import '../widgets/movie_poster_stack.dart';
import '../widgets/primary_button.dart';
import 'story_result_page.dart';

class ThemeSelectionPage extends StatefulWidget {
  const ThemeSelectionPage({
    super.key,
    required this.event,
    required this.selectedPhotos,
  });

  final Event event;
  final List<Photo> selectedPhotos;

  @override
  State<ThemeSelectionPage> createState() => _ThemeSelectionPageState();
}

class _ThemeSelectionPageState extends State<ThemeSelectionPage> {
  final StoryThemePreferenceService _preferenceService =
      StoryThemePreferenceService();

  late final List<_ThemeOption> _options;
  int _selectedIndex = 0;
  StoryThemeTone _selectedTone = StoryThemeTone.warm;
  StoryLength _selectedLength = StoryLength.medium;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _options = _buildOptions();
    _restorePreference();
  }

  Future<void> _restorePreference() async {
    final latest = await _preferenceService.loadLatestSelection();
    if (!mounted || latest == null) {
      return;
    }

    final matchedIndex = _options.indexWhere((option) {
      return option.selection.normalizedThemeTitle ==
          latest.normalizedThemeTitle;
    });

    setState(() {
      if (matchedIndex >= 0) {
        _selectedIndex = matchedIndex;
      }
      _selectedTone = latest.tone;
    });
  }

  List<_ThemeOption> _buildOptions() {
    final aiThemes = widget.event.aiThemes;
    final options = <_ThemeOption>[];

    for (var i = 0; i < aiThemes.length; i++) {
      final theme = aiThemes[i];
      options.add(
        _ThemeOption.fromAiTheme(
          theme: theme,
          style: _themeStyles[i % _themeStyles.length],
        ),
      );
    }

    if (options.isEmpty) {
      options.addAll(_fallbackThemeOptions());
    } else {
      options.addAll(_fallbackThemeOptions().take(2));
    }

    return options;
  }

  List<_ThemeOption> _fallbackThemeOptions() {
    return [
      _ThemeOption(
        selection: const StoryThemeSelection(
          themeTitle: '温馨家庭',
          subtitle: '柔和、亲密、日常',
          source: StoryThemeSource.custom,
        ),
        description: '柔和、亲密、日常',
        style: _themeStyles[0],
      ),
      _ThemeOption(
        selection: const StoryThemeSelection(
          themeTitle: '冒险之旅',
          subtitle: '兴奋、探索、动态',
          source: StoryThemeSource.custom,
        ),
        description: '兴奋、探索、动态',
        style: _themeStyles[1],
      ),
      _ThemeOption(
        selection: const StoryThemeSelection(
          themeTitle: '浪漫秋意',
          subtitle: '温柔、安静、电影感',
          source: StoryThemeSource.custom,
        ),
        description: '温柔、安静、电影感',
        style: _themeStyles[2],
      ),
    ];
  }

  Future<void> _selectTheme(int index) async {
    await HapticFeedback.lightImpact();
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _generateStory() async {
    if (_isGenerating) {
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    final selectedOption = _options[_selectedIndex];
    final selection = selectedOption.selection.copyWith(tone: _selectedTone);

    try {
      final isar = PhotoService().isar;
      final eventEntityId = int.parse(widget.event.id);
      final eventEntity = await isar.collection<EventEntity>().get(
        eventEntityId,
      );
      if (eventEntity == null) {
        throw Exception('Event not found');
      }

      final selectedAssetIds = widget.selectedPhotos
          .map((photo) => photo.id)
          .toList();
      final photoEntities = await isar
          .collection<PhotoEntity>()
          .filter()
          .anyOf(selectedAssetIds, (q, assetId) => q.assetIdEqualTo(assetId))
          .sortByTimestamp()
          .findAll();

      if (photoEntities.isEmpty) {
        throw Exception('No photos found');
      }

      final story = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        selection: selection,
        length: _selectedLength,
      );

      if (story == null) {
        throw Exception('故事生成失败');
      }

      await _preferenceService.saveLatestSelection(selection);

      if (!mounted) {
        return;
      }

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StoryResultPage.fromStoryEntity(
            storyEntity: story,
            photos: photoEntities,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成异常: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(pinned: true, title: Text('选择故事主题')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                '围绕这 ${widget.selectedPhotos.length} 张照片，选择一个更有情绪的讲述方式。',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: _options.length,
              itemBuilder: (context, index) {
                final option = _options[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: MoviePosterStack(
                      title: option.selection.normalizedThemeTitle,
                      subtitle: option.description,
                      topBadge: index == _selectedIndex ? '已选择' : option.badge,
                      metaLine: option.selection.normalizedSubtitle,
                      background: _ThemeBackdrop(style: option.style),
                      isSelected: index == _selectedIndex,
                      onTap: () => _selectTheme(index),
                    ),
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ThemeSettingsSection(
                selectedTone: _selectedTone,
                selectedLength: _selectedLength,
                onToneChanged: (tone) => setState(() => _selectedTone = tone),
                onLengthChanged: (length) =>
                    setState(() => _selectedLength = length),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PrimaryButton(
            text: _isGenerating ? '生成中' : 'AI 生成故事',
            icon: _isGenerating ? null : Icons.auto_awesome_rounded,
            onPressed: _generateStory,
          ),
        ),
      ),
    );
  }
}

class _ThemeSettingsSection extends StatelessWidget {
  const _ThemeSettingsSection({
    required this.selectedTone,
    required this.selectedLength,
    required this.onToneChanged,
    required this.onLengthChanged,
  });

  final StoryThemeTone selectedTone;
  final StoryLength selectedLength;
  final ValueChanged<StoryThemeTone> onToneChanged;
  final ValueChanged<StoryLength> onLengthChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '叙述语气',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: StoryThemeTone.values.map((tone) {
            return ChoiceChip(
              label: Text(tone.label),
              side: BorderSide.none,
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFFDDEBFF),
              selected: selectedTone == tone,
              onSelected: (_) => onToneChanged(tone),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        Text(
          '篇幅',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SegmentedButton<StoryLength>(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF007AFF);
              }
              return Colors.white;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? Colors.white
                  : Colors.black87;
            }),
            side: const WidgetStatePropertyAll(BorderSide.none),
          ),
          segments: const [
            ButtonSegment(value: StoryLength.short, label: Text('短篇')),
            ButtonSegment(value: StoryLength.medium, label: Text('中篇')),
          ],
          selected: {selectedLength},
          onSelectionChanged: (selection) => onLengthChanged(selection.first),
        ),
      ],
    );
  }
}

class _ThemeBackdrop extends StatelessWidget {
  const _ThemeBackdrop({required this.style});

  final _ThemeStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -22,
            child: Icon(
              style.icon,
              size: 150,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            top: -30,
            left: -10,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption {
  const _ThemeOption({
    required this.selection,
    required this.description,
    required this.style,
    this.badge = '故事主题',
  });

  factory _ThemeOption.fromAiTheme({
    required AITheme theme,
    required _ThemeStyle style,
  }) {
    return _ThemeOption(
      selection: StoryThemeSelection.fromAITheme(theme),
      description: theme.subtitle,
      style: style,
      badge: theme.emoji,
    );
  }

  final StoryThemeSelection selection;
  final String description;
  final _ThemeStyle style;
  final String badge;
}

class _ThemeStyle {
  const _ThemeStyle({required this.colors, required this.icon});

  final List<Color> colors;
  final IconData icon;
}

const _themeStyles = [
  _ThemeStyle(
    colors: [Color(0xFF5956D6), Color(0xFF1C1C1E)],
    icon: Icons.nightlight_round,
  ),
  _ThemeStyle(
    colors: [Color(0xFFFF9F0A), Color(0xFF4B2D12)],
    icon: Icons.hiking_rounded,
  ),
  _ThemeStyle(
    colors: [Color(0xFF30B0C7), Color(0xFF123A49)],
    icon: Icons.waves_rounded,
  ),
  _ThemeStyle(
    colors: [Color(0xFFFF375F), Color(0xFF521A28)],
    icon: Icons.favorite_rounded,
  ),
];
