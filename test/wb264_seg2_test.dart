import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/next_class.dart';
import 'package:xiaoma_timetable/utils/week_calc.dart';

/// WB_SPEC_264 第 2 段（§2 通知链路）回归测试
void main() {
  const semester =
      Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
  ];

  Course course({required int id, required String name}) => Course(
        id: id,
        semesterId: 1,
        name: name,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: 1,
        startSection: 1,
        endSection: 1,
        weeks: const [1, 2, 3],
      );

  group('合并 A 排序稳定性', () {
    test('同时间多门课按 id 升序，焦点课确定', () {
      final f = computeClassFocus(
        now: DateTime(2026, 9, 7, 7, 30),
        semester: semester,
        courses: [course(id: 5, name: '后录入'), course(id: 3, name: '先录入')],
        timeSlots: slots,
      );
      expect(f.next?.course.id, 3);
      expect(f.next?.course.name, '先录入');
    });

    test('sessionsOnDay 同时间多门课同样按 id 升序', () {
      final sessions = sessionsOnDay(
        date: DateTime(2026, 9, 7),
        semester: semester,
        courses: [course(id: 9, name: '乙'), course(id: 2, name: '甲')],
        timeSlots: slots,
      );
      expect(sessions.map((s) => s.course.id).toList(), [2, 9]);
    });
  });

  group('合并 B 夏令时', () {
    test('dayLabel 今天/明天/周X', () {
      expect(dayLabel(DateTime(2026, 9, 7), DateTime(2026, 9, 7, 8)), '今天');
      expect(dayLabel(DateTime(2026, 9, 8), DateTime(2026, 9, 7, 8)), '明天');
      expect(dayLabel(DateTime(2026, 9, 9), DateTime(2026, 9, 7, 8)),
          '周三（9月9日）');
    });

    test('currentWeek 跨周递进不变', () {
      expect(WeekCalc.currentWeek(DateTime(2026, 9, 7), DateTime(2026, 9, 7)), 1);
      expect(WeekCalc.currentWeek(DateTime(2026, 9, 7), DateTime(2026, 9, 14)), 2);
      expect(WeekCalc.currentWeek(DateTime(2026, 9, 7), DateTime(2026, 9, 6)), 0);
    });

    test('weekDatesOf 第 2 周周一是 9 月 14 日', () {
      final dates = WeekCalc.weekDatesOf(DateTime(2026, 9, 7), 2);
      expect(dates.first, DateTime(2026, 9, 14));
      expect(dates.last, DateTime(2026, 9, 20));
    });

    test('夏令时跳变日：dayLabel/currentWeek/weekDatesOf 按日历天算', () {
      // M7（DeepSeek 264 复审 B 段）：9 月上海日期无夏令时，新旧实现结果相同，
      // 咬不住；2026-03-08 是美东夏令时开始日（只有 23 小时的一天），
      // 旧实现用 Duration 除 24 小时会在这一带算错。
      // 本用例在 TZ=America/New_York 下才有判别力（见处置表）；上海时区下亦应全绿。
      // 2026-03-02 周一开学，03-09 是第 2 周周一。
      expect(dayLabel(DateTime(2026, 3, 9), DateTime(2026, 3, 7, 8)),
          '周一（3月9日）');
      expect(dayLabel(DateTime(2026, 3, 8), DateTime(2026, 3, 7, 8)), '明天');
      expect(
        WeekCalc.currentWeek(DateTime(2026, 3, 2), DateTime(2026, 3, 9)),
        2,
      );
      final dates = WeekCalc.weekDatesOf(DateTime(2026, 3, 2), 2);
      expect(dates.first, DateTime(2026, 3, 9));
      expect(dates.first.hour, 0);
    });
  });

  group('R3-3 脏开学日期回退基准', () {
    test('脏日期按参考日所在周一回退', () {
      const dirty = Semester(name: '脏', startDate: 'not-a-date', totalWeeks: 20);
      expect(dirty.parseStartDate(reference: DateTime(2026, 9, 9)),
          DateTime(2026, 9, 7));
    });

    test('合法日期原样解析，startDateParsed 仍可用', () {
      expect(semester.parseStartDate(), DateTime(2026, 9, 7));
      expect(semester.startDateParsed, DateTime(2026, 9, 7));
    });

    test('sessionsOnDay 显式传 semesterStart 与默认一致', () {
      final a = sessionsOnDay(
        date: DateTime(2026, 9, 7),
        semester: semester,
        courses: [course(id: 1, name: '高数')],
        timeSlots: slots,
      );
      final b = sessionsOnDay(
        date: DateTime(2026, 9, 7),
        semester: semester,
        courses: [course(id: 1, name: '高数')],
        timeSlots: slots,
        semesterStart: DateTime(2026, 9, 7),
      );
      expect(b.length, a.length);
      expect(b.first.course.name, '高数');
    });
  });
}
