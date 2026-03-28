import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import '../../models/story_length.dart';
import '../../models/story_theme_selection.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo/photo_service.dart';
import '../../service/story/story_service.dart';
import '../../service/story/story_theme_preference_service.dart';
import '../widgets/primary_button.dart';
import 'story_result_page.dart';

class ConfigPage extends StatefulWidget {
  final Event event;
  final List<Photo> selectedPhotos;
  final List<AITheme> recommendedThemes;

  const ConfigPage({
    super.key,
    required this.event,
    required this.selectedPhotos,
    required this.recommendedThemes,
  });

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const _fallbackSubtitles = ['难忘的回忆', '美好时光', '特别的日子'];

  final StoryThemePreferenceService _preferenceService =
      StoryThemePreferenceService();
  late TextEditingController _themeController;
  String? _selectedThemeId;
  String? _selectedSubtitle;
  StoryThemeTone _selectedTone = StoryThemeTone.warm;
  StoryLength _selectedLength = StoryLength.medium;
  bool _isGenerating = false;
  bool _isLoadingPreference = true;

  @override
  void initState() {
    super.initState();
    final initialTheme = widget.recommendedThemes.firstOrNull;
    _themeController = TextEditingController(text: initialTheme?.title ?? '');
    _selectedThemeId = initialTheme?.id;
    _selectedSubtitle = initialTheme?.subtitle;
    _loadLatestSelection();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> _loadLatestSelection() async {
    final recent = await _preferenceService.loadLatestSelection();
    if (!mounted) return;

    if (recent == null) {
      setState(() {
        _isLoadingPreference = false;
      });
      return;
    }

    final matchedTheme = recent.themeId == null
        ? null
        : widget.recommendedThemes
              .where((theme) => theme.id == recent.themeId)
              .firstOrNull;

    final nextSelection = matchedTheme != null
        ? StoryThemeSelection.fromAITheme(matchedTheme, tone: recent.tone)
        : recent;

    _applySelection(nextSelection);
    setState(() {
      _isLoadingPreference = false;
    });
  }

  void _applySelection(StoryThemeSelection selection) {
    _themeController.text = selection.normalizedThemeTitle;
    _selectedThemeId = selection.source == StoryThemeSource.aiRecommend
        ? selection.themeId
        : null;
    _selectedSubtitle = selection.normalizedSubtitle.isEmpty
        ? null
        : selection.normalizedSubtitle;
    _selectedTone = selection.tone;
  }

  StoryThemeSelection _buildSelection() {
    final themeTitle = _themeController.text.trim();
    final matchedTheme = widget.recommendedThemes
        .where((theme) => theme.id == _selectedThemeId)
        .firstOrNull;

    if (matchedTheme != null && matchedTheme.title == themeTitle) {
      return StoryThemeSelection.fromAITheme(
        matchedTheme,
        tone: _selectedTone,
      ).copyWith(subtitle: _selectedSubtitle ?? '');
    }

    return StoryThemeSelection(
      themeTitle: themeTitle,
      subtitle: _selectedSubtitle ?? '',
      source: StoryThemeSource.custom,
      tone: _selectedTone,
    );
  }

  void _selectRecommendedTheme(AITheme theme) {
    setState(() {
      _selectedThemeId = theme.id;
      _themeController.text = theme.title;
      _selectedSubtitle = theme.subtitle;
    });
  }

  void _switchToCustomTheme() {
    setState(() {
      _selectedThemeId = null;
    });
  }

  Future<void> _generateStory() async {
    final selection = _buildSelection();

    if (!selection.isValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 2 到 30 个字的故事主题')));
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      // 1. 获取 EventEntity（通过 Event.id 查询）
      final isar = PhotoService().isar;
      final eventEntityId = int.parse(widget.event.id);
      final eventEntity = await isar.collection<EventEntity>().get(
        eventEntityId,
      );

      if (eventEntity == null) {
        throw Exception('Event not found');
      }

      // 2. 严格按用户选择的照片生成故事
      final selectedAssetIds = widget.selectedPhotos
          .map((photo) => photo.id)
          .toList();
      final List<PhotoEntity> photoEntities = await isar
          .collection<PhotoEntity>()
          .filter()
          .anyOf(selectedAssetIds, (q, assetId) => q.assetIdEqualTo(assetId))
          .sortByTimestamp()
          .findAll();

      if (photoEntities.isEmpty) {
        throw Exception('No photos found');
      }

      // 3. 调用 StoryService 生成故事
      final story = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        selection: selection,
        length: _selectedLength,
      );

      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });

