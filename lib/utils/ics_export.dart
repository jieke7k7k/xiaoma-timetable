import '../models/course.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import 'week_calc.dart';

/// ICS 导出（阶段五）：把一个学期的课表导出为标准 .ics 日历文本
///
/// 周次展开方案选型（二选一里选了「单次事件」）：
/// - **逐周展开为独立 VEVENT**（本实现）：一个 20 周 × 10 门课的学期约
///   200 个事件，体积完全可接受；实现简单、无歧义，任何日历 App 都能正确
///   导入，本 App 自己的 IcsParser 也能直接读回来。
/// - RRULE 按周重复：事件数少，但 FREQ=WEEKLY + 学期结束边界的组合在不同
///   日历软件里兼容性参差，还要处理 INTERVAL/UNTIL 时区细节，不值得。
///
/// 时间格式用「floating local time」（YYYYMMDDTHHMMSS，无 Z 后缀、无 TZID）：
/// 大学生课表只关心本地时间，floating 是最不容易产生时区偏差的表示法。
///
/// 已知取舍：不做 RFC 5545 的 75 字节行折叠——主流日历 App 都接受长行，
/// 本项目自己的解析器也按整行读取；极端超长课程名暂不兼容老古董软件。
class IcsExporter {
  IcsExporter._();

  /// 生成完整 ICS 文本。CRLF 行尾（RFC 5545 要求）。
  ///
  /// [semester] 提供开学日期（周次 → 具体日期的换算基准）与日历名；
  /// [courses] 为该学期全部课程；[slots] 为节次时间表；
  /// 节次时间缺失的课程无法给出具体时刻，跳过并计入 [IcsExportResult.skippedCount]。
  static IcsExportResult build({
    required Semester semester,
    required List<Course> courses,
    required List<TimeSlot> slots,
    DateTime? now,
  }) {
    final slotBySection = {for (final s in slots) s.section: s};
    final stamp = _toUtcStamp(now ?? DateTime.now());
    final semesterStart = DateTime.parse(semester.startDate);

    // 按星期几 + 起始节次排序，让导出文件里事件顺序稳定可读
    final sorted = [...courses]..sort((a, b) {
        final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
        if (byDay != 0) return byDay;
        return a.startSection.compareTo(b.startSection);
      });

    final buffer = StringBuffer();
    buffer.write('BEGIN:VCALENDAR\r\n');
    buffer.write('VERSION:2.0\r\n');
    buffer.write('PRODID:-//simple-timetable//jiankebiao 1.0//CN\r\n');
    buffer.write('CALSCALE:GREGORIAN\r\n');
    // X-WR-CALNAME 为事实标准扩展：多数日历 App 会用它作为导入后的日历名
    buffer.write('X-WR-CALNAME:${_escapeText(semester.name)}\r\n');

    var eventCount = 0;
    var skippedCount = 0;
    for (final c in sorted) {
      // 去重排序周次；isActiveInWeek 再过滤一次单双周——周次数组是权威数据，
      // 但 weekType 字段为兼容旧数据保留，两道过滤保证与周视图显示一致
      final weeks = {...c.weeks}.toList()..sort();
      for (final week in weeks) {
        if (!c.isActiveInWeek(week)) continue;
        final startSlot = slotBySection[c.startSection];
        final endSlot = slotBySection[c.endSection];
        if (startSlot == null || endSlot == null) {
          // 节次时间缺失（如课程引用了被删掉的节次号），无法给出时刻，跳过
          skippedCount++;
          continue;
        }
        // 第 week 周该课程星期几对应的日期（weekDatesOf 返回周一~周日）
        final day =
            WeekCalc.weekDatesOf(semesterStart, week)[c.dayOfWeek - 1];

        buffer.write('BEGIN:VEVENT\r\n');
        buffer.write(
            'UID:st-${c.id ?? 'new'}-${c.dayOfWeek}-${c.startSection}'
            '-w$week-$stamp@simple-timetable\r\n');
        buffer.write('DTSTAMP:$stamp\r\n');
        buffer.write('SUMMARY:${_escapeText(c.name)}\r\n');
        if (c.classroom != null && c.classroom!.isNotEmpty) {
          buffer.write('LOCATION:${_escapeText(c.classroom!)}\r\n');
        }
        // 教师与备注放进 DESCRIPTION：本 App 的 IcsParser 也从 DESCRIPTION 启发式提取教师
        final description = [
          if (c.teacher != null && c.teacher!.isNotEmpty) '教师：${c.teacher}',
          if (c.note != null && c.note!.isNotEmpty) c.note!,
        ].join('\n');
        if (description.isNotEmpty) {
          buffer.write('DESCRIPTION:${_escapeText(description)}\r\n');
        }
        buffer.write('DTSTART:${_formatLocal(day, startSlot.startTime)}\r\n');
        buffer.write('DTEND:${_formatLocal(day, endSlot.endTime)}\r\n');
        buffer.write('END:VEVENT\r\n');
        eventCount++;
      }
    }
    buffer.write('END:VCALENDAR\r\n');

    return IcsExportResult(
      content: buffer.toString(),
      eventCount: eventCount,
      skippedCount: skippedCount,
    );
  }

  /// 日期 + 「HH:mm」→ floating local time，如 20260907T080000
  static String _formatLocal(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${day.year}${two(day.month)}${two(day.day)}'
        'T${two(h)}${two(m)}00';
  }

  /// DTSTAMP 要求 UTC：本地时间转 UTC 后拼 YYYYMMDDTHHMMSSZ
  static String _toUtcStamp(DateTime now) {
    final utc = now.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  /// RFC 5545 TEXT 值转义：反斜杠、分号、逗号、换行。
  /// 必须先转义反斜杠本身，否则会把后续生成的转义符又吃掉。
  static String _escapeText(String raw) => raw
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');
}

/// ICS 构建结果：content 为完整文件文本，另附统计供 UI 提示
/// （skippedCount > 0 时提醒用户有课程因节次时间缺失未导出）
class IcsExportResult {
  const IcsExportResult({
    required this.content,
    required this.eventCount,
    required this.skippedCount,
  });

  final String content;
  final int eventCount;
  final int skippedCount;
}
