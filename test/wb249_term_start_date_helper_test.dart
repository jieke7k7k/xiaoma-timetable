import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/term_start_date_helper.dart';

void main() {
  group('mondayOfWeek', () {
    test('2026-09-01（周二）所在周一是 2026-08-31', () {
      expect(
        TermStartDateHelper.mondayOfWeek(DateTime(2026, 9, 1)),
        DateTime(2026, 8, 31),
      );
    });

    test('周一本身返回当天', () {
      expect(
        TermStartDateHelper.mondayOfWeek(DateTime(2026, 9, 7)),
        DateTime(2026, 9, 7),
      );
    });

    test('2026-03-01（周日）所在周一是 2026-02-23', () {
      expect(
        TermStartDateHelper.mondayOfWeek(DateTime(2026, 3, 1)),
        DateTime(2026, 2, 23),
      );
    });
  });

  group('defaultStartDateFor', () {
    test('2026-11-22（秋季）→ 9 月 1 日那周周一 2026-08-31', () {
      expect(
        TermStartDateHelper.defaultStartDateFor(DateTime(2026, 11, 22)),
        DateTime(2026, 8, 31),
      );
    });

    test('2026-03-15（春季）→ 3 月 1 日那周周一 2026-02-23', () {
      expect(
        TermStartDateHelper.defaultStartDateFor(DateTime(2026, 3, 15)),
        DateTime(2026, 2, 23),
      );
    });

    test('2027-01-15（次年 1 月归秋季）→ 上年 9 月 1 日那周周一', () {
      expect(
        TermStartDateHelper.defaultStartDateFor(DateTime(2027, 1, 15)),
        DateTime(2026, 8, 31),
      );
    });
  });

  group('calculateWeekNumber / suggestStartDateFromCurrentWeek', () {
    test('开学周一当天是第 1 周，下个周一是第 2 周', () {
      expect(
        TermStartDateHelper.calculateWeekNumber(
          startDate: DateTime(2026, 8, 31),
          today: DateTime(2026, 8, 31),
        ),
        1,
      );
      expect(
        TermStartDateHelper.calculateWeekNumber(
          startDate: DateTime(2026, 8, 31),
          today: DateTime(2026, 9, 7),
        ),
        2,
      );
    });

    test('11 月 22 日读到第 12 周，反推开学日为 2026-08-31（与同学学校一致）', () {
      expect(
        TermStartDateHelper.suggestStartDateFromCurrentWeek(
          detectedCurrentWeek: 12,
          today: DateTime(2026, 11, 22),
        ),
        DateTime(2026, 8, 31),
      );
    });
  });

  group('extractCurrentWeekFromText', () {
    test('常见写法都能抽到', () {
      expect(
        TermStartDateHelper.extractCurrentWeekFromText('当前第12周'),
        12,
      );
      expect(
        TermStartDateHelper.extractCurrentWeekFromText('第 8 周'),
        8,
      );
      expect(
        TermStartDateHelper.extractCurrentWeekFromText('当前周：第5周'),
        5,
      );
    });

    test('读不到或超范围返回 null', () {
      expect(TermStartDateHelper.extractCurrentWeekFromText('学生课表'), isNull);
      expect(TermStartDateHelper.extractCurrentWeekFromText(null), isNull);
      expect(TermStartDateHelper.extractCurrentWeekFromText('第31周'), isNull);
      // 「第1-16周」是课的周次范围，不是当前周
      expect(TermStartDateHelper.extractCurrentWeekFromText('第1-16周'), isNull);
    });
  });
}