      if (story != null) {
        await _preferenceService.saveLatestSelection(selection);
        if (!mounted) return;
        // 4. 导航到 StoryResultPage.fromStoryEntity
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StoryResultPage.fromStoryEntity(
              storyEntity: story,
              photos: photoEntities,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('故事生成失败，请重试')));
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成异常: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('生成故事')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.event.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ConfigInfoPill(
                        icon: Icons.photo_library_outlined,
                        label: '${widget.selectedPhotos.length} 张照片',
                      ),
                      _ConfigInfoPill(
                        icon: Icons.calendar_today_outlined,
                        label: widget.event.dateRangeText,
                      ),
                      _ConfigInfoPill(
                        icon: Icons.location_on_outlined,
                        label: widget.event.location,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '已完成照片选择，接下来选择 AI 主题或输入自定义主题后生成故事。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (_isLoadingPreference)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: LinearProgressIndicator(),
            ),

          _ConfigSection(
            title: '推荐主题',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.recommendedThemes.map((theme) {
                final isSelected = theme.id == _selectedThemeId;
                return ChoiceChip(
                  showCheckmark: false,
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFDDEBFF),
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(theme.emoji),
                      const SizedBox(width: 6),
                      Text(theme.title),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (_) => _selectRecommendedTheme(theme),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          _ConfigSection(
            title: '自定义主题',
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TextField(
                controller: _themeController,
                onChanged: (_) => _switchToCustomTheme(),
                decoration: const InputDecoration(
                  hintText: '输入 2 到 30 个字的故事主题',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.auto_stories_outlined),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          _ConfigSection(
            title: '副标题 / 切入点',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  {
                    ...widget.recommendedThemes
                        .map((theme) => theme.subtitle)
                        .where((subtitle) => subtitle.trim().isNotEmpty),
                    ..._fallbackSubtitles,
                  }.map((subtitle) {
                    final isSelected = subtitle == _selectedSubtitle;
                    return ChoiceChip(
                      label: Text(subtitle),
                      side: BorderSide.none,
                      backgroundColor: Colors.white,
                      selectedColor: const Color(0xFFDDEBFF),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedSubtitle = selected ? subtitle : null;
                        });
                      },
                    );
                  }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          _ConfigSection(
            title: '写作语气',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: StoryThemeTone.values.map((subtitle) {
                final isSelected = subtitle == _selectedTone;
                return ChoiceChip(
                  label: Text(subtitle.label),
                  side: BorderSide.none,
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFDDEBFF),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTone = subtitle;
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          _ConfigSection(
            title: '篇幅选择',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<StoryLength>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return theme.colorScheme.primary;
                      }
                      return Colors.white;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white;
                      }
                      return Colors.black87;
                    }),
                    side: const WidgetStatePropertyAll(BorderSide.none),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: StoryLength.short,
                      label: Text('短篇'),
                      icon: Icon(Icons.short_text),
                    ),
                    ButtonSegment(
                      value: StoryLength.medium,
                      label: Text('中篇'),
                      icon: Icon(Icons.notes),
                    ),
                  ],
                  selected: {_selectedLength},
                  onSelectionChanged: (Set<StoryLength> newSelection) {
                    setState(() {
                      _selectedLength = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _selectedLength == StoryLength.short ? '约 150 字' : '约 300 字',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          PrimaryButton(
            text: _isGenerating ? '生成中' : '开始生成',
            icon: _isGenerating ? null : Icons.auto_stories_outlined,
            onPressed: _isGenerating || _isLoadingPreference
                ? null
                : _generateStory,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ConfigInfoPill extends StatelessWidget {
  const _ConfigInfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
