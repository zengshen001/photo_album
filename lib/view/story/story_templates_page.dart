import 'package:flutter/material.dart';
import '../../../service/story/story_template_service.dart';
import '../../../models/entity/story_template_entity.dart';
import 'story_template_edit_page.dart';

class StoryTemplatesPage extends StatefulWidget {
  const StoryTemplatesPage({super.key});

  @override
  State<StoryTemplatesPage> createState() => _StoryTemplatesPageState();
}

class _StoryTemplatesPageState extends State<StoryTemplatesPage> {
  late Future<List<StoryTemplateEntity>> _templatesFuture;
  final _templateService = StoryTemplateService();

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  void _loadTemplates() {
    setState(() {
      _templatesFuture = _templateService.getAllTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('故事模版管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StoryTemplateEditPage(),
                ),
              ).then((_) => _loadTemplates());
            },
          ),
        ],
      ),
      body: FutureBuilder<List<StoryTemplateEntity>>(
        future: _templatesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('加载失败：${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('暂无故事模版'));
          }

          final templates = snapshot.data!;
          return ListView.builder(
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final template = templates[index];
              return ListTile(
                leading: template.thumbnailPhotoId != null
                    ? const CircleAvatar(child: Icon(Icons.photo))
                    : const CircleAvatar(child: Icon(Icons.book)),
                title: Text(template.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.description),
                    Text(
                      template.isSystemTemplate ? '系统模版' : '自定义模版',
                      style: TextStyle(
                        fontSize: 12,
                        color: template.isSystemTemplate
                            ? Colors.blue
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            StoryTemplateEditPage(template: template),
                      ),
                    ).then((_) => _loadTemplates());
                  },
                ),
                onTap: () {
                  Navigator.pop(context, template.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}
