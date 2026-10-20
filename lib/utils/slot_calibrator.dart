import '../models/time_slot.dart';
import 'ics_parser.dart';

/// 按导入课表文件校准作息时间（网格重建版）
///
/// 旧版只覆盖「块首节开始 / 块末节结束」，其余节次保留原作息的值；当原作息
/// 与真实作息结构不一致时（例如默认 12 节 4/4/4、真实 13 节 5/4/4），
/// 就会拼出「第 5 节 14:00-12:00」这类开始晚于结束的倒置时间。
///
/// 新版把校准当作网格重建，分五步：
/// 1. 收集课表块给出的已知边界：块开始时间 → 首节开始，块结束时间 → 末节
///    结束；同一节次同一字段冲突时保留第一个（与旧版一致）。
/// 2. 由「起止都已知」的节次推导统一课时（取众数，如 40 分钟）。
/// 3. 用课时互推同一节的起止（有开始补结束、有结束补开始）。
/// 4. 用多节块的跨度方程分配段内课间，再链式补齐其余未知边界；
///    跨段的块（午休/晚餐包含在跨度内）不参与课间分配，避免污染分段间隔。
/// 5. 合法性兜底：逐节保证开始早于结束、相邻节次不重叠；块给出的已知值
///    冲突时保开始顺延结束。绝不输出倒置或重叠的时间段。
///
/// 未被课表文件触及的节次保留原值；块引用了作息表之外的节次时自动扩表。
class SlotCalibrator {
  SlotCalibrator._();

