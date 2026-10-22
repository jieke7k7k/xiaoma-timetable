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

  /// 用于页面定位的周次：钳制到 [1, totalWeeks]
  ///
  /// [currentWeek] 按语义允许返回超过学期总周数的实际周数（学期结束了还在数），
  /// 但这个值一旦用作 PageView 的页码就会越界崩溃，定位用途必须钳回来。
  /// [totalWeeks] <= 0（学期还没加载完）时保持原行为：只保下限 1、不限制上限。
  static int clampForPage(int week, int totalWeeks) {
    final w = week < 1 ? 1 : week;
    if (totalWeeks <= 0) return w;
    return w > totalWeeks ? totalWeeks : w;
  }

  /// 是否单周（奇数周）；week <= 0 时视为未开学，返回 false
  static bool isOddWeek(int week) => week > 0 && week.isOdd;

  /// 单双周描述文本
  static String weekTypeText(int week) {
    if (week <= 0) return '未开学';
    return week.isOdd ? '单周' : '双周';
  }

  /// 单双周小标识文本（主页左上角那枚小字）；学期外返回 null 表示「不显示」
  ///
  /// 与 [weekTypeText] 的差别：这里对「不该显示」的情形返回 null，而不是给一句
  /// 「未开学」占位——小标识是装饰性元素，未开学（week ≤ 0）或学期已结束
  /// （week 超过总周数）时整个不出现才对。
  /// [totalWeeks] ≤ 0 表示总周数未知（学期还没加载），此时不判断上限。
  static String? parityLabel(int week, {int totalWeeks = 0}) {
    if (week <= 0) return null;
    if (totalWeeks > 0 && week > totalWeeks) return null;
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
