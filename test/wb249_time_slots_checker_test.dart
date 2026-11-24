import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/time_slots_checker.dart';

/// 浙师大内置默认作息（db_helper.dart defaultTimeSlots，13 节）
const _zjnuSlots = [
  TimeSlot(section: 1, startTime: '08:00', endTime: '08:40'),
  TimeSlot(section: 2, startTime: '08:50', endTime: '09:30'),
  TimeSlot(section: 3, startTime: '09:40', endTime: '10:20'),
  TimeSlot(section: 4, startTime: '10:30', endTime: '11:10'),
  TimeSlot(section: 5, startTime: '11:20', endTime: '12:00'),
  TimeSlot(section: 6, startTime: '14:00', endTime: '14:40'),
  TimeSlot(section: 7, startTime: '14:50', endTime: '15:30'),
  TimeSlot(section: 8, startTime: '15:40', endTime: '16:20'),
  TimeSlot(section: 9, startTime: '16:30', endTime: '17:10'),
  TimeSlot(section: 10, startTime: '18:00', endTime: '18:40'),
  TimeSlot(section: 11, startTime: '18:50', endTime: '19:30'),
  TimeSlot(section: 12, startTime: '19:40', endTime: '20:20'),
  TimeSlot(section: 13, startTime: '20:30', endTime: '21:10'),
];

/// 大连海洋大学作息 1–8 节（同学截图实测）
const _dlouSlots = [
  TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
  TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
  TimeSlot(section: 3, startTime: '09:50', endTime: '10:35'),
  TimeSlot(section: 4, startTime: '10:40', endTime: '11:25'),
  TimeSlot(section: 5, startTime: '11:30', endTime: '12:15'),
  TimeSlot(section: 6, startTime: '13:30', endTime: '14:15'),
  TimeSlot(section: 7, startTime: '14:20', endTime: '15:05'),
  TimeSlot(section: 8, startTime: '15:15', endTime: '16:00'),
];

