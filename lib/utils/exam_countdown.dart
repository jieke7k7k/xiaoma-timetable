/// 考试倒计时纯函数工具（阶段五·考试/作业倒计时）
///
/// 设计要点：
/// - 全部为纯函数，不依赖 UI / 数据库 / 平台通道，可脱离 Flutter 环境单测
/// - 「天数」按日历日期差计算，忽略时分秒：
///   考试是 10-22，今天 10-15，无论现在是早上 0 点还是晚上 23 点都算「还有 7 天」
class ExamCountdown {
  ExamCountdown._();

  /// 计算考试日期 [examDate] 相对 [now] 的天数差（忽略时分秒）。
  /// 返回值 >0 表示还有几天；0 表示就是今天；<0 表示已过去几天。
  ///
  /// 为什么先转 UTC 再作差：本地时间在夏令时切换日一天可能只有 23 或 25 小时，
  /// 直接用本地日期 difference().inDays 会因截断差一天；
  /// DateTime.utc 没有时区偏移与夏令时，按「日历日」作差严格准确。
  static int daysUntil(DateTime examDate, DateTime now) {
    final examDay =
        DateTime.utc(examDate.year, examDate.month, examDate.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    return examDay.difference(today).inDays;
  }

  /// 天数差 → 倒计时文案。
  /// >0 显示「还有 X 天」；0 显示「今天考试」；<0 显示「已结束」。
  static String countdownText(int days) {
    if (days > 0) return '还有 $days 天';
    if (days == 0) return '今天考试';
    return '已结束';
  }
}
