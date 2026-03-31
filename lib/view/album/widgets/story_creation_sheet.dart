import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../../models/entity/event_entity.dart';
import '../../../models/entity/photo_entity.dart';
import '../../../models/event.dart';
import '../../../models/story_length.dart';
import '../../../models/story_theme_selection.dart';
import '../../../models/vo/photo.dart';
import '../../../service/photo/photo_service.dart';
import '../../../service/story/story_service.dart';
import '../../widgets/ai_backdrop.dart';
import '../../story/story_editor_page.dart';
import '../../story/story_templates_page.dart';

class StoryCreationSheet extends StatefulWidget {
  final Event event;
  final List<Photo> selectedPhotos;

  const StoryCreationSheet({
    super.key,
    required this.event,
    required this.selectedPhotos,
  });

  @override
  State<StoryCreationSheet> createState() => _StoryCreationSheetState();
}

class _StoryCreationSheetState extends State<StoryCreationSheet> {
  final _controller = TextEditingController();
  bool _isGenerating = false;
  int? _selectedTemplateId;

  void _generateStory({StoryThemeSelection? themeSelection}) async {
    final text = _controller.text.trim();
    if (text.isEmpty && themeSelection == null) return;

    setState(() => _isGenerating = true);

    try {
      final isar = PhotoService().isar;
      final eventId = int.parse(widget.event.id);
      final eventEntity = await isar.collection<EventEntity>().get(eventId);

      if (eventEntity == null) throw Exception('Event not found');

      final assetIds = widget.selectedPhotos.map((p) => p.id).toList();
      final photoEntities = await isar
          .collection<PhotoEntity>()
          .filter()
          .anyOf(assetIds, (q, id) => q.assetIdEqualTo(id))
          .findAll();

      final selection =
          themeSelection ??
          StoryThemeSelection(
            themeTitle: text,
            subtitle: '一段值得回味的故事',
            source: StoryThemeSource.custom,
          );

      final storyEntity = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        selection: selection,
        length: StoryLength.medium,
        templateId: _selectedTemplateId,
      );

      if (!mounted) return;

      if (storyEntity != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => StoryEditorPage(story: storyEntity),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('故事生成失败，请重试')));
        setState(() => _isGenerating = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('错误：$e')));
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safePadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDFEFF), Color(0xFFF3F9FF)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      // 固定最大高度，超出时内容可滚动
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽条（固定不滚动）
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // 可滚动内容区
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                bottomInset > 0 ? bottomInset + 16 : safePadding + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AIPanel(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(
                          '为故事命名',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '已选择 ${widget.selectedPhotos.length} 张照片',
                          style: TextStyle(color: Colors.grey[700]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  if (widget.event.aiThemes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'AI 推荐主题',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.event.aiThemes.map((theme) {
                        return ActionChip(
                          label: Text('${theme.emoji} ${theme.title}'),
                          avatar: Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onPressed: () {
                            _controller.text = theme.title;
                            _generateStory(
                              themeSelection: StoryThemeSelection.fromAITheme(
                                theme,
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    autofocus: widget.event.aiThemes.isEmpty,
                    decoration: InputDecoration(
                      hintText: '或者在这里自定义主题...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD8E6FF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD8E6FF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _generateStory(),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StoryTemplatesPage(),
                        ),
                      );
                      if (result is int) {
                        setState(() {
                          _selectedTemplateId = result;
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _selectedTemplateId != null ? '已选择模版' : '选择故事模版',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _isGenerating ? null : _generateStory,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isGenerating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'AI 生成',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
