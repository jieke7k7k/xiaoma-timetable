import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import 'override_effect.dart';
import 'week_calc.dart';

/// 上课提醒的纯逻辑工具（阶段四·本地通知）
///
/// 全部为纯函数，不依赖任何插件/平台通道，便于单元测试。
/// NotificationService 在排期前调用这里产出「某天需要提醒的课程清单」，
/// 再逐条转成 zonedSchedule 的精确闹钟。

/// 一条待排期的提醒计划（纯数据）
class ReminderPlan {
  final Course course;
  final DateTime courseStart; // 实际上课时刻
  final DateTime reminderTime; // 提醒时刻 = 上课时刻 - 提前分钟

  const ReminderPlan({
    required this.course,
    required this.courseStart,
    required this.reminderTime,
  });
}

/// 计算提醒时刻：上课时间减去提前 N 分钟
DateTime computeReminderTime(DateTime courseStart, int advanceMinutes) =>
    courseStart.subtract(Duration(minutes: advanceMinutes));

/// 通知正文文案：
/// - 有教室：「《xx》还有 15 分钟在 xx教室上课」
/// - 无教室兜底：「《xx》还有 15 分钟上课」
String buildReminderBody(Course course, int advanceMinutes) {
  final room = course.classroom?.trim();
  if (room == null || room.isEmpty) {
    return '《${course.name}》还有 $advanceMinutes 分钟上课';
  }
  return '《${course.name}》还有 $advanceMinutes 分钟在 $room 上课';
}

/// 构建某天需要提醒的课程计划（纯函数）。
///
/// 筛选规则：
/// 1. [date] 的星期与课程（应用单次调课后）的 dayOfWeek 一致
///    （周一=1 … 周日=7，与 DateTime.weekday 对齐）；
/// 2. 该日所在周次在课程 weeks 中且通过单双周过滤（复用 Course.isActiveInWeek）；
/// 3. 能按 startSection 在 [timeSlots] 找到节次时间（找不到说明节次表缺失，跳过）。
///
/// 单次调课（[overrides]，阶段五）：先经 [effectiveCoursesForWeek] 应用到本周——
/// 停课的本次不再提醒，调课的按新星期/新节次提醒（教室文案用新教室）。
///
/// 结果按提醒时刻升序，方便排期。
List<ReminderPlan> buildDailyReminderPlan({
  required DateTime date,
  required Semester semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  required int advanceMinutes,
  List<CourseOverride> overrides = const [],
}) {
  // 未开学（周次 0）没有任何课
  final week = WeekCalc.currentWeek(DateTime.parse(semester.startDate), date);
  if (week <= 0) return const [];

  // 应用单次调课：得到本周有效上课实例（停课移除、调课替换为新时间/教室）
  final effective = effectiveCoursesForWeek(
      courses: courses, overrides: overrides, week: week);

  final plans = <ReminderPlan>[];
  for (final course in effective) {
    if (course.dayOfWeek != date.weekday) continue;
    if (!course.isActiveInWeek(week)) continue;
    final start = courseStartTime(date, course, timeSlots);
    if (start == null) continue;
    plans.add(ReminderPlan(
      course: course,
      courseStart: start,
      reminderTime: computeReminderTime(start, advanceMinutes),
    ));
  }
  plans.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
  return plans;
}

/// 由节次时间表解析课程在 [date] 当天的上课时刻；找不到对应节次返回 null
DateTime? courseStartTime(
    DateTime date, Course course, List<TimeSlot> timeSlots) {
  for (final slot in timeSlots) {
    if (slot.section == course.startSection) {
      return combineDateAndTime(date, slot.startTime);
    }
  }
  return null;
}

/// 把日期与 "HH:mm" 文本合并为 DateTime；解析失败返回 null
DateTime? combineDateAndTime(DateTime date, String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(date.year, date.month, date.day, hour, minute);
}
