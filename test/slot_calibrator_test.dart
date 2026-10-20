import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ics_parser.dart';
import 'package:xiaoma_timetable/utils/slot_calibrator.dart';

/// SlotCalibrator 单元测试：覆盖规格点名的四种情况 + 非法值跳过 + 不改入参
void main() {
  group('SlotCalibrator.calibrate', () {
    test('单块覆盖首尾：无课时证据时只改块首节开始与末节结束', () {
      final slots = _slots();
      final blocks = [
        _block(start: 1, end: 3, startTime: '08:00', endTime: '10:20'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 1 节开始时间被覆盖
      expect(_find(result, 1).startTime, '08:00');
      // 第 1 节结束时间不变（块只覆盖 startSection 的开始）
      expect(_find(result, 1).endTime, _find(slots, 1).endTime);
      // 第 3 节结束时间被覆盖
      expect(_find(result, 3).endTime, '10:20');
      // 第 3 节开始时间不变（块只覆盖 endSection 的结束）
      expect(_find(result, 3).startTime, _find(slots, 3).startTime);
      // 中间的节次完全不变
      expect(_find(result, 2).startTime, _find(slots, 2).startTime);
      expect(_find(result, 2).endTime, _find(slots, 2).endTime);
    });

    test('相邻块共享节次：交叉确定整段网格（课时 40 分钟、课间 10 分钟）', () {
      // 旧版断言固化了「第 3 节 09:40 开始、09:30 结束」的倒置结果，
      // 网格重建版按真实作息语义断言完整网格。
      final slots = _slots5();
      final blocks = [
        _block(start: 1, end: 3, startTime: '08:00', endTime: '10:20'),
        _block(start: 3, end: 5, startTime: '09:40', endTime: '12:00'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      // 第 3 节：开始来自第二个块、结束来自第一个块，共同生效
      expect(_find(result, 3).startTime, '09:40');
      expect(_find(result, 3).endTime, '10:20');
      // 其余节次由课时与课间链式推出
      expect(_find(result, 1).startTime, '08:00');
      expect(_find(result, 1).endTime, '08:40');
      expect(_find(result, 2).startTime, '08:50');
      expect(_find(result, 2).endTime, '09:30');
      expect(_find(result, 4).startTime, '10:30');
      expect(_find(result, 4).endTime, '11:10');
      expect(_find(result, 5).startTime, '11:20');
      expect(_find(result, 5).endTime, '12:00');
    });

    test('原作息结构不一致时不得拼出倒置时间（真机「14:00-12:00」回归）', () {
      // 原作息第 5 节是下午的 14:00-14:45，真实作息第 5 节在上午以 12:00 结束：
      // 旧版只覆盖结束时间会拼出 14:00-12:00；新版由课时反推开始时间。
      final slots = _slots5();
      final blocks = [
        _block(start: 1, end: 3, startTime: '08:00', endTime: '10:20'),
        _block(start: 3, end: 5, startTime: '09:40', endTime: '12:00'),
      ];

      final result = SlotCalibrator.calibrate(slots, blocks);

      expect(_find(result, 5).startTime, '11:20');
      expect(_find(result, 5).endTime, '12:00');
      // 全表合法性：开始早于结束、相邻不重叠
      for (var i = 0; i < result.length; i++) {
        expect(result[i].startTime.compareTo(result[i].endTime), lessThan(0),
            reason: '第 ${result[i].section} 节倒置');
        if (i + 1 < result.length) {
          expect(result[i].endTime.compareTo(result[i + 1].startTime),
              lessThanOrEqualTo(0),
              reason: '第 ${result[i].section} 节与下一节重叠');
        }
      }
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

      // 第 1 节非法值全部跳过，且未被其他证据触及，保持原值
      expect(_find(result, 1).startTime, _find(slots, 1).startTime);
      expect(_find(result, 1).endTime, _find(slots, 1).endTime);
      // 第 2 节 startTime 非法跳过（没有被采用）；endTime 合法生效，
      // 开始时间由第 3 节推导出的课时（50 分钟）从结束时间反推
      expect(_find(result, 2).startTime, '09:10');
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

/// 构造 5 节测试作息表（旧默认风格：第 5 节落在下午 14:00，
/// 用于模拟原作息与真实作息结构不一致的场景）
List<TimeSlot> _slots5() => const [
      TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
      TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
      TimeSlot(section: 3, startTime: '10:00', endTime: '10:45'),
      TimeSlot(section: 4, startTime: '10:55', endTime: '11:40'),
      TimeSlot(section: 5, startTime: '14:00', endTime: '14:45'),
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
