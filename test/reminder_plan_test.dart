import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/reminder_plan.dart';

/// 上课提醒纯逻辑测试
///
/// 覆盖：提醒时刻计算、通知文案（有/无教室）、当日课程筛选
/// （星期匹配 / 周次过滤 / 单双周过滤 / 未开学 / 缺节次时间跳过 / 升序排序）。
void main() {
  // 2026-09-07 是周一（与 db_helper 默认开学日期一致）
  const semester =
      Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 3, startTime: '10:00', endTime: '10:45'),
  ];

  Course course({
    int dayOfWeek = 1,
    int startSection = 1,
    List<int> weeks = const [1, 2],
    int weekType = 0,
    String? classroom,
  }) =>
      Course(
        semesterId: 1,
        name: '课程',
        classroom: classroom,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: startSection,
        weeks: weeks,
        weekType: weekType,
      );

  group('computeReminderTime', () {
    test('上课时刻减去提前分钟', () {
      expect(
        computeReminderTime(DateTime(2026, 9, 7, 8, 0), 15),
        DateTime(2026, 9, 7, 7, 45),
      );
    });

    test('跨天借位（凌晨的课提前到前一天）', () {
      expect(
        computeReminderTime(DateTime(2026, 9, 8, 0, 10), 30),
        DateTime(2026, 9, 7, 23, 40),
      );
    });
  });

  group('buildReminderBody', () {
    test('有教室', () {
      final c = course(classroom: 'A101');
      expect(buildReminderBody(c, 15), '《课程》还有 15 分钟在 A101 上课');
    });

    test('无教室兜底', () {
      expect(buildReminderBody(course(), 15), '《课程》还有 15 分钟上课');
    });
  });

  group('buildDailyReminderPlan', () {
    test('只筛选当天星期的课程，并按节次时间算提醒时刻、升序排序', () {
      final plans = buildDailyReminderPlan(
        date: DateTime(2026, 9, 7), // 周一 · 第 1 周
        semester: semester,
        courses: [
          course(dayOfWeek: 1, startSection: 3), // 10:00 → 09:45
          course(dayOfWeek: 2), // 周二，应被过滤
          course(dayOfWeek: 1, startSection: 1), // 08:00 → 07:45
        ],
        timeSlots: slots,
        advanceMinutes: 15,
      );

      expect(plans.length, 2);
      expect(plans[0].reminderTime, DateTime(2026, 9, 7, 7, 45));
      expect(plans[1].reminderTime, DateTime(2026, 9, 7, 9, 45));
    });

    test('按周次过滤（只在 weeks 内的周提醒）', () {
      final plans = buildDailyReminderPlan(
        date: DateTime(2026, 9, 7), // 第 1 周
        semester: semester,
        courses: [
          course(weeks: [1]),
          course(weeks: [2]),
        ],
        timeSlots: slots,
        advanceMinutes: 15,
      );
      expect(plans.length, 1);
    });

    test('单双周过滤（单周课双周不提醒）', () {
      final courses = [course(weekType: 1)]; // 单周
      final week1 = buildDailyReminderPlan(
        date: DateTime(2026, 9, 7), // 第 1 周（单）
        semester: semester,
        courses: courses,
        timeSlots: slots,
        advanceMinutes: 15,
      );
      final week2 = buildDailyReminderPlan(
        date: DateTime(2026, 9, 14), // 第 2 周（双）
        semester: semester,
        courses: courses,
        timeSlots: slots,
        advanceMinutes: 15,
      );
      expect(week1.length, 1);
      expect(week2.length, 0);
    });

    test('未开学（周次 0）返回空', () {
      final plans = buildDailyReminderPlan(
        date: DateTime(2026, 9, 1), // 开学前
        semester: semester,
        courses: [course()],
        timeSlots: slots,
        advanceMinutes: 15,
      );
      expect(plans, isEmpty);
    });

    test('找不到对应节次时间时跳过该课程', () {
      final plans = buildDailyReminderPlan(
        date: DateTime(2026, 9, 7),
        semester: semester,
        courses: [course(startSection: 5)], // 节次表没有第 5 节
        timeSlots: slots,
        advanceMinutes: 15,
      );
      expect(plans, isEmpty);
    });
  });
}
