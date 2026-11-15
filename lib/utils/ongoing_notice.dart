import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import 'next_class.dart';

/// 常驻通知栏内容构建（纯逻辑）
///
/// 1.2.0 起改「焦点模式」，与主页顶部状态条共用 [computeClassFocus]：
/// - 上课中：标题是正在上的课，行内给下课时间 + 下一节预告；
/// - 上课前 / 课间：标题是下一节课，行内给时间地点（今天还有更多课时附带提示）；
/// - 近期无课：兜底文案。
/// 通知是静态下发的（靠外部触发刷新），因此文案不带「还有 X 分钟」这类易过期信息。

/// 一条常驻通知的内容（纯数据）
class OngoingNotice {
  final String title;
  final List<String> lines;

  const OngoingNotice({required this.title, required this.lines});
}

/// 构建常驻通知内容（纯函数）。
OngoingNotice buildOngoingNotice({
  required DateTime now,
  required Semester semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  List<CourseOverride> overrides = const [],
}) {
  final focus = computeClassFocus(
    now: now,
    semester: semester,
    courses: courses,
    timeSlots: timeSlots,
    overrides: overrides,
  );
  final cur = focus.current;
  final nxt = focus.next;

  if (cur != null) {
    final note = _noteLine(cur.course);
    return OngoingNotice(
      title: '正在上课：${cur.course.name}',
      lines: [
        '${cur.timeRange}${_roomSuffix(cur.course)}',
        if (note != null) note,
        if (nxt != null)
          '下一节：${nxt.course.name} · ${dayLabel(nxt.date, now)} '
              '${fmtHhmm(nxt.start)}${_roomSuffix(nxt.course)}'
        else
          '今天没有其他课了',
      ],
    );
  }
  if (nxt != null) {
    final isToday = dayLabel(nxt.date, now) == '今天';
    final note = _noteLine(nxt.course);
    return OngoingNotice(
      title: '下一节：${nxt.course.name}',
      lines: [
        '${isToday ? "" : "${dayLabel(nxt.date, now)} "}'
            '${nxt.timeRange}${_roomSuffix(nxt.course)}',
        if (note != null) note,
        if (focus.laterTodayCount > 0)
          '今天后面还有 ${focus.laterTodayCount} 节课',
      ],
    );
  }
  return const OngoingNotice(
    title: '暂无课程安排',
    lines: ['近期没有要上的课，好好休息'],
  );
}

/// 「 · 教室」后缀；无教室返回空串
String _roomSuffix(Course c) {
  final room = c.classroom?.trim();
  return room != null && room.isNotEmpty ? ' · $room' : '';
}

/// 备注行：只对填了备注的课显示；空白备注不占行。
/// 只取焦点课（正在上的课 / 下一节课）的备注，预告行里下一节的备注不另起行。
/// 备注行永远排在时间行之后：收起时正文仍是第一行（时间），备注只在展开后出现。
String? _noteLine(Course c) {
  final note = c.note?.trim();
  return note != null && note.isNotEmpty ? note : null;
}