void main() {
  group('extractFromSectionTexts', () {
    test('带节次号与时间的行按号归位', () {
      final slots = TimeSlotsChecker.extractFromSectionTexts([
        '1\n08:00-08:45',
        '第2节 08:50~09:35',
        '第3节 09:50–10:35',
      ]);
      expect(slots.length, 3);
      expect(slots[0].section, 1);
      expect(slots[0].startTime, '08:00');
      expect(slots[0].endTime, '08:45');
      expect(slots[1].section, 2);
      expect(slots[2].section, 3);
      expect(slots[2].endTime, '10:35');
    });

    test('无节次号时按行序顺延', () {
      final slots = TimeSlotsChecker.extractFromSectionTexts([
        '08:00-08:45',
        '08:50-09:35',
      ]);
      expect(slots.map((s) => s.section).toList(), [1, 2]);
    });

    test('裸节次标签行把顺延基准推到它之后', () {
      final slots = TimeSlotsChecker.extractFromSectionTexts([
        '3',
        '08:00-08:45',
      ]);
      expect(slots.length, 1);
      expect(slots[0].section, 4);
    });

    test('裸节次区间行同样推进顺延基准', () {
      final slots = TimeSlotsChecker.extractFromSectionTexts([
        '1-2',
        '08:00-08:45',
      ]);
      expect(slots.length, 1);
      expect(slots[0].section, 3);
    });

    test('起止颠倒与非法时间跳过', () {
      final slots = TimeSlotsChecker.extractFromSectionTexts([
        '08:45-08:00',
        '25:00-26:00',
        '08:00-08:45',
      ]);
      expect(slots.length, 1);
      expect(slots[0].section, 1);
    });
  });

  group('extractFromLooseTexts', () {
    test('行首节次标记 + 时间段认出', () {
      final result = TimeSlotsChecker.extractFromLooseTexts([
        '第1节 08:00-08:45',
        '第2节 08:50-09:35',
        '3 09:50-10:35',
      ]);
      expect(result.length, 3);
      expect(result[0].section, 1);
      expect(result[0].startTime, '08:00');
      expect(result[0].endTime, '08:45');
      expect(result[2].section, 3);
      expect(result[2].startTime, '09:50');
    });

    test('整行只有一个时间段时按行序顺延', () {
      final result = TimeSlotsChecker.extractFromLooseTexts([
        '08:00-08:45',
        '08:50-09:35',
      ]);
      expect(result.length, 2);
      expect(result[0].section, 1);
      expect(result[1].section, 2);
    });

    test('办公时间与课程条目行不要', () {
      final result = TimeSlotsChecker.extractFromLooseTexts([
        '办公时间 08:00-12:00',
        '高等数学 1-2节 08:00-09:35 周一',
        '考试 09:00-11:00',
      ]);
      expect(result, isEmpty);
    });

    test('X-Y 时间段行只记到 X 节（与主表口径一致）', () {
      final result = TimeSlotsChecker.extractFromLooseTexts([
        '1-2 08:00-09:35',
      ]);
      expect(result.length, 1);
      expect(result[0].section, 1);
    });
  });

  group('pickPreferredSlots', () {
    test('优先级：网页 > 预设 > OCR；全空返回 null', () {
      const web = [TimeSlot(section: 1, startTime: '08:00', endTime: '08:45')];
      const preset = [TimeSlot(section: 1, startTime: '09:00', endTime: '09:45')];
      const ocr = [TimeSlot(section: 1, startTime: '10:00', endTime: '10:45')];
      expect(
        TimeSlotsChecker.pickPreferredSlots(
          fromWebPage: web,
          fromSchoolPreset: preset,
          fromOcr: ocr,
        ),
        web,
      );
      expect(
        TimeSlotsChecker.pickPreferredSlots(
          fromSchoolPreset: preset,
          fromOcr: ocr,
        ),
        preset,
      );
      expect(
        TimeSlotsChecker.pickPreferredSlots(fromOcr: ocr),
        ocr,
      );
      expect(
        TimeSlotsChecker.pickPreferredSlots(
          fromWebPage: const [],
          fromSchoolPreset: const [],
          fromOcr: const [],
        ),
        isNull,
      );
    });
  });

  group('compare（浙师大现状 vs 大连海洋 1–8 节）', () {
    test('只比对已读到的节次，1–8 节全不同，其余保留原样', () {
      final result = TimeSlotsChecker.compare(
        current: _zjnuSlots,
        incoming: _dlouSlots,
      );
      expect(result.hasDifference, isTrue);
      expect(result.diffs.length, 8);
      expect(result.diffs.first.section, 1);
      expect(result.diffs.first.currentRange, '08:00-08:40');
      expect(result.diffs.first.incomingRange, '08:00-08:45');
      // 合并：1–8 节取大连海洋，9–13 节保留浙师大
      expect(result.mergedSlots.length, 13);
      expect(result.mergedSlots[0].endTime, '08:45');
      expect(result.mergedSlots[8].startTime, '16:30');
    });

    test('作息完全一致时无差异', () {
      final result = TimeSlotsChecker.compare(
        current: _zjnuSlots,
        incoming: _zjnuSlots,
      );
      expect(result.hasDifference, isFalse);
      expect(result.diffs, isEmpty);
    });
  });

  group('inferBreakBands', () {
    test('大连海洋合并作息：午间在 5 节后、晚间在 9 节后', () {
      final merged = TimeSlotsChecker.compare(
        current: _zjnuSlots,
        incoming: _dlouSlots,
      ).mergedSlots;
      final bands = TimeSlotsChecker.inferBreakBands(merged);
      expect(bands.lunchAfterSection, 5);
      expect(bands.lunchStart, '12:15');
      expect(bands.lunchEnd, '13:30');
      expect(bands.dinnerAfterSection, 9);
      expect(bands.dinnerStart, '17:10');
      expect(bands.dinnerEnd, '18:00');
    });

    test('晚上没课时晚间带子为 null（保持原样）', () {
      final bands = TimeSlotsChecker.inferBreakBands(_dlouSlots);
      expect(bands.hasLunch, isTrue);
      expect(bands.lunchAfterSection, 5);
      expect(bands.hasDinner, isFalse);
    });

    test('浙师大默认作息推出的带子与现有分段点一致（午间 5 节后、晚间 9 节后）', () {
      final bands = TimeSlotsChecker.inferBreakBands(_zjnuSlots);
      // 5→6 节空档 12:00–14:00（120 分钟），9→10 节空档 17:10–18:00（50 分钟）
      expect(bands.lunchAfterSection, 5);
      expect(bands.dinnerAfterSection, 9);
    });
  });
}
