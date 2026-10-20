import '../models/time_slot.dart';
import 'ics_parser.dart';

/// 按导入课表文件校准作息时间
///
/// 保守规则：
/// - 块的 [IcsTimeBlock.startTime] 只覆盖其 startSection 的开始时间；
/// - 块的 [IcsTimeBlock.endTime] 只覆盖其 endSection 的结束时间；
/// - 同一节次同一字段被多个块给出不同值时，保留第一个，跳过后续冲突值；
/// - 未被任何块触及的节次保持原值。
class SlotCalibrator {
  SlotCalibrator._();

  /// 返回校准后的新列表，不修改入参 [slots]
  static List<TimeSlot> calibrate(
      List<TimeSlot> slots, List<IcsTimeBlock> blocks) {
    final result = [for (final s in slots) s];

    // 按「节次 + 字段」粒度记录已定值，保证同字段冲突保留第一个、
    // 而 startTime 与 endTime 互不干扰（相邻块共享节次时共同生效）
    final startSeen = <int>{};
    final endSeen = <int>{};

    for (final block in blocks) {
      if (_isValidHm(block.startTime)) {
        _apply(result, startSeen, block.startSection, block.startTime,
            isStart: true);
      }
      if (_isValidHm(block.endTime)) {
        _apply(result, endSeen, block.endSection, block.endTime,
            isStart: false);
      }
    }

    return result;
  }

  /// 将 [value] 写入 [result] 中第 [section] 节次的对应字段；
  /// 已定过值的节次直接跳过（冲突保留第一个）
  static void _apply(
    List<TimeSlot> result,
    Set<int> seen,
    int section,
    String value, {
    required bool isStart,
  }) {
    if (seen.contains(section)) return;
    final idx = result.indexWhere((s) => s.section == section);
    if (idx < 0) return; // 节次不存在，跳过
    seen.add(section);
    result[idx] = isStart
        ? result[idx].copyWith(startTime: value)
        : result[idx].copyWith(endTime: value);
  }

  /// 校验 "HH:mm" 格式（1~2 位小时 + 2 位分钟），非法/空值一律跳过
  static bool _isValidHm(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m == null) return false;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    return h >= 0 && h <= 23 && min >= 0 && min <= 59;
  }
}
