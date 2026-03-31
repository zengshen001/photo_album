import 'package:flutter/material.dart';
import '../../../service/story/story_template_service.dart';
import '../../../models/entity/story_template_entity.dart';

class StoryTemplateEditPage extends StatefulWidget {
  final StoryTemplateEntity? template;

  const StoryTemplateEditPage({super.key, this.template});

  @override
  State<StoryTemplateEditPage> createState() => _StoryTemplateEditPageState();
}

class _StoryTemplateEditPageState extends State<StoryTemplateEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contentController = TextEditingController();
  final _templateService = StoryTemplateService();
  bool _isSystemTemplate = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.template != null) {
      _titleController.text = widget.template!.title;
      _subtitleController.text = widget.template!.subtitle;
      _descriptionController.text = widget.template!.description;
      _contentController.text = widget.template!.content;
      _isSystemTemplate = widget.template!.isSystemTemplate;
    }
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (widget.template != null) {
        // 更新现有模版
        final updatedTemplate = widget.template!.copyWith(
          title: _titleController.text.trim(),
          subtitle: _subtitleController.text.trim(),
          description: _descriptionController.text.trim(),
          content: _contentController.text.trim(),
          isSystemTemplate: _isSystemTemplate,
        );
        await _templateService.updateTemplate(updatedTemplate);
      } else {
        // 创建新模版
        await _templateService.createTemplate(
          title: _titleController.text.trim(),
          subtitle: _subtitleController.text.trim(),
          description: _descriptionController.text.trim(),
          content: _contentController.text.trim(),
          isSystemTemplate: _isSystemTemplate,
        );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template != null ? '编辑故事模版' : '创建故事模版'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveTemplate,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '模版标题',
                  hintText: '请输入模版标题',
                ),
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return '请输入模版标题';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subtitleController,
                decoration: const InputDecoration(
                  labelText: '副标题',
                  hintText: '请输入副标题',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: '模版描述',
                  hintText: '请输入模版描述',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '模版内容',
                  hintText: '请输入模版内容（Markdown格式）',
                  alignLabelWithHint: true,
                ),
                maxLines: 10,
                validator: (value) {
                  if (value?.trim().isEmpty ?? true) {
                    return '请输入模版内容';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('系统模版'),
                value: _isSystemTemplate,
                onChanged: (value) {
                  setState(() => _isSystemTemplate = value);
                },
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _saveTemplate,
                  child: const Text('保存'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
