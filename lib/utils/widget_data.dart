import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import 'color_schemes.dart';
import 'next_class.dart';
import 'week_calc.dart';

/// 桌面小部件数据（1.2.2 改版，对照 WakeUp 式列表样式）
///
/// 顶栏：左 = 学期名，右 = 「M.d 第X周 周X」（所展示那天的日期）；
/// 列表：当天尚未结束的课（正在上的 + 后面的），今天没了就换明天的；
/// 每行 = 课程色竖条 + 课名 / 教室 教师 + 右侧起止时间。最多 4 行，
/// 超出部分在底部注明「还有 N 节课」。数据经 JSON 交给原生侧渲染。
class WidgetRow {
  const WidgetRow({
    required this.name,
    required this.sub,
    required this.start,
    required this.end,
    required this.colorArgb,
  });

  final String name;

  /// 「教室 教师」拼接（缺哪项省哪项，可为空串）
  final String sub;
  final String start;
  final String end;

  /// 已按当前配色方案映射过的课程色（ARGB int）
  final int colorArgb;

  Map<String, dynamic> toJson() => {
    'name': name,
    'sub': sub,
    'start': start,
    'end': end,
    'color': colorArgb,
  };
}

class WidgetPayload {
  const WidgetPayload({
    required this.headerLeft,
    required this.headerRight,
    required this.rows,
    required this.footer,
    required this.emptyText,
  });

  final String headerLeft;
  final String headerRight;
  final List<WidgetRow> rows;

  /// 超出 4 行时的尾注（如「还有 2 节课」），无则空串
  final String footer;

  /// 无课可显示时的占位文案
  final String emptyText;

  Map<String, dynamic> toJson() => {
    'headerLeft': headerLeft,
    'headerRight': headerRight,
    'rows': rows.map((r) => r.toJson()).toList(),
    'footer': footer,
    'emptyText': emptyText,
  };
}

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

WidgetPayload buildWidgetPayload({
  required DateTime now,
  required Semester? semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  List<CourseOverride> overrides = const [],
  UiSettings ui = const UiSettings(),
}) {
  if (semester == null) {
    return WidgetPayload(
      headerLeft: '小马课表',
      headerRight: '${now.month}.${now.day} 周${_weekdayNames[now.weekday - 1]}',
      rows: const [],
      footer: '',
      emptyText: '暂无课程',
    );
  }
  final today = DateTime(now.year, now.month, now.day);
  var day = today;
  var sessions = sessionsOnDay(
    date: day,
    semester: semester,
    courses: courses,
    timeSlots: timeSlots,
    overrides: overrides,
  ).where((s) => s.end.isAfter(now)).toList();
  if (sessions.isEmpty) {
    // 今天没课了 → 展示明天的全天课（顶栏日期随之切换）
    day = today.add(const Duration(days: 1));
    sessions = sessionsOnDay(
      date: day,
      semester: semester,
      courses: courses,
      timeSlots: timeSlots,
      overrides: overrides,
    );
  }
  final week = WeekCalc.currentWeek(DateTime.parse(semester.startDate), day);
  final headerRight =
      '${day.month}.${day.day} '
      '${week >= 1 ? '第$week周 ' : ''}周${_weekdayNames[day.weekday - 1]}';
  WidgetRow toRow(ClassSession s) {
    final parts = [
      s.course.classroom?.trim() ?? '',
      s.course.teacher?.trim() ?? '',
    ].where((e) => e.isNotEmpty).join(' ');
    return WidgetRow(
      name: s.course.name,
      sub: parts,
      start: fmtHhmm(s.start),
      end: fmtHhmm(s.end),
      colorArgb: mapCourseColor(s.course.colorValue, ui.colorScheme),
    );
  }

  final all = sessions.map(toRow).toList();
  return WidgetPayload(
    headerLeft: semester.name,
    headerRight: headerRight,
    rows: all.take(4).toList(),
    footer: all.length > 4 ? '还有 ${all.length - 4} 节课' : '',
    emptyText: '暂无课程',
  );
}
