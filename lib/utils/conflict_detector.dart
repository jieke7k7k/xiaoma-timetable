import '../models/course.dart';

/// 课程时间冲突检测
///
/// 判定规则：同一学期内，两门课程若「同一星期 + 存在重合周次 + 存在重合节次」，
/// 即视为时间冲突。
///
/// 检测结果给出具体冲突详情（哪周哪节冲突），供 UI 弹窗让用户选择
/// 跳过新课 / 覆盖旧课 / 保留两者。
class ConflictDetector {
  ConflictDetector._();

  /// 检测 [candidate] 与已有课程列表 [existing] 之间的冲突
  ///
  /// 返回所有冲突详情；无冲突返回空列表。
  static List<CourseConflict> detect(
    Course candidate,
    List<Course> existing, {
    int? ignoreCourseId,
  }) {
    final conflicts = <CourseConflict>[];
    for (final other in existing) {
      if (other.id != null && other.id == ignoreCourseId) continue;
      if (other.id != null && other.id == candidate.id) continue;
      final conflict = _conflictBetween(candidate, other);
      if (conflict != null) conflicts.add(conflict);
    }
    return conflicts;
  }

  static CourseConflict? _conflictBetween(Course a, Course b) {
    // 同一星期？
    if (a.dayOfWeek != b.dayOfWeek) return null;
    // 节次重合？
    if (a.endSection < b.startSection || b.endSection < a.startSection) {
      return null;
    }
    // 周次重合？
    final overlapWeeks =
        a.weeks.where((w) => b.weeks.contains(w)).toList()..sort();
    if (overlapWeeks.isEmpty) return null;
    // 节次重合区间
    final overlapStart =
        a.startSection > b.startSection ? a.startSection : b.startSection;
    final overlapEnd = a.endSection < b.endSection ? a.endSection : b.endSection;
    return CourseConflict(
      courseA: a,
      courseB: b,
      overlapWeeks: overlapWeeks,
      overlapSections: [
        for (var s = overlapStart; s <= overlapEnd; s++) s,
      ],
    );
  }
}

/// 一次冲突的详细描述
class CourseConflict {
  const CourseConflict({
    required this.courseA,
    required this.courseB,
    required this.overlapWeeks,
    required this.overlapSections,
  });

  final Course courseA;
  final Course courseB;
  final List<int> overlapWeeks;
  final List<int> overlapSections;

  /// 冲突的人类可读描述，如：
  /// 「《药物分析》与《药理学》在第 1、3、5 周的 周一 第 3-4 节 时间冲突」
  String describe() {
    final weekText = _joinWeeks(overlapWeeks);
    final sectionText = overlapSections.length == 1
        ? '第 ${overlapSections.first} 节'
        : '第 ${overlapSections.first}-${overlapSections.last} 节';
    return '《${courseA.name}》与《${courseB.name}》'
        '在第 $weekText 周的 周${_weekdayName(courseA.dayOfWeek)} $sectionText 时间冲突';
  }

  static const _weekdayNames = ['', '一', '二', '三', '四', '五', '六', '日'];

  static String _weekdayName(int dayOfWeek) =>
      (dayOfWeek >= 1 && dayOfWeek <= 7) ? _weekdayNames[dayOfWeek] : '$dayOfWeek';

  static String _joinWeeks(List<int> weeks) {
    if (weeks.length <= 5) return weeks.join('、');
    return '${weeks.first}、${weeks[1]}、…、${weeks.last}';
  }
}
