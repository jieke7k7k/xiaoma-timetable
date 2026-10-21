import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/free_time.dart';

/// 空闲时段计算（1.2.0）：占用扣除、连续区间、全天没课、时长文本
void main() {
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:40'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:30'),
    TimeSlot(section: 3, startTime: '09:40', endTime: '10:20'),
    TimeSlot(section: 4, startTime: '10:30', endTime: '11:10'),
    TimeSlot(section: 5, startTime: '11:20', endTime: '12:00'),
  ];

  Course mk({int day = 1, int start = 1, int end = 2}) => Course(
        semesterId: 1,
        name: '课',
        colorValue: 0,
        dayOfWeek: day,
        startSection: start,
        endSection: end,
        weeks: const [1],
      );

  test('一门课占 1-2 节 → 当天空闲为 3-5 节一段', () {
    final blocks =
        freeBlocksForWeek([mk()], slots).where((b) => b.dayOfWeek == 1);
    expect(blocks.length, 1);
    expect(blocks.single.startSection, 3);
    expect(blocks.single.endSection, 5);
    expect(blocks.single.startTime, '09:40');
    expect(blocks.single.endTime, '12:00');
    expect(blocks.single.durationText, '约 2 小时 20 分钟');
  });

  test('中间有课 → 空闲被切成两段', () {
    final blocks = freeBlocksForWeek([mk(start: 3, end: 3)], slots)
        .where((b) => b.dayOfWeek == 1)
        .toList();
    expect(blocks.length, 2);
    expect((blocks[0].startSection, blocks[0].endSection), (1, 2));
    expect((blocks[1].startSection, blocks[1].endSection), (4, 5));
  });

  test('整天没课 → 一段覆盖全天', () {
    final blocks =
        freeBlocksForWeek(const [], slots).where((b) => b.dayOfWeek == 6);
    expect(blocks.length, 1);
    expect(blocks.single.startSection, 1);
    expect(blocks.single.endSection, 5);
  });

  test('全天排满 → 无空闲段', () {
    final blocks = freeBlocksForWeek([mk(start: 1, end: 5)], slots)
        .where((b) => b.dayOfWeek == 1);
    expect(blocks, isEmpty);
  });

  test('多门课占用合并：相邻课程不产生假空闲', () {
    final blocks = freeBlocksForWeek(
            [mk(start: 1, end: 2), mk(start: 3, end: 4)], slots)
        .where((b) => b.dayOfWeek == 1)
        .toList();
    expect(blocks.length, 1);
    expect(blocks.single.startSection, 5);
  });
}
