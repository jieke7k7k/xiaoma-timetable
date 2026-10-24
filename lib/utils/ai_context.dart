import 'dart:convert';

import '../models/course.dart';
import '../models/note.dart';
import '../models/semester.dart';
import '../services/command_executor.dart';
import 'command_describe.dart' as cmd;
import 'exam_countdown.dart';
import 'week_calc.dart';

/// 内置 AI 的「课表上下文 + 回复解析」（**纯函数区**，不碰网络与数据库）
///
/// 内置助手要能直接答「我明天有什么课」「哪天有空」，靠的就是发送时现取的一份
/// 上下文（学期 / 本周课表 / 临近考试 / 今明两天备注）。组装与解析都放在这里，
/// 页面与服务只负责取数与发请求——于是这两块可以在纯 Dart 环境里单测。
///
/// 指令协议与 AI 桥同源：模型要动手时，在回复里附一个 fenced json 代码块
/// ```json
/// {"commands": [ …CommandExecutor 指令… ]}
/// ```
/// App 解析出来后**不直接执行**（见 ai_chat_page 的确认卡片），解析出的代码块
/// 也不会原样展示给用户，只留下正文。

// ---------- 回复解析 ----------

/// 模型回复的解析结果
class AiReply {
  const AiReply({
    required this.text,
    required this.commands,
    this.commandParseError,
  });

  /// 去掉指令代码块后的正文（直接展示给用户）
  final String text;

  /// 解析出的指令原文（逐条喂给 CommandExecutor）；没有指令块时为空列表
  final List<Map<String, dynamic>> commands;

  /// 代码块看着像指令块但 JSON 坏了时的中文提示（不影响正文展示）
  final String? commandParseError;

  bool get hasCommands => commands.isNotEmpty;
}

/// 围栏代码块（``` 或 ~~~，可带语言标记）
final RegExp _fencePattern = RegExp(r'```[ \t]*(\w*)[ \t]*\r?\n([\s\S]*?)```');

/// 解析模型回复：抽出指令块并把代码块从正文里**摘掉**。
///
/// 只认「内容能解析成对象且含 commands 数组」的代码块——普通的示例代码块
/// （模型讲解 JSON 格式时很常见）原样留在正文里，不会被误当成指令。
/// 多个指令块会按顺序合并（模型偶尔把一个块拆成两块）。
AiReply parseAiReply(String raw) {
  final commands = <Map<String, dynamic>>[];
  String? parseError;
  final text = raw.replaceAllMapped(_fencePattern, (m) {
    final lang = m.group(1)?.toLowerCase() ?? '';
    final body = m.group(2) ?? '';
    // 语言标记给了但不是 json 系（```dart / ```text 等）就直接放过
    if (lang.isNotEmpty && lang != 'json' && lang != 'jsonc') return m.group(0)!;
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      // 看着像指令块（里面出现了 commands）却解析失败，记一条提示
      if (lang == 'json' || body.contains('"commands"')) {
        parseError ??= 'AI 回复里的指令代码块不是合法 JSON，已忽略';
      }
      return m.group(0)!;
    }
    if (decoded is! Map<String, dynamic>) return m.group(0)!;
    final list = decoded['commands'];
    if (list is! List) return m.group(0)!;
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        commands.add(Map<String, dynamic>.of(item));
      }
    }
    // 指令块不展示给用户：用空串替换掉整块（含围栏）
    return '';
  });

  // 摘掉块之后可能出现连续空行，压成最多一个；首尾空白去掉
  final cleaned = text
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return AiReply(
    text: cleaned,
    commands: commands,
    commandParseError: parseError,
  );
}

/// 指令是否破坏性（读 CommandRegistry，不另写黑名单）
bool isDestructiveCommand(Map<String, dynamic> command) =>
    cmd.isDestructiveCommand(command);

/// 指令的人话描述（与 AI 桥待确认列表同一份实现）
String describeAiCommand(Map<String, dynamic> command) =>
    cmd.describeCommand(command);

// ---------- 课表上下文 ----------

