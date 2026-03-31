/// 时间规则（聚类工具）。
///
/// 聚类中很多判断要区分“同一天”与“跨天”，这里统一封装，避免在主流程里重复写时间处理。
class EventClusterTimeRules {
  const EventClusterTimeRules._();

  /// 判断两个毫秒时间戳是否落在同一个“本地自然日”。
  ///
  /// 注意：这里使用本地时区（DateTime.fromMillisecondsSinceEpoch 默认按本地时区解析）。
  static bool isSameLocalDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }
}
