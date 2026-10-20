import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ics_parser.dart';
import 'package:xiaoma_timetable/utils/slot_calibrator.dart';

/// ICS 导入验收测试：使用用户本人从 WakeUp 导出的真实课表文件
/// （test/fixtures/wakeup_sample.ics），断言值均按文件实测核对：
/// - 共 14 个 VEVENT、12 个不同课程名；
/// - DESCRIPTION 为「第 X - Y 节\n教室\n老师」结构，
///   LOCATION 为「教室 老师」拼接；
/// - 每个事件带 VALARM 提醒子块。
void main() {
  group('WakeUp 真实课表导入验收', () {
    // 本人学期第一周周一为 2026-09-07（文件中最早一节课在第二周 09-14）
    final semesterStart = DateTime(2026, 9, 7);
    // 占位作息：第 1~13 节全部 08:00/08:45，仅用于走通解析与校准
    final placeholderSlots = [
      for (var s = 1; s <= 13; s++)
        TimeSlot(section: s, startTime: '08:00', endTime: '08:45'),
    ];

    late IcsParseResult result;

    setUpAll(() {
      final content =
          File('test/fixtures/wakeup_sample.ics').readAsStringSync();
      result = IcsParser.parse(
        content,
        semesterStart: semesterStart,
        slots: placeholderSlots,
      );
    });

    test('14 个事件全部解析成功，12 个不同课名', () {
      expect(result.errors, isEmpty);
      expect(result.courses, hasLength(14));
      expect(result.timeBlocks, hasLength(14));
      final names = result.courses.map((c) => c.name).toSet();
      expect(names, hasLength(12));
    });

    test('药物化学块：第 1–3 节、08:00–10:20', () {
      final block = _blockOf(result, '药物化学');
      expect(block.startSection, 1);
      expect(block.endSection, 3);
      expect(block.startTime, '08:00');
      expect(block.endTime, '10:20');
    });

    test('药理学实验块：第 6–9 节、14:00–17:10', () {
      final block = _blockOf(result, '药理学实验');
      expect(block.startSection, 6);
      expect(block.endSection, 9);
      expect(block.startTime, '14:00');
      expect(block.endTime, '17:10');
    });

    test('课程含老师与教室：从 WakeUp 结构化描述中拆出', () {
      final chem = _courseOf(result, '药物化学');
      expect(chem.teacher, '邓卫平');
      expect(chem.classroom, '16-102');

      final pharma = _courseOf(result, '药理学');
      expect(pharma.teacher, '周金明');
      expect(pharma.classroom, '16-639');

      // 无老师的课程不应把教室误当老师，也不应把老师拼进教室
      final pe = _courseOf(result, '大学体育');
      expect(pe.teacher, isNull);
      expect(pe.classroom, '体育馆');
    });

    test('校准：相邻块共享节次时交叉确定每节起止', () {
      final calibrated =
          SlotCalibrator.calibrate(placeholderSlots, result.timeBlocks);

      TimeSlot slot(int s) => calibrated.firstWhere((e) => e.section == s);

      // 第 1 节开始来自「药物化学」块（第 1–3 节 08:00 起）
      expect(slot(1).startTime, '08:00');
      // 第 3 节：开始来自「药理学」块（第 3–5 节 09:40 起），
      // 结束来自「药物化学」块（第 1–3 节 10:20 止），交叉确定
      expect(slot(3).startTime, '09:40');
      expect(slot(3).endTime, '10:20');
      // 第 5 节结束来自「药理学」块（第 3–5 节 12:00 止）
      expect(slot(5).endTime, '12:00');
    });

    test('以 App 默认作息为底校准：重建完整的 13 节真实网格', () {
      // 真机回归：默认作息与真实作息结构不一致时，旧校准拼出过
      // 第 5 节 14:00-12:00、第 8 节 16:55-16:20 等倒置时间。
      // 期望网格按文件块交叉推导（每节 40 分钟）逐节核对。
      final calibrated =
          SlotCalibrator.calibrate(defaultTimeSlots, result.timeBlocks);

      expect(calibrated, hasLength(13)); // 扩出第 13 节
      const expected = {
        1: ('08:00', '08:40'),
        2: ('08:50', '09:30'),
        3: ('09:40', '10:20'),
        4: ('10:30', '11:10'),
        5: ('11:20', '12:00'),
        6: ('14:00', '14:40'),
        7: ('14:50', '15:30'),
        8: ('15:40', '16:20'),
        9: ('16:30', '17:10'),
        10: ('18:00', '18:40'),
        11: ('18:45', '19:25'),
        12: ('19:40', '20:20'),
        13: ('20:30', '21:10'),
      };
      for (final s in calibrated) {
        final e = expected[s.section]!;
        expect(s.startTime, e.$1, reason: '第 ${s.section} 节开始');
        expect(s.endTime, e.$2, reason: '第 ${s.section} 节结束');
        expect(s.startTime.compareTo(s.endTime), lessThan(0),
            reason: '第 ${s.section} 节不得倒置');
      }
      // 分段间隔：午休 12:00-14:00、晚餐 17:10-18:00
      TimeSlot slot(int sec) => calibrated.firstWhere((e) => e.section == sec);
      expect(slot(5).endTime, '12:00');
      expect(slot(6).startTime, '14:00');
      expect(slot(9).endTime, '17:10');
      expect(slot(10).startTime, '18:00');
    });
  });
}

IcsTimeBlock _blockOf(IcsParseResult result, String courseName) {
  final idx = result.courses.indexWhere((c) => c.name == courseName);
  if (idx < 0) fail('未解析出课程：$courseName');
  return result.timeBlocks[idx];
}

Course _courseOf(IcsParseResult result, String courseName) {
  final idx = result.courses.indexWhere((c) => c.name == courseName);
  if (idx < 0) fail('未解析出课程：$courseName');
  return result.courses[idx];
}
