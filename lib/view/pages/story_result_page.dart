import 'package:flutter/material.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/story.dart';

class StoryResultPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;

  const StoryResultPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.sections,
  });

  // Create from generated story (Config -> Result)
  factory StoryResultPage.fromGenerated({
    required Event event,
    required List<Photo> photos,
    required String theme,
    required String subtitle,
  }) {
    final sections = [
      StorySection(
        text:
            '${event.dateRangeText}，${event.location}。'
            '这是一段$theme的美好时光。阳光洒在我们身上，微风轻拂，'
            '每一个瞬间都值得被记录和珍藏。',
        photo: photos[0],
      ),
      StorySection(
        text:
            '我们一起探索这个美丽的地方，发现了许多惊喜。'
            '笑声和欢乐充满了每一个角落，这些时刻成为了我们最珍贵的回忆。',
        photo: photos.length > 1 ? photos[1] : photos[0],
      ),
      StorySection(
        text:
            '时间总是过得很快，但这些美好的记忆会永远留在心中。'
            '期待下一次的相遇，期待更多的美好时光。',
        photo: photos.length > 2 ? photos[2] : photos[0],
      ),
    ];

    return StoryResultPage(
      title: theme,
      subtitle: subtitle,
      heroImage: photos.first,
      sections: sections,
    );
  }

  // Create from saved story (Stories list -> Result)
  factory StoryResultPage.fromStory(Story story) {
    return StoryResultPage(
      title: story.title,
      subtitle: story.subtitle,
      heroImage: story.heroImage,
      sections: story.blocks
          .where((block) => block.photo != null)
          .map((block) => StorySection(text: block.text, photo: block.photo!))
          .toList(),
    );
  }

  @override
  State<StoryResultPage> createState() => _StoryResultPageState();
}

class _StoryResultPageState extends State<StoryResultPage> {
  late List<StorySection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = List.from(widget.sections);
  }

  void _editText(int index) {
    final controller = TextEditingController(text: _sections[index].text);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑文字'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _sections[index] = StorySection(
                    text: controller.text,
                    photo: _sections[index].photo,
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  void _saveStory() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('故事已保存')));
  }

  void _shareStory() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image with title
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 3,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(widget.heroImage.path, fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Subtitle
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.subtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Story sections
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final section = _sections[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Text block
                    GestureDetector(
                      onTap: () => _editText(index),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                section.text,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.copyWith(height: 1.6),
                              ),
                            ),
                            Icon(Icons.edit, size: 16, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Photo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        section.photo.path,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ),
              );
            }, childCount: _sections.length),
          ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              icon: const Icon(Icons.close),
              label: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: _saveStory,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
            TextButton.icon(
              onPressed: _shareStory,
              icon: const Icon(Icons.share),
              label: const Text('分享'),
            ),
          ],
        ),
      ),
    );
  }
}

class StorySection {
  final String text;
  final Photo photo;

  StorySection({required this.text, required this.photo});
}