/// 组装发给模型的课表上下文（发送时现取，不缓存——课表刚被改过也要说对话）
///
/// [courses] 由调用方传「本周有效课程」（周视图同款口径，已应用单次调课）；
/// 本函数不再按周次过滤一次，避免与调用方的口径打架。
///
/// [allCourses] 可选：当前学期**全部**课程（不经周次过滤），非空时上下文会多出
/// 一节【全部课程（定位用）】——模型要定位已有课程（set_course_color /
/// set_course_remark / add_exam）时从这里原样复制 courseName，避免它自己编名字。
/// 为兼容桥等其他调用方，本参数可选，不传（null/空）时不输出这一节。
String buildTimetableContext({
  required Semester? semester,
  required List<Course> courses,
  required List<Note> notes,
  required DateTime now,
  List<Course>? allCourses,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final buf = StringBuffer();

  if (semester == null) {
    buf.writeln('【学期】还没设置当前学期（请提示用户先去「设置 → 学期管理」建一个）');
  } else {
    final week = WeekCalc.currentWeek(semester.startDateParsed, now);
    final parity = WeekCalc.parityLabel(week, totalWeeks: semester.totalWeeks);
    final weekText = week <= 0
        ? '还没开学（开学日期 ${semester.startDate}）'
        : '第 $week 周${parity == null ? '' : '（$parity）'}';
    buf.writeln(
      '【学期】${semester.name}；共 ${semester.totalWeeks} 周；'
      '开学日期 ${semester.startDate}；当前 $weekText',
    );
  }
  buf.writeln(
    '【今天】${_dateKey(today)} 周${_weekdayName(today.weekday)}；'
    '明天 ${_dateKey(today.add(const Duration(days: 1)))} '
    '周${_weekdayName(today.add(const Duration(days: 1)).weekday)}',
  );

  buf.writeln('【本周课程】');
  if (courses.isEmpty) {
    buf.writeln('（本周没有课程）');
  } else {
    final sorted = [...courses]..sort((a, b) {
        final d = a.dayOfWeek.compareTo(b.dayOfWeek);
        return d != 0 ? d : a.startSection.compareTo(b.startSection);
      });
    for (final c in sorted) {
      buf.writeln('- ${_courseLine(c)}');
    }
  }

  if (allCourses != null && allCourses.isNotEmpty) {
    buf.writeln(buildCourseListContext(allCourses));
    buf.writeln();
  }

  final exams = _upcomingExams(courses, today);
  buf.writeln('【临近考试】');
  if (exams.isEmpty) {
    buf.writeln('（没有已登记的考试）');
  } else {
    for (final c in exams) {
      final d = DateTime.fromMillisecondsSinceEpoch(c.examDate!);
      final days = ExamCountdown.daysUntil(d, today);
      buf.writeln(
        '- 《${c.name}》：${_dateKey(d)}'
        '${_hasTime(c.examDate!) ? ' ${_hhmm(c.examDate!)}' : ''}'
        '（${ExamCountdown.countdownText(days)}）',
      );
    }
  }

  // 日期备注（全部，不只是今明两天）：每条带 id / 日期 / 内容，
  // 让模型能按 id 精确删除（delete_note 支持 id / date / date+关键词）
  buf.writeln('【日期备注（按天，只对某一天有效）】');
  final dayNotes = [
    for (final n in notes)
      if (n.content.trim().isNotEmpty) n,
  ]..sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : (a.id ?? 0).compareTo(b.id ?? 0);
    });
  if (dayNotes.isEmpty) {
    buf.writeln('（无）');
  } else {
    for (final n in dayNotes) {
      buf.writeln('- [id=${n.id}] ${n.date} ${n.content.trim()}');
    }
  }

  // 课程备注（挂在课程上、长期有效）：明确与日期备注区分开
  buf.writeln('【课程备注（挂在课程上，长期有效）】');
  final courseNotes = [
    for (final c in courses)
      if (c.note != null && c.note!.trim().isNotEmpty) c,
  ];
  if (courseNotes.isEmpty) {
    buf.writeln('（无）');
  } else {
    for (final c in courseNotes) {
      final idPart = c.id == null ? '' : '（id=${c.id}）';
      buf.writeln('- 《${c.name}》$idPart：${c.note!.trim()}');
    }
  }

  return buf.toString().trim();
}

