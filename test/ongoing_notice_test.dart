import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ongoing_notice.dart';

/// 常驻通知纯逻辑测试（1.2.0 焦点模式）
///
/// 与主页状态条共用 computeClassFocus：上课中挂当前课 + 下一节预告，
/// 课前/课间挂下一节，今天没课看明天，近期无课给兜底文案。
void main() {
  // 2026-09-07 是周一
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

  group('buildOngoingNotice 焦点模式', () {
    test('课间：标题是下一节课，行给时间与教室', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 10, 0),
        semester: semester,
        courses: [
          course(
              startSection: 2, endSection: 2, name: '大学物理', classroom: 'B202'),
          course(startSection: 1, endSection: 1, classroom: 'A101'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '下一节：大学物理');
      expect(notice.lines, ['14:00–15:30 · B202']);
    });

    test('上课中：标题是当前课，第二行预告下一节', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 8, 20),
        semester: semester,
        courses: [
          course(startSection: 1, endSection: 1, classroom: 'A101'),
          course(
              startSection: 2, endSection: 2, name: '大学物理', classroom: 'B202'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '正在上课：高等数学');
      expect(notice.lines, [
        '08:00–08:45 · 08:45 下课 · A101',
        '下一节：大学物理 · 今天 14:00 · B202',
      ]);
    });

    test('上课中且是当天最后一节：第二行提示没有其他课', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 20, 30),
        semester: semester,
        courses: [
          // 只在第 1 周有这一次课：9 天窗口内再无下一节，才会走「没有其他课」
          course(startSection: 3, endSection: 3, classroom: 'C303',
              weeks: const [1]),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '正在上课：高等数学');
      expect(notice.lines, [
        '20:00–21:30 · 21:30 下课 · C303',
        '今天没有其他课了',
      ]);
    });

    test('今天课已上完：下一节是明天的课，行内带「明天」', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 20, 30),
        semester: semester,
        courses: [
          course(startSection: 1, endSection: 1, classroom: 'A101'),
          course(dayOfWeek: 2, startSection: 1, endSection: 1,
              classroom: 'A101'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '下一节：高等数学');
      expect(notice.lines, ['明天 08:00–08:45 · A101']);
    });

    test('下一节之后今天还有课 → 附带计数提示', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 7, 0),
        semester: semester,
        courses: [
          course(startSection: 1, endSection: 1),
          course(startSection: 2, endSection: 2, name: '大学物理'),
          course(startSection: 3, endSection: 3, name: '晚自习课'),
        ],
        timeSlots: slots,
      );
      expect(notice.title, '下一节：高等数学');
      expect(notice.lines, ['08:00–08:45', '今天后面还有 2 节课']);
    });

    test('无教室时省略教室后缀', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 10, 0),
        semester: semester,
        courses: [course(startSection: 2, endSection: 2)],
        timeSlots: slots,
      );
      expect(notice.lines, ['14:00–15:30']);
    });

    test('近期无课 → 兜底文案', () {
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 20, 30),
        semester: semester,
        courses: [course(startSection: 1, endSection: 1)],
        timeSlots: slots,
      );
      // 该课第 1 周的已结束，但第 2 周同一时间（7 天后）在 9 天窗口内，仍有下一节
      // ——再用学期结束之后的时间验证彻底无课的兜底
      final after = buildOngoingNotice(
        now: DateTime(2027, 2, 1, 8, 0),
        semester: semester,
        courses: [course(startSection: 1, endSection: 1)],
        timeSlots: slots,
      );
      expect(after.title, '暂无课程安排');
      expect(after.lines, ['近期没有要上的课，好好休息']);
      expect(notice.title, isNot('暂无课程安排'));
    });
  });
}
