/// §9 导入时开学日期默认锚点与当前周数核对工具（纯函数）
class TermStartDateHelper {
  /// 匹配教务页常见当前周文案：「第8周」「第 12 周」「当前周：第5周」「当前第3周」
  static final RegExp _currentWeekReg = RegExp(r'第\s*(\d{1,2})\s*周');

  /// 计算指定日期所在周的周一（归零到 00:00:00）
  static DateTime mondayOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    // DateTime.monday == 1
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  /// §9 默认开学日期锚点：
  /// - 秋季学期（8月~次年1月）：取该学年 9 月 1 日所在周的周一
  /// - 春季学期（2月~7月）：取当年 3 月 1 日所在周的周一
  static DateTime defaultStartDateFor(DateTime now) {
    if (now.month >= 8) {
      return mondayOfWeek(DateTime(now.year, 9, 1));
    } else if (now.month == 1) {
      return mondayOfWeek(DateTime(now.year - 1, 9, 1));
    } else {
      return mondayOfWeek(DateTime(now.year, 3, 1));
    }
  }

  /// 根据第 1 周周一 [startDate] 与参考日期 [today] 计算当前是第几周（1-based）
  /// 若 [today] 早于开学日期，返回 0 或负数
  static int calculateWeekNumber({
    required DateTime startDate,
    required DateTime today,
  }) {
    final startMonday = mondayOfWeek(startDate);
    final todayDate = DateTime(today.year, today.month, today.day);
    final diffDays = todayDate.difference(startMonday).inDays;
    if (diffDays < 0) return 0;
    return (diffDays ~/ 7) + 1;
  }

  /// 根据教务页读到的「当前第 X 周」反推建议的开学日期（第 1 周周一）
  static DateTime suggestStartDateFromCurrentWeek({
    required int detectedCurrentWeek,
    required DateTime today,
  }) {
    final thisMonday = mondayOfWeek(today);
    return thisMonday.subtract(Duration(days: (detectedCurrentWeek - 1) * 7));
  }

  /// 从教务页文本中抽取当前第 X 周（1~30 合理范围内）；读不到返回 null
  static int? extractCurrentWeekFromText(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = _currentWeekReg.firstMatch(text);
    if (match == null) return null;
    final week = int.tryParse(match.group(1)!);
    if (week == null || week < 1 || week > 30) return null;
    return week;
  }
}
