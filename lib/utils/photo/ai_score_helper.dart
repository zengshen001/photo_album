class EmotionScores {
  final double happy;
  final double calm;
  final double nostalgic;
  final double lively;

  const EmotionScores({
    required this.happy,
    required this.calm,
    required this.nostalgic,
    required this.lively,
  });

  double get compatibilityJoyScore => _clamp((happy * 0.75) + (lively * 0.25));

  String get dominantEmotion {
    final scores = {
      'happy': happy,
      'calm': calm,
      'nostalgic': nostalgic,
      'lively': lively,
    }.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return scores.first.key;
  }

  static double _clamp(double v) => v.clamp(0.0, 1.0);
}

class AIScoreHelper {
  const AIScoreHelper._();

  static const _happyTags = {
    '美食',
    '花朵',
    '宠物',
    '猫',
    '狗',
    '微笑',
    '快乐',
    '蛋糕',
    '甜点',
  };
  static const _calmTags = {
    '日落',
    '日出',
    '天空',
    '云',
    '湖',
    '河',
    '水',
    '风景',
    '自然',
    '公园',
    '花园',
    '海滩',
    '大海',
    '海洋',
    '森林',
    '夜晚',
    '傍晚',
  };
  static const _nostalgicTags = {
    '学校',
    '教室',
    '校园',
    '古城',
    '建筑',
    '桥',
    '节日',
    '家庭',
    '友情',
    '情侣',
    '婚礼',
    '人像',
  };
  static const _livelyTags = {
    '人群',
    '活动',
    '派对',
    '音乐会',
    '舞台',
    '灯光',
    '运动',
    '比赛',
    '街道',
    '城市',
    '节日',
    '快餐',
  };

  static EmotionScores calculateEmotionScores({
    required int faceCount,
    required double maxSmileProb,
    required List<String> tags,
  }) {
    final facePresenceScore = _clamp(faceCount / 4);
    final crowdScore = _clamp(faceCount / 6);
    final smileScore = _clamp(maxSmileProb);
    final lowCrowdScore = _clamp(1 - (faceCount / 5));

    final happyTagScore = _tagMatchScore(tags, _happyTags);
    final calmTagScore = _tagMatchScore(tags, _calmTags);
    final nostalgicTagScore = _tagMatchScore(tags, _nostalgicTags);
    final livelyTagScore = _tagMatchScore(tags, _livelyTags);

    final happy = _clamp(
      (smileScore * 0.45) +
          (facePresenceScore * 0.20) +
          (happyTagScore * 0.20) +
          (_socialWarmthScore(faceCount, tags) * 0.15),
    );
    final calm = _clamp(
      (calmTagScore * 0.45) +
          (lowCrowdScore * 0.20) +
          (_staticVisualScore(tags) * 0.20) +
          (_daylightMoodScore(tags) * 0.15),
    );
    final nostalgic = _clamp(
      (nostalgicTagScore * 0.40) +
          (_groupPhotoScore(faceCount, tags) * 0.20) +
          (_memorySceneScore(tags) * 0.25) +
          (_seasonalCeremonyScore(tags) * 0.15),
    );
    final lively = _clamp(
      (crowdScore * 0.30) +
          (livelyTagScore * 0.35) +
          (_movementScore(tags) * 0.20) +
          (_nightLightScore(tags) * 0.15),
    );

    return EmotionScores(
      happy: happy,
      calm: calm,
      nostalgic: nostalgic,
      lively: lively,
    );
  }

  static double calculateJoyScore({
    required int faceCount,
    required double maxSmileProb,
    required List<String> tags,
  }) {
    return calculateEmotionScores(
      faceCount: faceCount,
      maxSmileProb: maxSmileProb,
      tags: tags,
    ).compatibilityJoyScore;
  }

  static double _tagMatchScore(List<String> tags, Set<String> targetTags) {
    if (targetTags.isEmpty || tags.isEmpty) {
      return 0.0;
    }
    final matchCount = tags.where(targetTags.contains).length;
    return _clamp(matchCount / 3);
  }

  static double _socialWarmthScore(int faceCount, List<String> tags) {
    final socialTags = {'家庭', '友情', '情侣', '人群', '人像'};
    return _clamp((_tagMatchScore(tags, socialTags) * 0.5) + (faceCount / 8));
  }

  static double _staticVisualScore(List<String> tags) {
    return _tagMatchScore(tags, {'天空', '云', '风景', '建筑', '桥', '花朵', '树木'});
  }

  static double _daylightMoodScore(List<String> tags) {
    return _tagMatchScore(tags, {'日出', '日落', '夜晚', '傍晚', '早晨'});
  }

  static double _groupPhotoScore(int faceCount, List<String> tags) {
    return _clamp(
      (_tagMatchScore(tags, {'人群', '人像', '学校'}) * 0.4) + (faceCount / 10),
    );
  }

  static double _memorySceneScore(List<String> tags) {
    return _tagMatchScore(tags, {'学校', '教室', '校园', '古城', '家庭', '节日'});
  }

  static double _seasonalCeremonyScore(List<String> tags) {
    return _tagMatchScore(tags, {'节日', '灯光', '舞台', '活动', '花朵'});
  }

  static double _movementScore(List<String> tags) {
    return _tagMatchScore(tags, {'运动', '比赛', '街道', '道路', '自行车', '船'});
  }

  static double _nightLightScore(List<String> tags) {
    return _tagMatchScore(tags, {'夜晚', '灯光', '城市', '舞台', '节日'});
  }

  static double _clamp(double v) => v.clamp(0.0, 1.0);
}
