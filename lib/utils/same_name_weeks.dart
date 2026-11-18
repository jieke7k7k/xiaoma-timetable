import '../models/course.dart';

/// 一组同名但周数不一致的课程（WB_SPEC_246 §1.2 / §1.4）
class InconsistentWeekGroup {
  /// 课程名（原样，不 trim、不分大小写）
  final String name;

  /// 组内全部行的 id（按星期、开始节次排序）
  final List<int> courseIds;

  /// 组内各不相同的 weeks 集合（每个元素已排序，去重后按出现顺序）
  final List<List<int>> distinctWeeks;

  /// 建议统一的目标 weeks（§1.4 规则选出）
  final List<int> targetWeeks;

  const InconsistentWeekGroup({
    required this.name,
    required this.courseIds,
    required this.distinctWeeks,
    required this.targetWeeks,
  });
}

/// 按集合比较两个 weeks 列表是否相等（排序后逐元素比，§3 硬性要求 3）
bool weeksListEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final sa = List<int>.from(a)..sort();
  final sb = List<int>.from(b)..sort();
  for (var i = 0; i < sa.length; i++) {
    if (sa[i] != sb[i]) return false;
  }
  return true;
}

/// 扫描课程列表，找出「同学期、同名、weeks 集合不一致」的组（WB_SPEC_246 §1.2）。
///
/// - 按 [Course.name] 原样分组（不 trim、不分大小写）；
/// - 组内 ≥2 条且 weeks 作为集合互不相同才算不一致；
/// - weeks 为空列表的课不参与分组；
/// - 只比 weeks，不比 weekType / 老师 / 教室 / 颜色。
List<InconsistentWeekGroup> findInconsistentWeekGroups(List<Course> courses) {
  // 按 name 分组，跳过空 weeks
  final byName = <String, List<Course>>{};
  for (final c in courses) {
    if (c.weeks.isEmpty) continue;
    byName.putIfAbsent(c.name, () => []).add(c);
  }

  final result = <InconsistentWeekGroup>[];
  for (final entry in byName.entries) {
    final group = entry.value;
    if (group.length < 2) continue;

    // 收集各不相同的 weeks 集合，按「周数多 → 范围早」排序，
    // 弹窗里按这个顺序列（如「2–21周 ×2、2–20周、2–19周」）
    final distinct = <List<int>>[];
    for (final c in group) {
      final sorted = List<int>.from(c.weeks)..sort();
      final exists = distinct.any((w) => weeksListEquals(w, sorted));
      if (!exists) distinct.add(sorted);
    }
    if (distinct.length < 2) continue; // 全一致，不检出
    distinct.sort((a, b) {
      final byLen = b.length.compareTo(a.length);
      return byLen != 0 ? byLen : a.first.compareTo(b.first);
    });

    // 组内行按星期、开始节次排序
    final sortedGroup = List<Course>.from(group)
      ..sort((a, b) {
        final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
        return byDay != 0 ? byDay : a.startSection.compareTo(b.startSection);
      });

    result.add(InconsistentWeekGroup(
      name: entry.key,
      courseIds: [
        for (final c in sortedGroup)
          if (c.id != null) c.id!,
      ],
      distinctWeeks: distinct,
      targetWeeks: _pickTargetWeeks(group),
    ));
  }
  return result;
}

/// 按 §1.4 规则选目标 weeks：
/// 1. 取组内最长的 weeks 列表（周数最多）；
/// 2. 并列最长时取出现次数最多的那组；
/// 3. 仍并列时取星期最早、再取开始节次最早的那条。
///
/// key 用「排序后 weeks 拼成的字符串」：Dart 的 List 未重写 ==/hashCode，
/// 不能直接当 Map key（引用相等会漏计等价集合）。
List<int> _pickTargetWeeks(List<Course> group) {
  // 每个 weeks 集合的出现次数与代表课程（星期/节次最早的那条）
  final counts = <String, int>{};
  final weeksByKey = <String, List<int>>{};
  final reps = <String, Course>{};
  for (final c in group) {
    final sorted = List<int>.from(c.weeks)..sort();
    final key = sorted.join(',');
    counts[key] = (counts[key] ?? 0) + 1;
    weeksByKey.putIfAbsent(key, () => sorted);
    final prev = reps[key];
    if (prev == null ||
        c.dayOfWeek < prev.dayOfWeek ||
        (c.dayOfWeek == prev.dayOfWeek &&
            c.startSection < prev.startSection)) {
      reps[key] = c;
    }
  }

  // 1. 最长
  var maxLen = 0;
  for (final k in counts.keys) {
    final len = weeksByKey[k]!.length;
    if (len > maxLen) maxLen = len;
  }
  final longest =
      counts.keys.where((k) => weeksByKey[k]!.length == maxLen).toList();

  // 2. 出现次数最多
  var maxCount = 0;
  for (final k in longest) {
    if (counts[k]! > maxCount) maxCount = counts[k]!;
  }
  final mostFrequent = longest.where((k) => counts[k] == maxCount).toList();

  // 3. 星期最早、再开始节次最早
  mostFrequent.sort((a, b) {
    final ca = reps[a]!;
    final cb = reps[b]!;
    final byDay = ca.dayOfWeek.compareTo(cb.dayOfWeek);
    return byDay != 0 ? byDay : ca.startSection.compareTo(cb.startSection);
  });

  return List<int>.from(weeksByKey[mostFrequent.first]!);
}
