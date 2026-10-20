import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ongoing_notice.dart';

/// 今日课程常驻通知纯逻辑测试
///
/// 覆盖：B 决策（今日有未下课课程 → 显示今日剩余，哪怕已过 20:00；
/// 今日课程全部下课 → 切明日预告）、行格式（有/无教室）、明日无课兜底。
void main() {
  // 2026-09-07 是周一（与 reminder_plan_test 一致）
  const semester =
      Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '14:00', endTime: '15:30'),
    TimeSlot(section: 3, startTime: '20:00', endTime: '21:30'),
  ];

  Course course({
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 1,
    String name = '高等数学',
    String? classroom,
    List<int> weeks = const [1, 2],
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

  group('buildOngoingNotice', () {
    test('今日还有未下课课程 → 显示今日剩余，行含教室', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 10, 0), // 周一 10:00
        semester: semester,
        courses: [
          // 14:00-15:30 未下课
          course(
              startSection: 2, endSection: 2, name: '大学物理', classroom: 'B202'),
          // 08:00-08:45 已下课
          course(startSection: 1, endSection: 1, classroom: 'A101'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '今日剩余课程（共 1 节）');
      expect(notice.lines, ['14:00-15:30 大学物理 B202']);
    });

    test('今日课程 16:00 前全部结束、20:30 时切明日预告（B 决策）', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 20, 30), // 周一 20:30
        semester: semester,
        courses: [
          // 08:00-08:45 已结束
          course(startSection: 1, endSection: 1, classroom: 'A101'),
          // 14:00-15:30 已结束
          course(
              startSection: 2, endSection: 2, name: '大学物理', classroom: 'B202'),
          // 周二 08:00-08:45
          course(dayOfWeek: 2, startSection: 1, endSection: 1, classroom: 'A101'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '明日课程预告（共 1 节）');
      expect(notice.lines, ['08:00-08:45 高等数学 A101']);
    });

    test('已过 20:00 但今日仍有未下课课程 → 仍显示今日剩余', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 20, 30), // 周一 20:30
        semester: semester,
        courses: [
          // 20:00-21:30 未下课
          course(startSection: 3, endSection: 3, classroom: 'C303'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '今日剩余课程（共 1 节）');
      expect(notice.lines, ['20:00-21:30 高等数学 C303']);
    });

    test('无教室时行格式省略教室', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 10, 0),
        semester: semester,
        courses: [
          course(startSection: 2, endSection: 2), // 无教室
        ],
        timeSlots: slots,
      );
      expect(notice.lines, ['14:00-15:30 高等数学']);
    });

    test('明日无课 → 预告 0 节并给兜底文案', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 20, 30),
        semester: semester,
        courses: [
          course(startSection: 1, endSection: 1), // 周一已结束，周二无课
        ],
        timeSlots: slots,
      );
      expect(notice.title, '明日课程预告（共 0 节）');
      expect(notice.lines, ['明天暂无课程']);
    });
  });
}
