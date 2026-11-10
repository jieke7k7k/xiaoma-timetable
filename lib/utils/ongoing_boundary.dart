import 'next_class.dart';

/// 今日课程常驻通知「单闹钟接力」的下一个边界点（WB_SPEC_229 第 3.2 节，纯逻辑）
///
/// 边界点 = min(正在上的课的下课时刻, 下一节课的上课时刻)：
/// 下课要立刻把标题从「正在上课」翻成「下一节」，上课要立刻翻成「正在上课」，
/// 两个时刻里更早的那个就是这条通知下一次必须重算的时刻。
///
/// 未来 9 天内都没有课（假期 / 学期外 / 课表为空）：取次日 00:05 的一天一 tick。
/// 此时文案是兜底「暂无课程安排」，不需要高频刷新，这个 tick 只为「不断链」——
/// 假期结束的那天早上，链还在，下一节课的边界点自然会被算出来。
///
/// 返回值与 Kotlin 侧 OngoingFocusCalculator.nextBoundary 逐字等价，
/// 两边改一处必须同时改另一处（共享夹具见 test/fixtures/ongoing_focus_cases.json）。
DateTime computeNextBoundary({required DateTime now, required ClassFocus focus}) {
  DateTime? earliest;
  for (final t in <DateTime?>[focus.current?.end, focus.next?.start]) {
    if (t == null) continue;
    if (earliest == null || t.isBefore(earliest)) earliest = t;
  }
  // 必须晚于 now：时钟跳变 / 脏数据算出过去时刻时退回次日 00:05，
  // 否则闹钟会「立刻触发 → 触发后又排一个立刻到期的闹钟」形成死循环
  if (earliest != null && earliest.isAfter(now)) return earliest;
  return DateTime(now.year, now.month, now.day + 1, 0, 5);
}
