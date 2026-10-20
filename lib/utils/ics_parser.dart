import '../models/course.dart';
import '../models/time_slot.dart';
import 'morandi_palette.dart';
import 'week_calc.dart';

/// ICS 日历文件解析器
///
/// 解析 VEVENT（SUMMARY/LOCATION/DESCRIPTION/RRULE/DTSTART/DTEND），
/// 自动推算对应的星期、节次、周次，生成草稿课程。
/// 解析失败的条目单独汇总，不中断整体流程。
class IcsParser {
  IcsParser._();

  /// 解析 ICS 文本
  ///
  /// [semesterStart]：当前学期开学日期（用于周次推算）
  /// [slots]：节次时间表（用于节次匹配）
  static IcsParseResult parse(
    String icsContent, {
    required DateTime semesterStart,
    required List<TimeSlot> slots,
  }) {
    final courses = <Course>[];
    final errors = <String>[];
    final timeBlocks = <IcsTimeBlock>[];

    // 按 VEVENT 切块
    final eventBlocks = _extractEvents(icsContent);
    if (eventBlocks.isEmpty) {
      errors.add('未在文件中找到任何日历事件（VEVENT）');
      return IcsParseResult(courses: courses, errors: errors);
    }

    for (var i = 0; i < eventBlocks.length; i++) {
      final block = eventBlocks[i];
      try {
        final parsed = _parseEvent(block, semesterStart, slots, i + 1);
        if (parsed != null) {
          courses.add(parsed.course);
          timeBlocks.add(parsed.timeBlock);
        }
      } catch (e) {
        errors.add('第 ${i + 1} 条事件解析失败：$e');
      }
    }

    return IcsParseResult(
        courses: courses, errors: errors, timeBlocks: timeBlocks);
  }

