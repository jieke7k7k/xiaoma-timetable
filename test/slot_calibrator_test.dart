import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ics_parser.dart';
import 'package:xiaoma_timetable/utils/slot_calibrator.dart';

/// SlotCalibrator 单元测试：覆盖规格点名的四种情况 + 非法值跳过 + 不改入参
void main() {
  group('SlotCalibrator.calibrate', () {
    test('单块覆盖首尾：只改 startSection 开始时间与 endSection 结束时间', () {
      final slots = _slots();
      final blocks = [
        _block(start: 1, end: 3, startTime: '08:00', endTime: '09:30'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 1 节开始时间被覆盖
      expect(_find(result, 1).startTime, '08:00');
      // 第 1 节结束时间不变（块只覆盖 startSection 的开始）
      expect(_find(result, 1).endTime, _find(slots, 1).endTime);
      // 第 3 节结束时间被覆盖
      expect(_find(result, 3).endTime, '09:30');
      // 第 3 节开始时间不变（块只覆盖 endSection 的结束）
      expect(_find(result, 3).startTime, _find(slots, 3).startTime);
      // 中间的节次完全不变
      expect(_find(result, 2).startTime, _find(slots, 2).startTime);
      expect(_find(result, 2).endTime, _find(slots, 2).endTime);
    });

    test('相邻块共享节次：1-3 节块给第 3 节结束、3-5 节块给第 3 节开始，共同生效', () {
      final slots = _slots();
      final blocks = [
        _block(start: 1, end: 3, startTime: '08:00', endTime: '09:30'),
        _block(start: 3, end: 5, startTime: '09:40', endTime: '11:10'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 3 节开始时间来自第二个块（3-5 节的 startTime）
      expect(_find(result, 3).startTime, '09:40');
      // 第 3 节结束时间来自第一个块（1-3 节的 endTime）
      expect(_find(result, 3).endTime, '09:30');
    });

    test('冲突保留第一个：同一节次同一字段多个块给不同值', () {
      final slots = _slots();
      final blocks = [
        _block(start: 1, end: 1, startTime: '08:00', endTime: '08:45'),
        _block(start: 1, end: 1, startTime: '09:00', endTime: '09:45'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 1 节开始/结束都保留第一个块的值
      expect(_find(result, 1).startTime, '08:00');
      expect(_find(result, 1).endTime, '08:45');
    });

    test('未触及节次不变', () {
      final slots = _slots();
      final blocks = [
        _block(start: 1, end: 1, startTime: '08:00', endTime: '08:45'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 2、3 节完全保持原值
      for (final section in [2, 3]) {
        expect(_find(result, section).startTime,
            _find(slots, section).startTime);
        expect(_find(result, section).endTime, _find(slots, section).endTime);
      }
    });

    test('非法/空时间值跳过，不影响其他节次', () {
      final slots = _slots();
      final blocks = [
        _block(start: 1, end: 1, startTime: '', endTime: '8:5'), // 非法
        _block(start: 2, end: 2, startTime: '25:00', endTime: '10:00'),
        _block(start: 3, end: 3, startTime: '10:10', endTime: '11:00'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 1 节非法值全部跳过，保持原值
      expect(_find(result, 1).startTime, _find(slots, 1).startTime);
      expect(_find(result, 1).endTime, _find(slots, 1).endTime);
      // 第 2 节 startTime 非法跳过，endTime 合法生效
      expect(_find(result, 2).startTime, _find(slots, 2).startTime);
      expect(_find(result, 2).endTime, '10:00');
      // 第 3 节合法生效
      expect(_find(result, 3).startTime, '10:10');
      expect(_find(result, 3).endTime, '11:00');
    });

    test('不修改入参列表', () {
      final slots = _slots();
      final original = [for (final s in slots) s.copyWith()];
      final blocks = [
        _block(start: 1, end: 1, startTime: '08:00', endTime: '08:45'),
      ];

      SlotCalibrator.calibrate(slots, blocks);

      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].section, original[i].section);
        expect(slots[i].startTime, original[i].startTime);
        expect(slots[i].endTime, original[i].endTime);
      }
    });
  });
}

/// 构造 3 节测试作息表
List<TimeSlot> _slots() => const [
      TimeSlot(section: 1, startTime: '07:50', endTime: '08:35'),
      TimeSlot(section: 2, startTime: '08:45', endTime: '09:30'),
      TimeSlot(section: 3, startTime: '09:40', endTime: '10:25'),
    ];

TimeSlot _find(List<TimeSlot> slots, int section) =>
    slots.firstWhere((s) => s.section == section);

IcsTimeBlock _block({
  required int start,
  required int end,
  required String startTime,
  required String endTime,
}) =>
    IcsTimeBlock(
      startSection: start,
      endSection: end,
      startTime: startTime,
      endTime: endTime,
    );
