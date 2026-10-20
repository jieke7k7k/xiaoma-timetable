import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import 'override_effect.dart';
import 'reminder_plan.dart' show combineDateAndTime;
import 'week_calc.dart';

/// 今日课程常驻通知栏的纯逻辑（阶段四·常驻通知）
///
/// 全部为纯函数，不依赖任何插件 / 平台通道，便于单元测试。
/// OngoingNoticeService 在下发通知前调用 [buildOngoingNotice] 产出标题与行文案，
/// 再通过 MethodChannel 交给 Android 原生前台 Service 渲染。

/// 一条常驻通知的内容（纯数据）
class OngoingNotice {
  final String title; // 标题：今日剩余课程（共 X 节）/ 明日课程预告（共 X 节）
  final List<String> lines; // 行文案，如「08:00-08:45 高等数学 A101」

  const OngoingNotice({required this.title, required this.lines});
}

/// 构建今日常驻通知内容（纯函数）。
///
/// 切换规则（B 决策）：
/// 1. 只要今天还有「未下课」的课程（当前时间早于其下课时间），就显示「今日剩余课程」，
///    哪怕已经过了 20:00；
/// 2. 仅当今天所有课程均已下课（或今天本就没课），才切换为「明日课程预告」。
///
/// 行文案按节次升序；无教室的课程省略教室字段；明日无课则给兜底文案「明天暂无课程」。
///
/// 单次调课（[overrides]，阶段五）：今天/明天各自按其所在周次应用调课——
/// 停课的本次不展示，调课的按新星期/新节次/新教室展示。
/// 今天与明天可能分属两个周次（周日晚 → 周一早），所以按日期分别计算周次。
OngoingNotice buildOngoingNotice({
  required DateTime now,
  required Semester semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  List<CourseOverride> overrides = const [],
}) {
  final slotMap = {for (final s in timeSlots) s.section: s};

  // 今天尚未下课的课程：结束时间晚于当前时间
  final todayRemaining = _coursesOnDay(now, semester, courses, overrides)
      .where((c) {
        final end = _endDateTime(now, c, slotMap);
        if (end == null) return false; // 节次时间缺失，无法判断下课，跳过
        return now.isBefore(end);
      })
      .toList();

  if (todayRemaining.isNotEmpty) {
    return OngoingNotice(
      title: '今日剩余课程（共 ${todayRemaining.length} 节）',
      lines: _toLines(todayRemaining, slotMap),
    );
  }

  // 明日课程预告
  final tomorrow = DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 1));
  final tomorrowCourses =
      _coursesOnDay(tomorrow, semester, courses, overrides);
  if (tomorrowCourses.isEmpty) {
    return const OngoingNotice(
      title: '明日课程预告（共 0 节）',
      lines: ['明天暂无课程'],
    );
  }
  return OngoingNotice(
    title: '明日课程预告（共 ${tomorrowCourses.length} 节）',
    lines: _toLines(tomorrowCourses, slotMap),
  );
}

/// 某天应显示的课程：星期一致 + 周次在范围内 + 单双周过滤 + 应用单次调课
List<Course> _coursesOnDay(DateTime date, Semester semester,
    List<Course> courses, List<CourseOverride> overrides) {
  final week = WeekCalc.currentWeek(DateTime.parse(semester.startDate), date);
  if (week <= 0) return const [];
  // 先应用单次调课（停课移除、调课替换为新星期/节次/教室），再按当天星期过滤
  final effective = effectiveCoursesForWeek(
      courses: courses, overrides: overrides, week: week);
  return effective.where((c) => c.dayOfWeek == date.weekday).toList();
}

/// 课程在 [date] 当天的下课时刻；找不到对应节次时间返回 null
DateTime? _endDateTime(DateTime date, Course c, Map<int, TimeSlot> slotMap) {
  final end = slotMap[c.endSection]?.endTime;
  if (end == null) return null;
  return combineDateAndTime(date, end);
}

/// 按节次升序生成行文案；节次时间缺失时仅显示课程名（不显示时间）
List<String> _toLines(List<Course> courses, Map<int, TimeSlot> slotMap) {
  final sorted = [...courses]
    ..sort((a, b) => a.startSection.compareTo(b.startSection));
  return sorted.map((c) => _formatLine(c, slotMap)).toList();
}

/// 行文案：「08:00-08:45 高等数学 A101」；无教室省略教室
String _formatLine(Course c, Map<int, TimeSlot> slotMap) {
  final start = slotMap[c.startSection]?.startTime;
  final end = slotMap[c.endSection]?.endTime;
  final parts = <String>[];
  if (start != null && end != null) {
    parts.add('$start-$end');
  }
  parts.add(c.name);
  final room = c.classroom?.trim();
  if (room != null && room.isNotEmpty) {
    parts.add(room);
  }
  return parts.join(' ');
}