  static List<String> _extractEvents(String content) {
    final blocks = <String>[];
    final lines = content.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    var inEvent = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toUpperCase() == 'BEGIN:VEVENT') {
        inEvent = true;
        buffer.clear();
      } else if (trimmed.toUpperCase() == 'END:VEVENT') {
        if (inEvent) blocks.add(buffer.toString());
        inEvent = false;
      } else if (inEvent) {
        buffer.writeln(line);
      }
    }
    return blocks;
  }

  static ({Course course, IcsTimeBlock timeBlock})? _parseEvent(
    String block,
    DateTime semesterStart,
    List<TimeSlot> slots,
    int index,
  ) {
    final props = _parseProperties(block);

    final summary = props['SUMMARY'];
    if (summary == null || summary.isEmpty) {
      throw '缺少 SUMMARY（课程名）';
    }
    final dtStart = props['DTSTART'];
    if (dtStart == null) {
      throw '缺少 DTSTART（开始时间）';
    }

    // 解析开始时间
    final startDateTime = _parseDateTime(dtStart);
    if (startDateTime == null) {
      throw 'DTSTART 格式无法识别：$dtStart';
    }
    final dayOfWeek = startDateTime.weekday; // 1~7

    // 节次匹配
    int startSection;
    int endSection;
    final dtEnd = props['DTEND'];
    final endDateTime = dtEnd != null ? _parseDateTime(dtEnd) : null;
    final startMinutes = startDateTime.hour * 60 + startDateTime.minute;
    final endMinutes = endDateTime != null
        ? endDateTime.hour * 60 + endDateTime.minute
        : startMinutes + 45;

    startSection = _matchSection(slots, startMinutes, isStart: true);
    endSection = _matchSection(slots, endMinutes, isStart: false);
    if (endSection < startSection) endSection = startSection;

    // 周次推算
    final startWeek =
        WeekCalc.currentWeek(semesterStart, startDateTime);
    if (startWeek <= 0) {
      throw '上课时间早于开学日期，无法推算周次';
    }
    List<int> weeks;
    final rrule = props['RRULE'];
    if (rrule != null && rrule.toUpperCase().contains('COUNT=')) {
      final count = int.tryParse(
          RegExp(r'COUNT=(\d+)', caseSensitive: false).firstMatch(rrule)?.group(1) ?? '');
      final n = count ?? 1;
      weeks = [for (var w = 0; w < n; w++) startWeek + w];
    } else if (rrule != null && rrule.toUpperCase().contains('UNTIL=')) {
      final untilStr = RegExp(r'UNTIL=([^;]+)', caseSensitive: false)
          .firstMatch(rrule)
          ?.group(1);
      final until = untilStr != null ? _parseDateTime(untilStr) : null;
      final endWeek = until != null
          ? WeekCalc.currentWeek(semesterStart, until)
          : startWeek + 15;
      weeks = [for (var w = startWeek; w <= endWeek; w++) w];
    } else {
      // 无 RRULE：仅一次，或按默认到学期结束
      weeks = [startWeek];
    }

    // 课程名/教室/老师
    final location = (props['LOCATION'] ?? '').trim();
    final description = props['DESCRIPTION'] ?? '';

    // 作息校准块的节次区间：优先从 DESCRIPTION 的「第 X - Y 节」解析，
    // 解析不到则回退为按钟点匹配出的 startSection/endSection（与课程一致）
    final descRange = _extractSectionRange(description);
    final blockStartSection = descRange?.$1 ?? startSection;
    final blockEndSection = descRange?.$2 ?? endSection;

    // WakeUp 风格结构化 DESCRIPTION：首行「第 X - Y 节」、次行教室、
    // 第三行老师（老师行可缺省）；LOCATION 则是「教室 老师」拼在一起。
    final wakeupLines = _wakeupDescLines(description, hasSectionLine: descRange != null);
    final descClassroom = wakeupLines.length >= 2 ? wakeupLines[1] : null;
    final descTeacher = wakeupLines.length >= 3 ? wakeupLines[2] : null;

    final teacher = _extractTeacher(description) ?? descTeacher;

    // 教室：优先 DESCRIPTION 的教室行；否则取 LOCATION，
    // 若 LOCATION 末尾拼着已识别出的老师名则剥掉
    String? classroom = descClassroom;
    if (classroom == null && location.isNotEmpty) {
      var loc = location;
      if (teacher != null && teacher.isNotEmpty && loc.endsWith(teacher)) {
        loc = loc.substring(0, loc.length - teacher.length).trim();
      }
      classroom = loc.isEmpty ? null : loc;
    }

    final timeBlock = IcsTimeBlock(
      startSection: blockStartSection,
      endSection: blockEndSection,
      startTime: _formatHm(startDateTime),
      // 缺失 DTEND 时，用该块结束节次现有作息的下课时间兜底；
      // 找不到对应节次则留空（校准阶段会跳过非法/空值）
      endTime: endDateTime != null
          ? _formatHm(endDateTime)
          : _slotEndTime(slots, blockEndSection),
    );

    final course = Course(
      semesterId: 0,
      name: summary,
      teacher: teacher,
      classroom: classroom,
      colorValue: MorandiPalette.colors[index % MorandiPalette.colors.length],
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
    );

    return (course: course, timeBlock: timeBlock);
  }

  /// 解析属性块为 Map（KEY -> VALUE，忽略行折叠场景的极端情况）
  static Map<String, String> _parseProperties(String block) {
    final map = <String, String>{};
    final lines = block.split(RegExp(r'\r?\n'));
    var inAlarm = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 跳过 VALARM 子块：其 DESCRIPTION 是提醒文案（如「课程名@教室」），
      // 若混入会覆盖事件自身的同名属性
      final upper = trimmed.toUpperCase();
      if (upper == 'BEGIN:VALARM') {
        inAlarm = true;
        continue;
      }
      if (upper == 'END:VALARM') {
        inAlarm = false;
        continue;
      }
      if (inAlarm) continue;
      final idx = trimmed.indexOf(':');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).toUpperCase();
      // 属性可能带参数，如 DTSTART;TZID=...:，取第一个分号前的主键
      final mainKey = key.split(';').first;
      final value = trimmed.substring(idx + 1);
      map[mainKey] = value;
    }
    return map;
  }

  /// 把 DESCRIPTION 按 ICS 转义还原后逐行拆开。
  ///
  /// 仅当首行是「第 X - Y 节」节次行（[hasSectionLine]）时才认为
  /// 后续行是 WakeUp 风格的「教室 / 老师」结构，否则返回空列表。
  static List<String> _wakeupDescLines(String description,
      {required bool hasSectionLine}) {
    if (!hasSectionLine) return const [];
    final unescaped = description
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';');
    final lines = unescaped
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // 首行必须是节次行才启用结构化拆分，避免误伤其他格式的描述
    if (lines.length < 2 || !lines.first.contains('节')) return const [];
    return lines;
  }

  static DateTime? _parseDateTime(String raw) {
    // 支持 20260914T140000 / 20260914T140000Z / 2026-09-14 14:00 等
    final cleaned = raw
        .replaceAll('Z', '')
        .replaceAll('-', '')
        .replaceAll(':', '')
        .replaceAll(' ', '')
        .trim();
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T)?(\d{2})(\d{2})?(\d{2})?')
        .firstMatch(cleaned);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = match.group(5) != null ? int.parse(match.group(5)!) : 0;
    return DateTime(year, month, day, hour, minute);
  }

  static int _matchSection(List<TimeSlot> slots, int minutes,
      {required bool isStart}) {
    if (slots.isEmpty) return 1;
    for (final slot in slots) {
      final start = _toMinutes(slot.startTime);
      final end = _toMinutes(slot.endTime);
      if (isStart) {
        if (minutes >= start && minutes < end) return slot.section;
      } else {
        if (minutes > start && minutes <= end) return slot.section;
      }
    }
    // 找不到精确匹配，退回最接近的节次
    int best = 1;
    int bestDiff = 1 << 30;
    for (final slot in slots) {
      final start = _toMinutes(slot.startTime);
      final diff = (minutes - start).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = slot.section;
      }
    }
    return best;
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  static String? _extractTeacher(String description) {
    // 启发式：描述里常见「教师:XXX」或「老师:XXX」或「讲师:XXX」
    final m = RegExp(r'(?:教师|老师|讲师|任课教师)\s*[:：]\s*([^\n;,，]+)')
        .firstMatch(description);
    return m?.group(1)?.trim();
  }

  /// 从 DESCRIPTION 文本提取节次区间，如「第 1 - 3 节」「第3节」；
  /// 解析不到返回 null（与 heuristic_parser 的节次区间正则可互换）
  static (int, int)? _extractSectionRange(String description) {
    final range = RegExp(r'第?\s*(\d{1,2})\s*[-—~至]\s*(\d{1,2})\s*节')
        .firstMatch(description);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      return (a, b);
    }
    final single = RegExp(r'第?\s*(\d{1,2})\s*节').firstMatch(description);
    if (single != null) {
      final a = int.parse(single.group(1)!);
      return (a, a);
    }
    return null;
  }

  /// 格式化为 "HH:mm"（与 TimeSlot.startTime/endTime 一致）
  static String _formatHm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';

  /// 取某节次现有作息的下课时间；找不到返回空串
  static String _slotEndTime(List<TimeSlot> slots, int section) {
    for (final s in slots) {
      if (s.section == section) return s.endTime;
    }
    return '';
  }
}

/// ICS 事件解析出的作息校准块
///
/// 记录某门课对应的节次区间（startSection~endSection）与该事件的
/// 真实起止时刻（DTSTART/DTEND 的时分），供 SlotCalibrator 校准作息表。
class IcsTimeBlock {
  const IcsTimeBlock({
    required this.startSection,
    required this.endSection,
    required this.startTime,
    required this.endTime,
  });

  final int startSection;
  final int endSection;
  final String startTime; // "HH:mm"
  final String endTime; // "HH:mm"；缺失 DTEND 且无兜底时为空串
}

/// ICS 解析结果
class IcsParseResult {
  const IcsParseResult({
    required this.courses,
    required this.errors,
    this.timeBlocks = const [],
  });

  final List<Course> courses;
  final List<String> errors;

  /// 每个成功解析事件产出的作息校准块（顺序与 courses 对应）
  final List<IcsTimeBlock> timeBlocks;
}
