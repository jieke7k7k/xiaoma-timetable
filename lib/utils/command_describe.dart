import '../services/command_executor.dart';

/// 结构化指令的「人话描述」（纯函数，AI 确认卡片与 AI 桥待确认列表共用）
///
/// 一期五条指令（见 [CommandRegistry]）在这里各有一句中文描述；将来新增指令
/// 忘了登记时走最后的兜底分支，用户看到的仍是「执行 xxx 指令」而不是原始 JSON。
///
/// **为什么要单独一个文件**：内置 AI 的确认卡片和 AI 桥的待确认队列都要把指令
/// 说成人话，两处各写一份迟早会漂移（一个改了描述另一个没改）。是否破坏性一律
/// 读 [CommandRegistry.destructiveOf]，不在这里另写黑名单。
String describeCommand(
  Map<String, dynamic> command, {
  String? detail,
}) {
  final type = command['type']?.toString().trim() ?? '';
  final note = detail?.trim();
  final hasNote = note != null && note.isNotEmpty;
  switch (type) {
    case 'add_course':
      return '新增课程${_courseSummary(command)}';
    case 'set_course_color':
      return '把${_targetName(command)}的颜色改为 ${_colorText(command['colorValue'] ?? command['color'])}';
    case 'add_note':
      final date = _str(command['date']);
      final content = _str(command['content']);
      if (date.isEmpty) return '新增备注：$content';
      return '新增 $date 的备注：$content';
    case 'delete_note':
      // 桥侧会把「日期 + 内容」作为 detail 传进来（查库得到），查不到时按
      // id / date / 关键词退化成对应的定位描述
      if (hasNote) return '删除备注 $note';
      final id = command['id'] ?? command['noteId'];
      if (id != null) return '删除备注 id=$id';
      final date = _str(command['date']);
      final keyword = _str(command['content'] ?? command['keyword']);
      if (date.isNotEmpty && keyword.isNotEmpty) {
        return '删除 $date 里含「$keyword」的备注';
      }
      if (date.isNotEmpty) return '删除 $date 的全部备注';
      return '删除备注（未指定定位方式）';
    case 'set_course_remark':
      final remark = _str(command['remark']);
      final target = _targetName(command);
      return remark.isEmpty ? '清除$target的课程备注' : '把$target的课程备注改为：$remark';
    case 'add_exam':
      return '把${_targetName(command)}的考试日期设为 ${_examDateText(command)}';
    default:
      return hasNote ? note : '执行 ${type.isEmpty ? '未知' : type} 指令';
  }
}

/// 该指令是否具有破坏性（删除/覆盖类为 true，供确认策略读取）
bool isDestructiveCommand(Map<String, dynamic> command) =>
    CommandRegistry.destructiveOf(command['type']?.toString().trim() ?? '');

/// add_course 的摘要：「《高等数学》：周一 第1-2节，第1-16周，A101（张三）」
String _courseSummary(Map<String, dynamic> cmd) {
  final name = _str(cmd['name']);
  final title = name.isEmpty ? '未命名课程' : '《$name》';
  final parts = <String>[];
  final day = _int(cmd['dayOfWeek']);
  if (day != null && day >= 1 && day <= 7) parts.add('周${_weekdayNames[day]}');
  final start = _int(cmd['startSection']);
  final end = _int(cmd['endSection']) ?? start;
  if (start != null) {
    parts.add(start == end ? '第$start节' : '第$start-${end ?? start}节');
  }
  final weeks = _weeksText(cmd['weeks']);
  if (weeks.isNotEmpty) parts.add(weeks);
  final classroom = _str(cmd['classroom']);
  if (classroom.isNotEmpty) parts.add(classroom);
  final teacher = _str(cmd['teacher']);
  if (teacher.isNotEmpty) parts.add('（$teacher）');
  if (parts.isEmpty) return title;
  return '$title：${parts.join('，')}';
}

/// 定位目标的名字（courseName 优先，其次「id 为 N 的课程」）
String _targetName(Map<String, dynamic> cmd) {
  final name = _str(cmd['courseName'] ?? cmd['name']);
  if (name.isNotEmpty) return '《$name》';
  final id = _int(cmd['courseId'] ?? cmd['id']);
  return id == null ? '这门课' : 'id 为 $id 的课程';
}

/// 周次字段：数组压缩成「第1-8,10周」，字符串原样带过（可能是「1-8单周」）
String _weeksText(Object? raw) {
  if (raw == null) return '';
  if (raw is List) {
    final weeks = <int>{
      for (final e in raw)
        if (e is int)
          e
        else if (e is num)
          e.round()
        else
          int.tryParse('$e') ?? 0,
    }..remove(0);
    if (weeks.isEmpty) return '';
    final sorted = weeks.toList()..sort();
    return '第${_compactWeeks(sorted)}周';
  }
  final s = raw.toString().trim();
  return s.isEmpty ? '' : '第$s周';
}

/// 连续周次压成区间：「1,2,3,5」→「1-3,5」
String _compactWeeks(List<int> sorted) {
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

/// 考试日期：优先 yyyy-MM-dd 字符串（可带 HH:mm），其次毫秒时间戳
String _examDateText(Map<String, dynamic> cmd) {
  final raw = _str(cmd['date']);
  if (raw.isNotEmpty) {
    final time = _str(cmd['time']);
    return time.isEmpty ? raw : '$raw $time';
  }
  final stamp = _int(cmd['examDate']);
  if (stamp == null) return '未指定日期';
  final t = DateTime.fromMillisecondsSinceEpoch(stamp);
  String two(int v) => v.toString().padLeft(2, '0');
  final date = '${t.year}-${two(t.month)}-${two(t.day)}';
  if (t.hour == 0 && t.minute == 0) return date;
  return '$date ${two(t.hour)}:${two(t.minute)}';
}

/// 颜色：int 直接转 #RRGGBB，字符串（#RRGGBB / 0xAARRGGBB）去掉前缀后取低 6 位
String _colorText(Object? raw) {
  if (raw == null) return '# 未指定';
  if (raw is int) return '#${(raw & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  var s = raw.toString().trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
  if (s.length > 6) s = s.substring(s.length - 6);
  return '#${s.toUpperCase()}';
}

String _str(Object? v) => v == null ? '' : v.toString().trim();

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

const _weekdayNames = ['', '一', '二', '三', '四', '五', '六', '日'];