  /// 返回校准后的新列表（按节次升序），不修改入参 [slots]
  static List<TimeSlot> calibrate(
      List<TimeSlot> slots, List<IcsTimeBlock> blocks) {
    final base = <int, TimeSlot>{for (final s in slots) s.section: s};
    if (blocks.isEmpty) {
      return [for (final s in slots) s.copyWith()];
    }

    // 全部节次 = 原作息节次 ∪ 块引用节次（块可能引用第 13 节等表外节次）
    final sectionSet = <int>{...base.keys};
    for (final b in blocks) {
      sectionSet.add(b.startSection);
      sectionSet.add(b.endSection);
    }
    final ordered = sectionSet.toList()..sort();

    // —— 第 1 步：已知边界（分钟数），冲突保留第一个 ——
    final ks = <int, int>{}; // known start
    final ke = <int, int>{}; // known end
    for (final b in blocks) {
      final st = _parseHm(b.startTime);
      final en = _parseHm(b.endTime);
      if (st != null) ks.putIfAbsent(b.startSection, () => st);
      if (en != null) ke.putIfAbsent(b.endSection, () => en);
    }

    // —— 第 2 步：统一课时（众数） ——
    final lesson = _modeLesson(ks, ke);

    if (lesson != null) {
      // —— 第 3 步：同节起止互推 ——
      for (final sec in ordered) {
        if (ks.containsKey(sec) && !ke.containsKey(sec)) {
          ke[sec] = ks[sec]! + lesson;
        }
        if (ke.containsKey(sec) && !ks.containsKey(sec)) {
          ks[sec] = ke[sec]! - lesson;
        }
      }

      // —— 第 4 步：课间分配 + 链式补齐 ——
      final gaps = <int, int>{}; // gaps[k] = 第 k 节与第 k+1 节之间的课间
      for (var i = 0; i + 1 < ordered.length; i++) {
        final a = ordered[i], b = ordered[i + 1];
        if (b == a + 1 && ke.containsKey(a) && ks.containsKey(b)) {
          final g = ks[b]! - ke[a]!;
          if (g >= 0 && g <= 40) gaps[a] = g;
        }
      }
      for (final blk in blocks) {
        final n = blk.endSection - blk.startSection + 1;
        if (n < 2) continue;
        final s0 = ks[blk.startSection];
        final e0 = ke[blk.endSection];
        if (s0 == null || e0 == null) continue;
        final totalBreak = (e0 - s0) - n * lesson;
        if (totalBreak < 0) continue;
        var knownSum = 0;
        var unknown = 0;
        for (var k = blk.startSection; k < blk.endSection; k++) {
          if (gaps.containsKey(k)) {
            knownSum += gaps[k]!;
          } else {
            unknown++;
          }
        }
        if (unknown == 0) continue;
        final rest = totalBreak - knownSum;
        if (rest < 0) continue;
        final each = rest ~/ unknown;
        if (each > 40) continue; // 跨段块（午/晚餐在跨度内），不参与分配
        var rem = rest % unknown;
        for (var k = blk.startSection; k < blk.endSection; k++) {
          if (!gaps.containsKey(k)) {
            gaps[k] = each + (rem > 0 ? 1 : 0);
            if (rem > 0) rem--;
          }
        }
      }
      // 链式补齐：已知一侧边界 + 课间 → 推出相邻节次边界，反复直到稳定
      var changed = true;
      while (changed) {
        changed = false;
        for (var i = 0; i + 1 < ordered.length; i++) {
          final a = ordered[i], b = ordered[i + 1];
          if (b != a + 1 || !gaps.containsKey(a)) continue;
          if (!ks.containsKey(b) && ke.containsKey(a)) {
            ks[b] = ke[a]! + gaps[a]!;
            ke.putIfAbsent(b, () => ks[b]! + lesson);
            changed = true;
          }
          if (!ke.containsKey(a) && ks.containsKey(b)) {
            ke[a] = ks[b]! - gaps[a]!;
            ks.putIfAbsent(a, () => ke[a]! - lesson);
            changed = true;
          }
        }
      }
      // 仍未知的边界：用已知课间中位数从相邻已知处补（缺省 10 分钟）。
      // 只补「扩表新增的节次」或「已有任一侧推导值的节次」，
      // 完全未被课表触及且有原值的节次不臆测，保留原值。
      final defGap = _median(gaps.values.toList()) ?? 10;
      for (var i = 0; i + 1 < ordered.length; i++) {
        final a = ordered[i], b = ordered[i + 1];
        if (b != a + 1) continue;
        if (!ks.containsKey(b) &&
            ke.containsKey(a) &&
            (!base.containsKey(b) || ke.containsKey(b))) {
          ks[b] = ke[a]! + defGap;
          ke.putIfAbsent(b, () => ks[b]! + lesson);
        }
        if (!ke.containsKey(a) &&
            ks.containsKey(b) &&
            (!base.containsKey(a) || ks.containsKey(a))) {
          ke[a] = ks[b]! - defGap;
          ks.putIfAbsent(a, () => ke[a]! - lesson);
        }
      }
    }

    // —— 第 5 步：合并（已知/推导优先，原值兜底）+ 合法性兜底 ——
    final fallbackLesson = lesson ?? _medianBaseDuration(base) ?? 45;
    final result = <TimeSlot>[];
    var prevEnd = -1;
    for (final sec in ordered) {
      int? st = ks[sec] ??
          (base[sec] == null ? null : _parseHm(base[sec]!.startTime));
      int? en = ke[sec] ??
          (base[sec] == null ? null : _parseHm(base[sec]!.endTime));
      if (st == null && en == null) {
        // 完全无依据的节次（扩表且无任何块覆盖）：接在上一节之后
        st = prevEnd >= 0 ? prevEnd + 10 : 8 * 60;
        en = st + fallbackLesson;
      } else if (st == null) {
        st = en! - fallbackLesson;
      } else if (en == null) {
        en = st + fallbackLesson;
      }
      var start = st, end = en;
      // 倒置修复：开始必须早于结束
      if (end <= start) {
        if (ke.containsKey(sec) && !ks.containsKey(sec)) {
          start = end - fallbackLesson; // 结束是文件给的，保结束反推开始
        } else {
          end = start + fallbackLesson; // 其余情况保开始顺延结束
        }
      }
      // 重叠修复：本节开始不得早于上一节结束（已知开始与上节冲突时贴合）
      if (prevEnd >= 0 && start < prevEnd) {
        start = prevEnd + (ks.containsKey(sec) ? 0 : 10);
        if (end <= start) end = start + fallbackLesson;
      }
      start = start.clamp(0, 1439);
      end = end.clamp(0, 1439);
      result.add(TimeSlot(
          section: sec, startTime: _hm(start), endTime: _hm(end)));
      prevEnd = end;
    }
    return result;
  }

  /// 由起止都已知的节次推导统一课时：时长在 20~90 分钟内才计入，取众数
  static int? _modeLesson(Map<int, int> ks, Map<int, int> ke) {
    final counts = <int, int>{};
    for (final sec in ks.keys) {
      final e = ke[sec];
      if (e == null) continue;
      final d = e - ks[sec]!;
      if (d >= 20 && d <= 90) counts[d] = (counts[d] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    var best = counts.keys.first;
    for (final d in counts.keys) {
      if (counts[d]! > counts[best]! ||
          (counts[d]! == counts[best]! && d < best)) {
        best = d;
      }
    }
    return best;
  }

  /// 原作息各节时长中位数（推导不出统一课时时作兜底课时）
  static int? _medianBaseDuration(Map<int, TimeSlot> base) {
    final durations = <int>[];
    for (final s in base.values) {
      final st = _parseHm(s.startTime);
      final en = _parseHm(s.endTime);
      if (st != null && en != null && en > st) durations.add(en - st);
    }
    return _median(durations);
  }

  static int? _median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// "HH:mm"（时可 1~2 位）→ 当天分钟数；非法/空值返回 null（跳过该值）
  static int? _parseHm(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h < 0 || h > 23 || min < 0 || min > 59) return null;
    return h * 60 + min;
  }

  static String _hm(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
