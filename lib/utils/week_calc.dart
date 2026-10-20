/// 周次计算工具类
///
/// 核心约定：
/// - 开学日期会自动对齐到该周的周一（用户填的可能不是周一）
/// - 周次从 1 开始计数；开学前返回 0，超出学期总周数仍返回实际周数
/// - 单双周按周次的奇偶判断：奇数周为单周，偶数周为双周
class WeekCalc {
  WeekCalc._();

  /// 把任意日期对齐到所在周的周一
  static DateTime alignToMonday(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// 计算 [target] 相对开学日期 [semesterStart] 是第几周。
  /// 开学前返回 0（表示未开学）；开学当天所在周返回 1。
  static int currentWeek(DateTime semesterStart, DateTime target) {
    final startMonday = alignToMonday(semesterStart);
    final targetDay = DateTime(target.year, target.month, target.day);
    final diffDays = targetDay.difference(startMonday).inDays;
    if (diffDays < 0) return 0;
    return diffDays ~/ 7 + 1;
  }

  /// 是否单周（奇数周）；week <= 0 时视为未开学，返回 false
  static bool isOddWeek(int week) => week > 0 && week.isOdd;

  /// 单双周描述文本
  static String weekTypeText(int week) {
    if (week <= 0) return '未开学';
    return week.isOdd ? '单周' : '双周';
  }

  /// 返回 [target] 所在周周一到周日的日期列表（共 7 天）
  static List<DateTime> weekDates(DateTime target) {
    final monday = alignToMonday(target);
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  /// 返回第 [week] 周周一到周日的日期列表
  static List<DateTime> weekDatesOf(DateTime semesterStart, int week) {
    final startMonday = alignToMonday(semesterStart);
    final monday = startMonday.add(Duration(days: (week - 1) * 7));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  /// 顶部栏展示文本，如「第 3 周 · 单周」
  static String weekTitle(int week) {
    if (week <= 0) return '距开学还有一段时间';
    return '第 $week 周 · ${weekTypeText(week)}';
  }
}
