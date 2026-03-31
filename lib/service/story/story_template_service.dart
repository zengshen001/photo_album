import 'package:isar/isar.dart';

import '../../models/entity/story_template_entity.dart';
import '../photo/photo_service.dart';

/// 故事模版服务 - 管理故事模版的增删改查
class StoryTemplateService {
  static final StoryTemplateService _instance = StoryTemplateService._internal();
  factory StoryTemplateService() => _instance;
  StoryTemplateService._internal();

  /// 📝 创建故事模版
  Future<StoryTemplateEntity> createTemplate({
    required String title,
    required String subtitle,
    required String description,
    required String content,
    String? contentJson,
    String? thumbnailPhotoId,
    bool isSystemTemplate = false,
  }) async {
    final template = StoryTemplateEntity.create(
      title: title,
      subtitle: subtitle,
      description: description,
      content: content,
      contentJson: contentJson,
      thumbnailPhotoId: thumbnailPhotoId,
      isSystemTemplate: isSystemTemplate,
    );

    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      await isar.collection<StoryTemplateEntity>().put(template);
    });

    print("✅ 故事模版创建成功：ID=${template.id}");
    return template;
  }

  /// 🔍 获取所有故事模版
  Future<List<StoryTemplateEntity>> getAllTemplates() async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryTemplateEntity>()
        .where()
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 🔍 根据ID获取故事模版
  Future<StoryTemplateEntity?> getTemplateById(int id) async {
    final isar = PhotoService().isar;
    return await isar.collection<StoryTemplateEntity>().get(id);
  }

  /// 📝 更新故事模版
  Future<bool> updateTemplate(StoryTemplateEntity template) async {
    final isar = PhotoService().isar;
    template.updatedAt = DateTime.now().millisecondsSinceEpoch;

    try {
      await isar.writeTxn(() async {
        await isar.collection<StoryTemplateEntity>().put(template);
      });

      print("💾 故事模版已更新：ID=${template.id}");
      return true;
    } catch (e) {
      print("❌ 故事模版更新失败：$e");
      return false;
    }
  }

  /// 🗑️ 删除故事模版
  Future<bool> deleteTemplate(int id) async {
    final isar = PhotoService().isar;

    try {
      await isar.writeTxn(() async {
        await isar.collection<StoryTemplateEntity>().delete(id);
      });

      print("🗑️ 故事模版已删除：ID=$id");
      return true;
    } catch (e) {
      print("❌ 故事模版删除失败：$e");
      return false;
    }
  }

  /// 🔍 获取系统模版
  Future<List<StoryTemplateEntity>> getSystemTemplates() async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryTemplateEntity>()
        .filter()
        .isSystemTemplateEqualTo(true)
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 🔍 获取用户自定义模版
  Future<List<StoryTemplateEntity>> getUserTemplates() async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryTemplateEntity>()
        .filter()
        .isSystemTemplateEqualTo(false)
        .sortByCreatedAtDesc()
        .findAll();
  }
}
