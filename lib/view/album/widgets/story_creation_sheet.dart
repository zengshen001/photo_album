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
import '../../story/story_editor_page.dart';

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

  void _generateStory() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

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

      final selection = StoryThemeSelection(
        themeTitle: text,
        subtitle: '一段值得回味的故事',
        source: StoryThemeSource.custom,
      );

      final storyEntity = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        selection: selection,
        length: StoryLength.medium,
      );

      if (!mounted) return;

      if (storyEntity != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => StoryEditorPage(story: storyEntity),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('故事生成失败，请重试')),
        );
        setState(() => _isGenerating = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('错误：$e')),
      );
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '为故事命名',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '已选择 ${widget.selectedPhotos.length} 张照片',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '例如：完美的海边假日...',
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              maxLines: null,
              onSubmitted: (_) => _generateStory(),
            ),
            const SizedBox(height: 24),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
