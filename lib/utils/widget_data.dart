import '../models/course.dart';
import '../models/course_override.dart';
import '../models/note.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import 'color_schemes.dart';
import 'next_class.dart';
import 'week_calc.dart';

/// 备注最多带几条进 payload（再多桌面也放不下，且 crowding 掉课程行没必要）
const int kWidgetMaxNotes = 3;

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
    this.notes = const [],
  });

  final String headerLeft;
  final String headerRight;
  final List<WidgetRow> rows;

  /// 超出 4 行时的尾注（如「还有 2 节课」），无则空串
  final String footer;

  /// 无课可显示时的占位文案
  final String emptyText;

  /// 当日备注内容，最多 [kWidgetMaxNotes] 条（v3）。
  /// 原生端渲染在课程列表下方；没有该字段的老 payload 照常渲染。
  final List<String> notes;

  Map<String, dynamic> toJson() => {
    'headerLeft': headerLeft,
    'headerRight': headerRight,
    'rows': rows.map((r) => r.toJson()).toList(),
    'footer': footer,
    'emptyText': emptyText,
    'notes': notes,
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
  Map<String, List<Note>> notesByDate = const {},
}) {
  if (semester == null) {
    return WidgetPayload(
      headerLeft: '小马课表',
      headerRight: '${now.month}.${now.day} 周${_weekdayNames[now.weekday - 1]}',
      rows: const [],
      footer: '',
      emptyText: '暂无课程',
      notes: _widgetNotes(notesByDate, widgetDayKey(now)),
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
  final week = WeekCalc.currentWeek(semester.startDateParsed, day);
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
    // 备注跟着「实际展示的那天」走：今天还有课就用今天的，今天没课顺延到明天时
    // 也跟着换成明天的——与顶栏日期口径一致，不会今天显示昨天的备忘
    notes: _widgetNotes(notesByDate, widgetDayKey(day)),
  );
}

/// 取某一天的备注文本：去空白、丢空串，最多 [kWidgetMaxNotes] 条
List<String> _widgetNotes(Map<String, List<Note>> byDate, String dayKey) {
  final list = byDate[dayKey];
  if (list == null || list.isEmpty) return const [];
  return [
    for (final n in list)
      if (n.content.trim().isNotEmpty) n.content.trim(),
  ].take(kWidgetMaxNotes).toList();
}

/// 逐日 payload 的日期键格式：yyyy-MM-dd（本地日期，与 Kotlin 端 SimpleDateFormat
/// 同格式，两侧口径必须一致，否则跨天取不到当天那份）。
String widgetDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// 逐日 payload 表（1.3.4，小部件跨天自动切换）
///
/// 背景：小部件由系统每 30 分钟重绘，但内容 payload 只在 App 端刷新时写入；
/// 长假不开 App 时 widget_payload 是旧日期的内容，跨天不会变。
/// 这里一次算好「今天 + 未来 [days-1] 天」共 [days] 份，原生侧按当天日期取用。
///
/// 键 = [widgetDayKey]（本地日期），值 = 该日 payload 的 JSON 结构
/// （与 [buildWidgetPayload]().toJson() 完全相同，字段不变）。
/// - 今天：用真实 [now] 构建 → 与现有 widget_payload 逐字一致；
/// - 未来某日：用该日 00:00 作 now → 当天课程全部「未结束」，完整入选。
Map<String, Map<String, dynamic>> buildWidgetPayloadDays({
  required DateTime now,
  required Semester? semester,
  required List<Course> courses,
  required List<TimeSlot> timeSlots,
  List<CourseOverride> overrides = const [],
  UiSettings ui = const UiSettings(),
  int days = 7,
  Map<String, List<Note>> notesByDate = const {},
}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <String, Map<String, dynamic>>{};
  for (var offset = 0; offset < days; offset++) {
    final day = today.add(Duration(days: offset));
    final key = widgetDayKey(day);
    final json = buildWidgetPayload(
      now: offset == 0 ? now : day,
      semester: semester,
      courses: courses,
      timeSlots: timeSlots,
      overrides: overrides,
      ui: ui,
      notesByDate: notesByDate,
    ).toJson();
    // 逐日条目按「条目日期」取用：课程行可以顺延（今天没课预告明天），但备注
    // 必须属于条目日期本身——周一那份若带上周二的备注，周一当天就会看到
    // 明天的备忘。故这里按条目日期覆写 notes，不跟随顺延后的展示日。
    json['notes'] = _widgetNotes(notesByDate, key);
    out[key] = json;
  }
  return out;
}
