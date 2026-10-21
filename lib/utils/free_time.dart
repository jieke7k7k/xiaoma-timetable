import '../models/course.dart';
import '../models/time_slot.dart';

/// 空闲时段计算（1.2.0）
///
/// 给定某周的有效课程与作息表，算出每天连续无课的节次区间，
/// 供「空闲时段」页排自习/约时间时一眼看全。全为纯函数。

/// 一段空闲时间（某天连续无课的节次区间）
class FreeBlock {
  const FreeBlock({
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    required this.startTime,
    required this.endTime,
  });

  final int dayOfWeek;
  final int startSection;
  final int endSection;

  /// 起始节上课时间 / 结束节下课时间（HH:mm 文本，来自作息表）
  final String startTime;
  final String endTime;

  int get sectionCount => endSection - startSection + 1;

  /// 时长（分钟，按起止时间算；解析失败为 0）
  int get minutes {
    final s = _toMinutes(startTime);
    final e = _toMinutes(endTime);
    if (s == null || e == null || e <= s) return 0;
    return e - s;
  }

  /// 「约 2 小时 20 分」式时长文本
  String get durationText {
    final m = minutes;
    if (m <= 0) return '';
    if (m < 60) return '约 $m 分钟';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '约 $h 小时' : '约 $h 小时 $r 分钟';
  }

  static int? _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final min = int.tryParse(parts[1]);
    if (h == null || min == null) return null;
    return h * 60 + min;
  }
}

/// 计算一周内每天的空闲时段（按星期、节次升序）。
///
/// [weekCourses] 须为该周有效课程（已应用单次调课、已按 isActiveInWeek 过滤）。
/// 空闲 = 作息节次全集（最小节 ~ 最大节）减去被占节次后的连续区间；
/// 整天没课时返回覆盖全天的一段（页面据此显示「全天没课」）。
List<FreeBlock> freeBlocksForWeek(
    List<Course> weekCourses, List<TimeSlot> timeSlots) {
  if (timeSlots.isEmpty) return const [];
  final slots = [...timeSlots]..sort((a, b) => a.section.compareTo(b.section));
  final bySection = {for (final s in slots) s.section: s};
  final first = slots.first.section;
  final last = slots.last.section;
  final result = <FreeBlock>[];
  for (var day = 1; day <= 7; day++) {
    final busy = <int>{};
    for (final c in weekCourses) {
      if (c.dayOfWeek != day) continue;
      for (var s = c.startSection; s <= c.endSection; s++) {
        busy.add(s);
      }
    }
    var runStart = -1;
    for (var sec = first; sec <= last + 1; sec++) {
      final isFree =
          sec <= last && !busy.contains(sec) && bySection.containsKey(sec);
      if (isFree && runStart < 0) runStart = sec;
      if (!isFree && runStart >= 0) {
        result.add(FreeBlock(
          dayOfWeek: day,
          startSection: runStart,
          endSection: sec - 1,
          startTime: bySection[runStart]!.startTime,
          endTime: bySection[sec - 1]!.endTime,
        ));
        runStart = -1;
      }
    }
  }
  return result;
}
