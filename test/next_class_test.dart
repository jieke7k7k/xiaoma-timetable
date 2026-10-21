import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/next_class.dart';

/// 当前/下一节课焦点（1.2.0）：课前、课中、课后、跨天与单双周
void main() {
  // 2026-09-07 周一开学
  const semester =
      Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
    TimeSlot(section: 6, startTime: '14:00', endTime: '15:30'),
  ];

  Course course({
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 1,
    String name = '高等数学',
    String? classroom,
    List<int> weeks = const [1, 2, 3],
    int weekType = 0,
  }) =>
      Course(
        semesterId: 1,
        name: name,
        classroom: classroom,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        weeks: weeks,
        weekType: weekType,
      );

  ClassFocus at(DateTime now, List<Course> courses) => computeClassFocus(
      now: now, semester: semester, courses: courses, timeSlots: slots);

  test('课前：无当前课，下一节是今天稍后的课', () {
    final f = at(DateTime(2026, 9, 7, 7, 30), [
      course(name: '高数'),
      course(name: '物理', startSection: 6, endSection: 6),
    ]);
    expect(f.current, isNull);
    expect(f.next?.course.name, '高数');
    expect(f.laterTodayCount, 1);
  });

  test('课中：当前课与下一节同时给出', () {
    final f = at(DateTime(2026, 9, 7, 8, 20), [
      course(name: '高数'),
      course(name: '物理', startSection: 6, endSection: 6),
    ]);
    expect(f.current?.course.name, '高数');
    expect(f.next?.course.name, '物理');
  });

  test('课间：刚下课，下一节是紧接着的那节', () {
    final f = at(DateTime(2026, 9, 7, 8, 47), [
      course(name: '高数'),
      course(name: '英语', startSection: 2, endSection: 2),
    ]);
    expect(f.current, isNull);
    expect(f.next?.course.name, '英语');
  });

  test('今天课上完：下一节是明天的课', () {
    final f = at(DateTime(2026, 9, 7, 16, 0), [
      course(name: '高数'),
      course(name: '化学', dayOfWeek: 2),
    ]);
    expect(f.current, isNull);
    expect(f.next?.course.name, '化学');
    expect(dayLabel(f.next!.date, DateTime(2026, 9, 7, 16, 0)), '明天');
  });

  test('周五晚上：下一节看到下周一（跨周末）', () {
    final f = at(DateTime(2026, 9, 11, 21, 0), [
      course(name: '高数', weeks: const [1, 2]),
    ]);
    expect(f.next?.course.name, '高数');
    expect(f.next?.date, DateTime(2026, 9, 14));
  });

  test('单双周过滤：双周课不在单周出现', () {
    final f = at(DateTime(2026, 9, 7, 7, 0), [
      course(name: '双周课', weekType: 2, weeks: const [1, 2]),
      course(name: '单周课', weekType: 1, weeks: const [1, 2],
          startSection: 6, endSection: 6),
    ]);
    expect(f.next?.course.name, '单周课');
  });

  test('学期未开始：向前看到开学第一课（开学预告）；学期结束后无焦点', () {
    final before = at(DateTime(2026, 9, 1, 8, 0), [course()]);
    expect(before.current, isNull);
    expect(before.next?.date, DateTime(2026, 9, 7));
    final after = at(DateTime(2027, 3, 1, 8, 0), [course()]);
    expect(after.hasAny, isFalse);
  });

  test('摘要格式：课名 + 时间段 + 教室', () {
    final f = at(DateTime(2026, 9, 7, 7, 0), [
      course(name: '药理学', classroom: '教3-201'),
    ]);
    expect(f.next?.summary, '药理学 08:00–08:45 · 教3-201');
  });
}