/// 【全部课程（定位用）】清单（2.0.6 第 3 节）：每行《课程名》（id 编号、周X 第A-B节），
/// 按课程名排序。供模型在执行「定位已有课程」的指令时原样复制 courseName，
/// 也给纠错重试提示复用（同一份格式，避免两处漂移）。
String buildCourseListContext(List<Course> allCourses) {
  final buf = StringBuffer()..writeln('【全部课程（定位用）】');
  if (allCourses.isEmpty) {
    buf.writeln('（当前学期没有课程）');
  } else {
    final sorted = [...allCourses]..sort((a, b) => a.name.compareTo(b.name));
    for (final c in sorted) {
      final idPart = c.id == null ? '' : 'id ${c.id}、';
      buf.writeln(
        '- 《${c.name}》（${idPart}周${_weekdayName(c.dayOfWeek)} '
        '第${_sectionText(c.startSection, c.endSection)}节）',
      );
    }
  }
  return buf.toString().trim();
}

/// 单门课程一行：「周一 第1-2节 高等数学｜张三｜A101｜第1-16周」
///
/// 课程备注不再写进课程行（2.0.5 起单列「课程备注」段落，明确与日期备注区分，
/// 见 buildTimetableContext）。
String _courseLine(Course c) {
  final parts = <String>[
    '周${_weekdayName(c.dayOfWeek)} 第${_sectionText(c.startSection, c.endSection)}节 ${c.name}',
  ];
  final teacher = c.teacher?.trim();
  if (teacher != null && teacher.isNotEmpty) parts.add('教师：$teacher');
  final room = c.classroom?.trim();
  if (room != null && room.isNotEmpty) parts.add('教室：$room');
  if (c.weeks.isNotEmpty) parts.add('第${_compactWeeks(c.weeks)}周');
  if (c.weekType == 1) parts.add('仅单周');
  if (c.weekType == 2) parts.add('仅双周');
  return parts.join('｜');
}

/// 临近考试：今天及以后（含今天），按日期升序，最多 5 门
List<Course> _upcomingExams(List<Course> courses, DateTime today) {
  final list = [
    for (final c in courses)
      if (c.examDate != null && !_beforeDay(c.examDate!, today)) c,
  ]..sort((a, b) => a.examDate!.compareTo(b.examDate!));
  return list.take(5).toList();
}

bool _beforeDay(int stamp, DateTime day) =>
    DateTime.fromMillisecondsSinceEpoch(stamp).isBefore(day);

bool _hasTime(int stamp) {
  final t = DateTime.fromMillisecondsSinceEpoch(stamp);
  return t.hour != 0 || t.minute != 0;
}

String _hhmm(int stamp) {
  final t = DateTime.fromMillisecondsSinceEpoch(stamp);
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

// ---------- 系统提示 ----------

/// 系统提示：身份 + 课表上下文 + 动手能力的协议约定
///
/// 约定要点（与 AI 桥同一套指令参数，见 command_executor.dart）：
/// - 只在用户**明确要求改动课表**时才附指令块，纯问答不要带；
/// - 指令块必须是 fenced json（```json … ```），格式 {"commands":[...]}；
/// - 一次回复里可以有 0 或多条指令；删除类会单独让用户确认。
String buildSystemPrompt(String timetableContext) => '''
你是「小马课表」App 的内置助手，用中文、简短直接地回答关于课表的问题。
下面是用户当前的课表数据（每次提问都会重新取，以它为准，不要凭常识编造课程）：

$timetableContext

回答规则：
1. 课表相关的问题只依据上面的数据回答；数据里没有的就说没有。
2. 用户问「明天/周几有什么课」「哪天有空」时，按上面的周次与星期推算，并说明依据（第几周、单双周）。
3. 不要复述整张课表，挑相关的说。
4. 备注分两类：「课程备注」挂在某门课上、长期有效；「日期备注」只对某一天有效。
   用户说「给 XX 课加备注」默认指课程备注，用 set_course_remark；只有说「某天加个备注」
   才用 add_note。

需要改动课表时（用户明确要求新增课程、改颜色、改课程备注、加日期备注、删备注、设考试日期），
在正常回复**之外**附一个 json 代码块，格式如下（不要加别的说明在块里）：

```json
{"commands": [{"type": "add_note", "date": "2026-10-23", "content": "交作业"}]}
```

可用指令：
- add_course：name、dayOfWeek(1=周一)、startSection、endSection、weeks("1-16" 或数组)、teacher?、classroom?、color?
- set_course_color：courseId 或 courseName、color("#RRGGBB")
- set_course_remark：courseId 或 courseName、remark（给课程加/改课程备注，空字符串表示清除备注）
- add_note：content、date?（默认今天，yyyy-MM-dd；这是「某一天」的日期备注）
- delete_note：id（备注 id）或 date（删当天全部备注）或 date+content（删当天含关键词备注），删除类，用户需逐条确认
- add_exam：courseId 或 courseName、date(yyyy-MM-dd)、time?("HH:mm")

set_course_remark 示例：{"type":"set_course_remark","courseName":"药理学实验","remark":"二楼"}
清除备注：{"type":"set_course_remark","courseName":"药理学实验","remark":""}
硬规矩：courseName 必须从上面的【全部课程（定位用）】清单里原样复制，不要改字、不要用简称、不要自己编 id。

这些指令不会立刻执行：App 会把它们渲染成确认卡片，用户点了「执行」才生效。
所以你只管给出指令，并在正文里说明你打算做什么。''';

// ---------- 公共小工具 ----------

/// 日期键 yyyy-MM-dd
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

String _sectionText(int start, int end) => start == end ? '$start' : '$start-$end';

/// 连续周次压成区间：「1,2,3,5」→「1-3,5」（周次可能乱序，先排序）
String _compactWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = [...weeks]..sort();
  final out = <String>[];
  var start = sorted.first;
  var prev = sorted.first;
  for (final w in sorted.skip(1)) {
    if (w == prev + 1) {
      prev = w;
      continue;
    }
    out.add(start == prev ? '$start' : '$start-$prev');
    start = w;
    prev = w;
  }
  out.add(start == prev ? '$start' : '$start-$prev');
  return out.join(',');
}

