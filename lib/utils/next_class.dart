import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import 'override_effect.dart';
import 'reminder_plan.dart' show combineDateAndTime;
import 'week_calc.dart';

/// 「当前 / 下一节课」焦点计算（1.2.0）
///
/// 主页顶部状态条与常驻通知共用同一套纯逻辑，保证两处说法永远一致：
/// - 上课前 / 课间：聚焦下一节课；
/// - 上课中：聚焦正在上的课，并预告下一节；
/// - 今天没课了：向前看到最近的那一节（明天、周末后都算）。
/// 单次调课（overrides）按所在周生效，与课表渲染口径一致。

/// 一次具体的课：某一天的某一门课，带确切起止时刻
class ClassSession {
  const ClassSession({
    required this.course,
    required this.date,
    required this.start,
    required this.end,
  });

  final Course course;

  /// 上课日期（当天 0 点）
  final DateTime date;
  final DateTime start;
  final DateTime end;

  /// 「08:00–08:40」式时间段文本
  String get timeRange => '${fmtHhmm(start)}–${fmtHhmm(end)}';

  /// 一行摘要：「药理学 08:00–08:40 · 教3-201」（无教室自动省略）
  String get summary {
    final room = course.classroom?.trim();
    return '${course.name} $timeRange'
        '${room != null && room.isNotEmpty ? " · $room" : ""}';
  }
}

/// 当前 / 下一节课焦点
class ClassFocus {
  const ClassFocus({this.current, this.next, this.laterTodayCount = 0});

  /// 正在上的课（没有为 null）
  final ClassSession? current;

  /// 下一节课（今天稍后或未来最近的一节；没有为 null）
  final ClassSession? next;

  /// 今天在 [next] 之后还有几节课（通知附带提示用）
  final int laterTodayCount;

  bool get hasAny => current != null || next != null;
}

/// HH:mm 格式化
String fmtHhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 相对今天的日期标签：今天 / 明天 / 周X（M月D日）
String dayLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  return '周${names[date.weekday - 1]}（${date.month}月${date.day}日）';
}

/// 计算 [now] 时刻的课程焦点。
///
/// 向前看 9 天生成具体课次（覆盖周末→下周一与短假期），
/// 按所在周应用调课后取正在上的与下一节。
ClassFocus computeClassFocus({
  required DateTime now,
  required Semester semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  List<CourseOverride> overrides = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  final sessions = <ClassSession>[
    for (var offset = 0; offset <= 8; offset++)
      ...sessionsOnDay(
        date: today.add(Duration(days: offset)),
        semester: semester,
        courses: courses,
        timeSlots: timeSlots,
        overrides: overrides,
      ),
  ]..sort((a, b) => a.start.compareTo(b.start));

  ClassSession? current;
  for (final s in sessions) {
    if (!s.start.isAfter(now) && s.end.isAfter(now)) {
      current = s;
      break;
    }
  }
  ClassSession? next;
  for (final s in sessions) {
    if (s.start.isAfter(now)) {
      next = s;
      break;
    }
  }
  var later = 0;
  if (next != null && next.date == today) {
    later = sessions
        .where((s) => s.date == today && s.start.isAfter(next!.start))
        .length;
  }
  return ClassFocus(current: current, next: next, laterTodayCount: later);
}

/// 某一天的具体课次（1.2.2 从 computeClassFocus 抽出，桌面小部件共用同一口径）
///
/// 已应用单次调课（overrides）与单双周/周次过滤，按开始时间排序；
/// 日期不在学期范围内返回空列表。
/// 注意：effectiveCoursesForWeek 按约定不做周次过滤，这里统一补上 isActiveInWeek。
List<ClassSession> sessionsOnDay({
  required DateTime date,
  required Semester semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  List<CourseOverride> overrides = const [],
}) {
  final day = DateTime(date.year, date.month, date.day);
  final week = WeekCalc.currentWeek(DateTime.parse(semester.startDate), day);
  if (week < 1 || week > semester.totalWeeks) return const [];
  final slotMap = {for (final s in timeSlots) s.section: s};
  final out = <ClassSession>[];
  final effective = effectiveCoursesForWeek(
    courses: courses,
    overrides: overrides,
    week: week,
  ).where((c) => c.isActiveInWeek(week));
  for (final c in effective) {
    if (c.dayOfWeek != day.weekday) continue;
    final sSlot = slotMap[c.startSection];
    final eSlot = slotMap[c.endSection];
    if (sSlot == null || eSlot == null) continue;
    final start = combineDateAndTime(day, sSlot.startTime);
    final end = combineDateAndTime(day, eSlot.endTime);
    if (start == null || end == null) continue;
    out.add(ClassSession(course: c, date: day, start: start, end: end));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
