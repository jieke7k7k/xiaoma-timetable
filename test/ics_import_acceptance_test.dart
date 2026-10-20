import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
