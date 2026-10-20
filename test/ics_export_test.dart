import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ics_export.dart';

/// ICS 导出测试：纯文本构建逻辑，不碰平台通道
void main() {
  // 默认学期 2026-09-07 恰为周一（与生产首启内置学期一致，便于手算日期）
  const semester = Semester(
      id: 1, name: '2026 秋季学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
  ];

  Course course({
    List<int> weeks = const [1, 2, 3],
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 2,
    String? classroom = 'A101',
    int weekType = 0,
    String? teacher,
    String? note,
  }) =>
      Course(
        id: 7,
        semesterId: 1,
        name: '高等数学',
        teacher: teacher,
        note: note,
        classroom: classroom,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        weeks: weeks,
        weekType: weekType,
      );

  IcsExportResult build(List<Course> courses) => IcsExporter.build(
        semester: semester,
        courses: courses,
        slots: slots,
        now: DateTime(2026, 10, 15, 12, 30),
      );

  test('周次逐周展开为独立 VEVENT（不用 RRULE 的既定方案）', () {
    final r = build([course(weeks: [1, 2, 3])]);
    expect(r.eventCount, 3);
    expect(r.skippedCount, 0);
    expect('BEGIN:VEVENT'.allMatches(r.content).length, 3);
    expect('END:VEVENT'.allMatches(r.content).length, 3);
  });

  test('第 1 周周一 1-2 节的 DTSTART/DTEND 正确（2026-09-07 是周一）', () {
    final r = build([course(weeks: const [1])]);
    expect(r.content, contains('DTSTART:20260907T080000'));
    // DTEND 取结束节次的下课时间（第 2 节 09:40），不是开始节的
    expect(r.content, contains('DTEND:20260907T094000'));
  });

  test('跨周次的日期随周次递推（第 3 周周一 = 2026-09-21）', () {
    final r = build([course(weeks: const [3], dayOfWeek: 1)]);
    expect(r.content, contains('DTSTART:20260921T080000'));
  });

  test('SUMMARY/LOCATION 内容正确，TEXT 值按 RFC 5545 转义', () {
    final c = Course(
      id: 7,
      semesterId: 1,
      name: 'C;语言,入门',
      teacher: '李;老师',
      note: '带,笔记本',
      classroom: 'A;101',
      colorValue: 0xFF6B8E7B,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 1,
      weeks: const [1],
    );
    final r = build([c]);
    expect(r.content, contains(r'SUMMARY:C\;语言\,入门'));
    expect(r.content, contains(r'LOCATION:A\;101'));
    // 教师与备注进 DESCRIPTION，换行被转义为字面 \n
    expect(r.content, contains(r'DESCRIPTION:教师：李\;老师\n带\,笔记本'));
  });

  test('无教室的课程不输出 LOCATION 行', () {
    final r = build([course(classroom: null)]);
    expect(r.content, contains('SUMMARY:高等数学'));
    expect(r.content.contains('LOCATION'), isFalse);
  });

  test('weekType 单双周过滤生效（weeks 里的偶数周被剔除）', () {
    final r = build([course(weeks: const [1, 2, 3], weekType: 1)]);
    expect(r.eventCount, 2);
    // 第 2 周周一 = 2026-09-14，双周不应出现
    expect(r.content.contains('20260914'), isFalse);
  });

  test('行尾为 CRLF 且不出现裸 LF（RFC 5545 要求）', () {
    final r = build([course()]);
    expect(r.content, contains('\r\n'));
    // 任何 \n 前面都不是 \r，说明没有裸换行
    expect(r.content.contains(RegExp(r'[^\r]\n')), isFalse);
  });

  test('日历头尾结构完整，含日历名扩展属性', () {
    final r = build([course()]);
    expect(r.content, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(r.content, contains('VERSION:2.0'));
    expect(r.content, contains('PRODID:'));
    expect(r.content, contains('X-WR-CALNAME:2026 秋季学期'));
    expect(r.content.trim(), endsWith('END:VCALENDAR'));
  });

  test('节次时间缺失的课程跳过并计数，不抛异常', () {
    final r = build([
      course(weeks: const [1, 2], startSection: 11, endSection: 12),
      course(),
    ]);
    // 第 11/12 节不在 slots 里 → 前一门课的 2 次被跳过，后一门正常导出
    expect(r.eventCount, 3);
    expect(r.skippedCount, 2);
  });
}
