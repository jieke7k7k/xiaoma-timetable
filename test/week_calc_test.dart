import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/week_calc.dart';

/// WeekCalc 单元测试
/// 覆盖：开学当天、跨月/跨年、未开学（开学前 3 天）、学期结束后等边界情况
void main() {
  // 2026-09-07 恰好是周一，作为基准开学日期
  final start = DateTime(2026, 9, 7);

  group('alignToMonday 对齐周一', () {
    test('周一当天保持不变', () {
      final d = WeekCalc.alignToMonday(DateTime(2026, 9, 7));
      expect(d, DateTime(2026, 9, 7));
    });

    test('周日对齐到本周周一', () {
      // 2026-09-13 是周日，应对齐到 09-07
      final d = WeekCalc.alignToMonday(DateTime(2026, 9, 13));
      expect(d, DateTime(2026, 9, 7));
    });

    test('开学日期非周一时自动对齐（周三 → 本周周一）', () {
      // 2026-09-09 是周三
      final d = WeekCalc.alignToMonday(DateTime(2026, 9, 9));
      expect(d, DateTime(2026, 9, 7));
    });
  });

  group('currentWeek 周次计算', () {
    test('开学当天是第 1 周', () {
      expect(WeekCalc.currentWeek(start, DateTime(2026, 9, 7)), 1);
    });

    test('开学第一周周日仍是第 1 周', () {
      expect(WeekCalc.currentWeek(start, DateTime(2026, 9, 13)), 1);
    });

    test('第二个周一是第 2 周', () {
      expect(WeekCalc.currentWeek(start, DateTime(2026, 9, 14)), 2);
    });

    test('未开学（开学前 3 天）返回 0', () {
      expect(WeekCalc.currentWeek(start, DateTime(2026, 9, 4)), 0);
    });

    test('未开学（开学前 1 天）返回 0', () {
      expect(WeekCalc.currentWeek(start, DateTime(2026, 9, 6)), 0);
    });

    test('开学日期填的是周三也能正确算周次', () {
      // 用户填 09-09（周三），系统对齐到 09-07（周一）
      expect(WeekCalc.currentWeek(DateTime(2026, 9, 9), DateTime(2026, 9, 7)), 1);
      expect(WeekCalc.currentWeek(DateTime(2026, 9, 9), DateTime(2026, 9, 15)), 2);
    });

    test('跨月：10 月 5 日是第 5 周', () {
      // 09-07 + 4*7 = 10-05
      expect(WeekCalc.currentWeek(start, DateTime(2026, 10, 5)), 5);
    });

    test('跨年：2027-01-04 是第 18 周', () {
      // 09-07 + 17*7 = 2027-01-04
      expect(WeekCalc.currentWeek(start, DateTime(2027, 1, 4)), 18);
    });

    test('学期结束后（20 周学期，第 25 周）仍返回实际周数', () {
      // 09-07 + 24*7 = 2027-02-22，超过 20 周但总周数不参与计算
      expect(WeekCalc.currentWeek(start, DateTime(2027, 2, 22)), 25);
    });
  });

  group('单双周判断', () {
    test('第 1 周是单周', () {
      expect(WeekCalc.isOddWeek(1), isTrue);
      expect(WeekCalc.weekTypeText(1), '单周');
    });

    test('第 2 周是双周', () {
      expect(WeekCalc.isOddWeek(2), isFalse);
      expect(WeekCalc.weekTypeText(2), '双周');
    });

    test('未开学时返回提示文案', () {
      expect(WeekCalc.weekTypeText(0), '未开学');
      expect(WeekCalc.isOddWeek(0), isFalse);
    });
  });

  group('weekDates 本周日期列表', () {
    test('返回周一到周日共 7 天', () {
      // 2026-09-10 是周四
      final dates = WeekCalc.weekDates(DateTime(2026, 9, 10));
      expect(dates.length, 7);
      expect(dates.first, DateTime(2026, 9, 7)); // 周一
      expect(dates.last, DateTime(2026, 9, 13)); // 周日
      expect(dates.first.weekday, DateTime.monday);
      expect(dates.last.weekday, DateTime.sunday);
    });

    test('跨月的一周日期正确', () {
      // 2026-09-30 周三所在周：09-28 ~ 10-04
      final dates = WeekCalc.weekDates(DateTime(2026, 9, 30));
      expect(dates.first, DateTime(2026, 9, 28));
      expect(dates.last, DateTime(2026, 10, 4));
    });

    test('weekDatesOf 按周次取日期', () {
      final dates = WeekCalc.weekDatesOf(start, 3);
      expect(dates.first, DateTime(2026, 9, 21));
      expect(dates.last, DateTime(2026, 9, 27));
    });
  });

  group('weekTitle 顶部文案', () {
    test('正常周次', () {
      expect(WeekCalc.weekTitle(3), '第 3 周 · 单周');
      expect(WeekCalc.weekTitle(4), '第 4 周 · 双周');
    });

    test('未开学', () {
      expect(WeekCalc.weekTitle(0), '距开学还有一段时间');
    });
  });
}