const _weekdayNames = ['', '一', '二', '三', '四', '五', '六', '日'];

String _weekdayName(int weekday) =>
    weekday >= 1 && weekday <= 7 ? _weekdayNames[weekday] : '$weekday';

// ---------- 纠错重试（2.0.6 第 4 节） ----------

/// 失败是否属于「参数类」（值得让模型照着课程名单纠错重试一次的那类中文报错）。
///
/// 认执行器里的这几类中文报错：缺少参数 / 缺少定位参数 / 没有名为…的课程 /
/// 没有 id 为…的课程 / 课程名对上多门课 / 不支持的指令类型。
bool isParameterFailure(String message) {
  if (message.contains('缺少参数') || message.contains('缺少定位参数')) {
    return true;
  }
  if (message.contains('没有名为') || message.contains('没有 id 为')) {
    return true;
  }
  if (message.contains('能对上多门课')) return true;
  if (message.contains('不支持的指令类型')) return true;
  return false;
}

/// 一轮里执行完指令后，是否应该自动纠错重试一次。
///
/// [alreadyRetried] 为 true（本轮已重试过）时一律不再重试——硬上限一次，
/// 防死循环、防刷接口。纯问答不触发（执行器只在有指令时被调），执行全成功不触发。
bool shouldRetryForParameterError(
  List<CommandResult> results, {
  required bool alreadyRetried,
}) {
  if (alreadyRetried) return false;
  return results.any((r) => !r.success && isParameterFailure(r.message));
}

/// 纠错重试时的提示（作为用户消息发给模型）：把用户原话、失败指令、报错原文、
/// 课程名单打包，要求模型只回改好的指令（沿用现有指令块格式）。
String buildCorrectionPrompt({
  required String userText,
  required List<Map<String, dynamic>> failedCommands,
  required List<String> failedMessages,
  required String courseList,
}) {
  final buf = StringBuffer();
  buf.writeln(
    '你刚才给出的指令没有执行成功。请照着下面的课程名单改好，'
    '然后只回一个 json 指令块（格式 {"commands":[...]}），不要加别的说明。',
  );
  buf.writeln();
  buf.writeln('用户原话：');
  buf.writeln(userText);
  buf.writeln();
  buf.writeln('你发的指令（失败）：');
  buf.writeln(const JsonEncoder.withIndent('  ').convert(failedCommands));
  buf.writeln();
  buf.writeln('执行器报错：');
  for (final m in failedMessages) {
    buf.writeln('- $m');
  }
  buf.writeln();
  buf.writeln('全部课程（courseName 从这里原样复制）：');
  buf.writeln(courseList);
  return buf.toString().trim();
}
