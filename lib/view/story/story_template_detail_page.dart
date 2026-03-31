import 'package:flutter/material.dart';
import '../../../models/entity/story_template_entity.dart';

class StoryTemplateDetailPage extends StatelessWidget {
  final StoryTemplateEntity template;

  const StoryTemplateDetailPage({super.key, required this.template});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(template.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      template.subtitle,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      template.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Chip(
                          label: Text(
                            template.isSystemTemplate ? '系统模版' : '自定义模版',
                            style: TextStyle(
                              color: template.isSystemTemplate
                                  ? Colors.blue
                                  : Colors.grey,
                            ),
                          ),
                          backgroundColor: template.isSystemTemplate
                              ? Colors.blue.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '创建于 ${template.createdAtText}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '模版内容',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(template.content),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
