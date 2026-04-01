import '../../models/entity/photo_entity.dart';

class EventScenarioRules {
  /// 根据事件中的照片集合，严格推导高级场景标签
  static List<String> generateAdvancedTags(List<PhotoEntity> photos) {
    if (photos.isEmpty) return [];

    Set<String> allTags = {};
    int totalFaces = 0;
    double totalSmileProb = 0.0;
    int photosWithFaces = 0;
    int graduationSeasonCount = 0;

    // 1. 聚合底层特征数据 (去重)
    for (var photo in photos) {
      final month = DateTime.fromMillisecondsSinceEpoch(photo.timestamp).month;
      if (month == 6 || month == 7) {
        graduationSeasonCount++;
      }
      if (photo.aiTags != null) {
        allTags.addAll(photo.aiTags!); // 收集该事件中出现过的所有基础标签
      }
      totalFaces += photo.faceCount;
      if (photo.faceCount > 0) {
        totalSmileProb += photo.smileProb;
        photosWithFaces++;
      }
    }

    // 计算有脸照片的平均微笑概率
    double avgSmile = photosWithFaces == 0
        ? 0.0
        : totalSmileProb / photosWithFaces;
    Set<String> advancedTags = {};

    // ==========================================
    // 核心组合规则引擎 (基于严格的 AND/OR 逻辑)
    // ==========================================

    // 1. 社交与情感类 (严格的人脸与笑容阈值)
    if (totalFaces >= 3 && avgSmile >= 0.6) {
      advancedTags.add("🎉 欢乐聚会");
    } else if (totalFaces == 2 && avgSmile >= 0.6) {
      advancedTags.add("👩❤️👨 双人时光");
    }

    if (totalFaces >= 4 && !advancedTags.contains("🎉 欢乐聚会")) {
      advancedTags.add("📷 大合照");
    }

    final graduationSeasonRatio = graduationSeasonCount / photos.length;
    if (graduationSeasonRatio >= 0.6 && totalFaces > 10) {
      advancedTags.add("🎓 毕业季");
    }

    // 亲子时刻：必须有人脸，且出现儿童相关标签
    if (totalFaces > 0 && _containsAny(allTags, ['儿童', '婴儿'])) {
      advancedTags.add("👶 亲子时刻");
    }

    // 2. 场景组合类 (严谨的多元特征交叉校验，防止误判)

    // ⛰️ 拥抱自然：必须同时出现至少 2 个自然类特征 (防止因为背景有一棵树就被判为自然)
    final natureKeywords = [
      '山',
      '山丘',
      '森林',
      '树木',
      '草地',
      '自然',
      '风景',
      '植物',
      '田野',
    ];
    if (_matchCount(allTags, natureKeywords) >= 2) {
      advancedTags.add("⛰️ 拥抱自然");
    }

    // 🏖️ 海滨假日：明确的"海滩" 或者 "大海/海洋"+"沙地/天空/水"的组合
    if (allTags.contains('海滩') ||
        (_containsAny(allTags, ['大海', '海洋']) &&
            _containsAny(allTags, ['沙地', '天空', '水']))) {
      advancedTags.add("🏖️ 海滨假日");
    }

    // 🍱 美食探店：必须在特定环境下，且识别出具体的"食物"
    final foodKeywords = [
      '美食',
      '菜肴',
      '甜点',
      '蛋糕',
      '咖啡',
      '冰淇淋',
      '海鲜',
      '肉类',
      '面条',
      '米饭',
      '饮料',
    ];
    if (_containsAny(allTags, ['餐厅', '室内', '桌子', '食物']) &&
        _containsAny(allTags, foodKeywords)) {
      advancedTags.add("🍱 美食探店");
    }

    // 🏙️ 城市漫步：必须有"城市"概念，且配合具体的城建设施
    final urbanFacilities = ['建筑物', '街道', '摩天楼', '建筑', '塔', '道路', '路灯'];
    if (allTags.contains('城市') && _containsAny(allTags, urbanFacilities)) {
      advancedTags.add("🏙️ 城市漫步");
    }

    // 🐾 萌宠当家：只要出现宠物类即命中
    if (_containsAny(allTags, ['猫', '狗', '宠物', '动物'])) {
      advancedTags.add("🐾 萌宠当家");
    }

    // 🌙 魅力夜景：夜晚+灯光组合
    if (_containsAny(allTags, ['夜晚', '傍晚']) &&
        _containsAny(allTags, ['灯光', '路灯', '城市'])) {
      advancedTags.add("🌙 魅力夜景");
    }

    final flowerKeywords = ['花朵', '植物', '花园', '草地'];
    if (_matchCount(allTags, flowerKeywords) >= 2) {
      advancedTags.add("🌸 花海漫游");
    }

    if (_containsAny(allTags, ['博物馆'])) {
      advancedTags.add("🏛️ 博物馆之旅");
    }

    if (_containsAny(allTags, ['学校', '教室', '课堂'])) {
      advancedTags.add("🎓 校园时光");
    }

    if (_containsAny(allTags, ['商场', '商店', '市场']) &&
        _containsAny(allTags, ['城市', '街道', '室内'])) {
      advancedTags.add("🛍️ 逛街买买");
    }

    if (_containsAny(allTags, ['咖啡', '甜点', '蛋糕']) &&
        _containsAny(allTags, ['餐厅', '室内', '桌子', '商店'])) {
      advancedTags.add("☕️ 咖啡甜点");
    }

    if ((_containsAny(allTags, ['机场', '火车站', '地铁站']) ||
            _matchCount(allTags, ['飞机', '机场', '火车', '地铁']) >= 2) &&
        _containsAny(allTags, ['城市', '天空', '道路', '街道'])) {
      advancedTags.add("✈️ 旅途出发");
    }

    if (_containsAny(allTags, ['音乐会', '舞台']) &&
        _containsAny(allTags, ['人群', '夜晚', '灯光'])) {
      advancedTags.add("🎤 现场演出");
    }

    if (advancedTags.isEmpty &&
        _containsAny(allTags, ['室内', '房间', '卧室', '厨房', '沙发'])) {
      advancedTags.add("🏠 居家日常");
    }

    // 3. 兜底策略：如果没有触发任何高级规则，怎么处理？
    if (advancedTags.isEmpty && allTags.isNotEmpty) {
      // 过滤掉太泛泛的词 (如室内、白天)，挑一个有意义的词展示
      var meaningfulTags = allTags
          .where((t) => !['白天', '室内', '户外', '人像'].contains(t))
          .toList();
      if (meaningfulTags.isNotEmpty) {
        advancedTags.add("✨ 捕捉到${meaningfulTags.first}");
      } else {
        advancedTags.add("📸 生活碎片");
      }
    } else if (advancedTags.isEmpty) {
      advancedTags.add("📸 生活碎片");
    }

    // 返回排序或截取 Top 3 的高级标签
    return advancedTags.take(3).toList();
  }

  // 辅助方法 1：检查集合是否包含目标列表中的任意一项 (OR 逻辑)
  static bool _containsAny(Set<String> source, List<String> targets) {
    return targets.any((tag) => source.contains(tag));
  }

  // 辅助方法 2：计算命中了目标列表中的多少项 (用于 >= N 的严谨逻辑)
  static int _matchCount(Set<String> source, List<String> targets) {
    return targets.where((tag) => source.contains(tag)).length;
  }
}
