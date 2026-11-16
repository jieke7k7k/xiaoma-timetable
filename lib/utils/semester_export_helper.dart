import '../models/course.dart';

/// 整学期导出辅助类（WB_SPEC_237 §3 & §4）：
/// 负责自动计算整学期最大周数 N 以及课程时间冲突分组判定。
class SemesterExportHelper {
  SemesterExportHelper._();

  /// 计算整学期总周数 N：按当前学期全部课程的 weeks 集合取最大值。
  /// 若无任何课程，返回 0。
  static int calculateMaxWeek(List<Course> courses) {
    if (courses.isEmpty) return 0;
    int maxW = 0;
    for (final c in courses) {
      for (final w in c.weeks) {
        if (w > maxW) maxW = w;
      }
    }
    return maxW;
  }

  /// 判定两门课在指定星期与节次范围内是否形成 WB_SPEC_237 冲突块：
  /// - 规则 1（真冲突）：周次有交集 (WA ∩ WB ≠ ∅)
  /// - 规则 2（前后交接）：周次无交集，但一门在另一门结束之后开始（如 1–8 周与 9–16 周）
  /// - 规则 3（交错）：如单双周交错，不画冲突块。
  static SemesterConflictPair? checkConflict(Course a, Course b, int week) {
    // 必须是同一星期且节次范围有重合
    if (a.dayOfWeek != b.dayOfWeek) return null;
    if (a.endSection < b.startSection || b.endSection < a.startSection) return null;
    // 周次为空的课不属于任何一周，不参与冲突分组
    if (a.weeks.isEmpty || b.weeks.isEmpty) return null;

    // 当周这两门课是否物理上有至少一门生效
    final aActive = a.isActiveInWeek(week);
    final bActive = b.isActiveInWeek(week);
    if (!aActive && !bActive) return null;

    final wa = a.weeks.toSet();
    final wb = b.weeks.toSet();

    // 1. 真冲突：周次有交集
    final intersection = wa.intersection(wb);
    if (intersection.isNotEmpty) {
      return _buildPair(a, b);
    }

    // 2. 前后交接：无交集且首周较早的一门完全在另一门开始之前结束
    // 按首周排序判定
    final minA = wa.isEmpty ? 999 : wa.reduce((x, y) => x < y ? x : y);
    final minB = wb.isEmpty ? 999 : wb.reduce((x, y) => x < y ? x : y);
    final maxA = wa.isEmpty ? 0 : wa.reduce((x, y) => x > y ? x : y);
    final maxB = wb.isEmpty ? 0 : wb.reduce((x, y) => x > y ? x : y);

    if (maxA < minB || maxB < minA) {
      return _buildPair(a, b);
    }

    return null;
  }

  static SemesterConflictPair _buildPair(Course a, Course b) {
    final minA = a.weeks.isEmpty ? 0 : a.weeks.reduce((x, y) => x < y ? x : y);
    final minB = b.weeks.isEmpty ? 0 : b.weeks.reduce((x, y) => x < y ? x : y);
    // 上半 = 先开始的那门（首周更小），标「前半学期」；下半 = 后半学期
    if (minA <= minB) {
      return SemesterConflictPair(topCourse: a, bottomCourse: b);
    } else {
      return SemesterConflictPair(topCourse: b, bottomCourse: a);
    }
  }
}

/// 冲突课程对描述
class SemesterConflictPair {
  const SemesterConflictPair({
    required this.topCourse,
    required this.bottomCourse,
  });

  final Course topCourse;
  final Course bottomCourse;
}
