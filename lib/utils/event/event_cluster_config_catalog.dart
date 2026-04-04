import 'event_cluster_helper.dart';
import 'event_festival_rules.dart';

class ClusterConfigParameter {
  final String key;
  final String label;
  final String description;
  final String unit;
  final String increaseEffect;
  final String decreaseEffect;

  const ClusterConfigParameter({
    required this.key,
    required this.label,
    required this.description,
    required this.unit,
    required this.increaseEffect,
    required this.decreaseEffect,
  });
}

class EventClusterConfigCatalog {
  const EventClusterConfigCatalog._();

  // 当前线上默认聚类配置。仅做集中管理，不改变任何现有算法逻辑。
  static const ClusterConfig defaultConfig = ClusterConfig(
    initialTimeThresholdHours: 4,
    baseDistanceThresholdKm: 12,
    sameCityTimeThresholdHours: 6,
    sameCityDistanceThresholdKm: 20,
    fallbackSameCityDistanceKm: 45,
    sameDayMergeGapHours: 10,
    crossDayMergeGapHours: 18,
    minPhotosPerClusterForMerge: 1,
    enableSameDayTravelMerge: true,
    enableCrossDayTravelMerge: true,
    enableFestivalClustering: true,
    festivalMergeGapHours: 48,
    festivalListVersion: EventFestivalRules.builtInVersion,
  );

  // 供调参/调试查看的参数表，不参与聚类判断。
  static const List<ClusterConfigParameter> parameterTable = [
    ClusterConfigParameter(
      key: 'initialTimeThresholdHours',
      label: '初分簇时间阈值',
      description: '非同城相邻照片的时间切分阈值，超过后直接切成新事件。',
      unit: '小时',
      increaseEffect: '事件更容易被合并成大簇。',
      decreaseEffect: '事件更容易被切碎。',
    ),
    ClusterConfigParameter(
      key: 'baseDistanceThresholdKm',
      label: '初分簇距离阈值',
      description: '非同城或未判定同城时，相邻照片的距离切分阈值。',
      unit: '公里',
      increaseEffect: '空间跨度更大的照片也可能保留在同一事件。',
      decreaseEffect: '更容易因为位移而拆成多个事件。',
    ),
    ClusterConfigParameter(
      key: 'sameCityTimeThresholdHours',
      label: '同城时间阈值',
      description: '同城照片的宽松时间阈值，避免同城活动被过度切碎。',
      unit: '小时',
      increaseEffect: '同城事件会更长、更容易合并。',
      decreaseEffect: '同城事件更容易被拆开。',
    ),
    ClusterConfigParameter(
      key: 'sameCityDistanceThresholdKm',
      label: '同城距离阈值',
      description: '同城照片的宽松距离阈值，允许城市内较大位移仍视作同一事件。',
      unit: '公里',
      increaseEffect: '同城多地点活动更容易归并为一个事件。',
      decreaseEffect: '同城活动更容易拆成多个事件。',
    ),
    ClusterConfigParameter(
      key: 'fallbackSameCityDistanceKm',
      label: 'GPS 兜底同城阈值',
      description: '缺少 adcode/city 时，用 GPS 距离粗略判定同城/跨城的阈值。',
      unit: '公里',
      increaseEffect: '更多未知地址照片会被视作同城。',
      decreaseEffect: '更多未知地址照片会被视作跨城。',
    ),
    ClusterConfigParameter(
      key: 'sameDayMergeGapHours',
      label: '同日合并间隔',
      description: '同一天相邻簇的最大允许合并间隔。',
      unit: '小时',
      increaseEffect: '同日碎片簇更容易重新合并。',
      decreaseEffect: '同日片段更容易保持拆分状态。',
    ),
    ClusterConfigParameter(
      key: 'crossDayMergeGapHours',
      label: '跨日合并间隔',
      description: '跨天相邻簇的最大允许合并间隔。',
      unit: '小时',
      increaseEffect: '跨天旅行/连续活动更容易被视作同一事件。',
      decreaseEffect: '跨天更容易切成不同事件。',
    ),
    ClusterConfigParameter(
      key: 'minPhotosPerClusterForMerge',
      label: '参与合并的最小簇大小',
      description: '旅行合并前，左右两边簇都需要达到的最小照片数。',
      unit: '张',
      increaseEffect: '更少小簇会参与合并，结果更保守。',
      decreaseEffect: '更多小簇会参与合并，结果更激进。',
    ),
    ClusterConfigParameter(
      key: 'festivalMergeGapHours',
      label: '节日合并间隔',
      description: '同一节日相邻簇的最大允许合并间隔。',
      unit: '小时',
      increaseEffect: '节日事件更容易合并成一整个大事件。',
      decreaseEffect: '节日事件更容易被拆开。',
    ),
  ];

  static Map<String, dynamic> toValueMap([
    ClusterConfig config = defaultConfig,
  ]) {
    return {
      'initialTimeThresholdHours': config.initialTimeThresholdHours,
      'baseDistanceThresholdKm': config.baseDistanceThresholdKm,
      'sameCityTimeThresholdHours': config.sameCityTimeThresholdHours,
      'sameCityDistanceThresholdKm': config.sameCityDistanceThresholdKm,
      'fallbackSameCityDistanceKm': config.fallbackSameCityDistanceKm,
      'sameDayMergeGapHours': config.sameDayMergeGapHours,
      'crossDayMergeGapHours': config.crossDayMergeGapHours,
      'minPhotosPerClusterForMerge': config.minPhotosPerClusterForMerge,
      'enableSameDayTravelMerge': config.enableSameDayTravelMerge,
      'enableCrossDayTravelMerge': config.enableCrossDayTravelMerge,
      'enableFestivalClustering': config.enableFestivalClustering,
      'festivalMergeGapHours': config.festivalMergeGapHours,
      'festivalListVersion': config.festivalListVersion,
    };
  }
}
