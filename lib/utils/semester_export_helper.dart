import '../models/course.dart';
import 'week_parser.dart';

/// 方案 C 全学期母版格子类型（WB_SPEC_239 §3 & §4）
enum SemesterMasterSlotKind {
  single, // 单门课独占
  conflict, // 真冲突 或 半学期前后交接（画焦糖渐变冲突块）
  parityPair, // 单双周交错同格（上下各自配色并排，不画焦糖块）
  stack, // 同格 ≥3 门（P1-1 多行分块兜底：全部课程纵向叠排，不丢课）
}

/// 方案 C 全学期母版单个课程块描述
class SemesterMasterSlot {
  const SemesterMasterSlot({
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    required this.kind,
    required this.courses,
    this.conflictPair,
  });

  final int dayOfWeek;
  final int startSection;
  final int endSection;
  final SemesterMasterSlotKind kind;
  final List<Course> courses;
  final SemesterConflictPair? conflictPair;

  int get span => endSection - startSection + 1;
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

/// 整学期导出辅助类（WB_SPEC_237 / WB_SPEC_239）：
/// 负责自动计算整学期最大周数 N、冲突分组判定及方案 C 全学期母版布局。
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

  /// 获取取某门课实际生效的周次集合（结合 weekType 单双周过滤）
  static Set<int> effectiveWeeksOf(Course c) {
    return c.weeks.where((w) {
      if (c.weekType == 1) return w.isOdd;
      if (c.weekType == 2) return w.isEven;
      return true;
    }).toSet();
  }

  /// 判定两门课是否形成冲突块（真冲突 或 半学期前后交接；单双周交错返回 null）：
  /// - [week]：传具体周次时，校验该周是否至少有一门课活跃（供周视图/单周PNG使用）；
  ///   传 null 时代表全学期母版（WB_SPEC_239 方案 C），只要全学期内有课即判定。
  static SemesterConflictPair? checkConflict(
    Course a,
    Course b, [
    int? week,
  ]) {
    if (a.dayOfWeek != b.dayOfWeek) return null;
    if (a.endSection < b.startSection || b.endSection < a.startSection) {
      return null;
    }

    final wa = effectiveWeeksOf(a);
    final wb = effectiveWeeksOf(b);
    if (wa.isEmpty || wb.isEmpty) return null;

    if (week != null) {
      // 指定周次时，校验该周是否至少有一门课活跃（既不在 wa 也不在 wb 内则不展示）
      if (!wa.contains(week) && !wb.contains(week)) {
        return null;
      }
    }

    // 1. 真冲突：有效周次有交集 (WA ∩ WB ≠ ∅)
    if (wa.intersection(wb).isNotEmpty) {
      return _buildPair(a, b, wa, wb);
    }

    // 2. 前后交接：无交集，且先开始的一门在另一门开始之前完全结束（如 1–8 周与 9–16 周）
    final minA = wa.reduce((x, y) => x < y ? x : y);
    final maxA = wa.reduce((x, y) => x > y ? x : y);
    final minB = wb.reduce((x, y) => x < y ? x : y);
    final maxB = wb.reduce((x, y) => x > y ? x : y);

    if (maxA < minB || maxB < minA) {
      return _buildPair(a, b, wa, wb);
    }

    // 3. 单双周交错等情况：不画冲突块
    return null;
  }

  static SemesterConflictPair _buildPair(
    Course a,
    Course b,
    Set<int> wa,
    Set<int> wb,
  ) {
    final minA = wa.reduce((x, y) => x < y ? x : y);
    final minB = wb.reduce((x, y) => x < y ? x : y);
    if (minA < minB) {
      return SemesterConflictPair(topCourse: a, bottomCourse: b);
    } else if (minB < minA) {
      return SemesterConflictPair(topCourse: b, bottomCourse: a);
    } else {
      // 首周相同时按课程名称稳定排序
      return a.name.compareTo(b.name) <= 0
          ? SemesterConflictPair(topCourse: a, bottomCourse: b)
          : SemesterConflictPair(topCourse: b, bottomCourse: a);
    }
  }

  /// 生成方案 C（全学期一张图）某一天的课程块布局列表
  static List<SemesterMasterSlot> layoutSemesterMasterDay({
    required List<Course> dayCourses,
    required int dayOfWeek,
    required int maxSection,
  }) {
    final valid = dayCourses
        .where(
          (c) =>
              c.dayOfWeek == dayOfWeek &&
              effectiveWeeksOf(c).isNotEmpty &&
              c.startSection <= maxSection,
        )
        .toList();
    if (valid.isEmpty) return const [];

    // 将节次有重叠的课程归入连通组
    final sorted = [...valid]
      ..sort((a, b) {
        final c = a.startSection.compareTo(b.startSection);
        return c != 0 ? c : a.endSection.compareTo(b.endSection);
      });

    final result = <SemesterMasterSlot>[];
    var i = 0;
    while (i < sorted.length) {
      final group = <Course>[sorted[i]];
      int groupStart = sorted[i].startSection.clamp(1, maxSection);
      int groupEnd = sorted[i].endSection.clamp(1, maxSection);
      var j = i + 1;
      while (j < sorted.length && sorted[j].startSection <= groupEnd) {
        group.add(sorted[j]);
        final endJ = sorted[j].endSection.clamp(1, maxSection);
        if (endJ > groupEnd) groupEnd = endJ;
        j++;
      }

      if (group.length == 1) {
        result.add(
          SemesterMasterSlot(
            dayOfWeek: dayOfWeek,
            startSection: groupStart,
            endSection: groupEnd,
            kind: SemesterMasterSlotKind.single,
            courses: group,
          ),
        );
      } else if (group.length == 2) {
        final pair = checkConflict(group[0], group[1]);
        if (pair != null) {
          result.add(
            SemesterMasterSlot(
              dayOfWeek: dayOfWeek,
              startSection: groupStart,
              endSection: groupEnd,
              kind: SemesterMasterSlotKind.conflict,
              courses: [pair.topCourse, pair.bottomCourse],
              conflictPair: pair,
            ),
          );
        } else {
          // 单双周同格交错：上下双色并排，不画焦糖冲突块
          result.add(
            SemesterMasterSlot(
              dayOfWeek: dayOfWeek,
              startSection: groupStart,
              endSection: groupEnd,
              kind: SemesterMasterSlotKind.parityPair,
              courses: [group[0], group[1]],
            ),
          );
        }
      } else {
        // P1-1：同格 ≥3 门不再只取前两门（第 3 门起会静默丢失）——
        // 多行分块兜底：组内全部课程纵向叠排，每门各占一行（带周次胶囊），
        // 不画冲突块、不做两两判定。237 §14 第 3 条的「不存在则不处理」是
        // 按测试学期数据（最大同格 2 门）写的；课程模型本身不限制同格门数，
        // 用户正常加课就能造出 3 门同格，所以这里必须兜底，不能丢课。
        result.add(
          SemesterMasterSlot(
            dayOfWeek: dayOfWeek,
            startSection: groupStart,
            endSection: groupEnd,
            kind: SemesterMasterSlotKind.stack,
            courses: group,
          ),
        );
      }
      i = j;
    }

    return result;
  }

  /// 格式化课程周次胶囊文案（如 "1-18周"、"1-15单周"、"2-16双周"、"第3周"、"1-3, 5-8周"）
  static String formatWeekCapsule(Course c) {
    final eff = effectiveWeeksOf(c).toList()..sort();
    if (eff.isEmpty) return '';
    // 仅剩单周时优先显示「第X周」，避免出现「3-3单周」
    if (eff.length == 1) return '第${eff.first}周';

    // 检测是否为等差步长为 2 的连续纯单周 / 纯双周
    var isStep2 = true;
    for (var i = 1; i < eff.length; i++) {
      if (eff[i] - eff[i - 1] != 2) {
        isStep2 = false;
        break;
      }
    }
    if (isStep2) {
      if (eff.every((w) => w.isOdd)) return '${eff.first}-${eff.last}单周';
      if (eff.every((w) => w.isEven)) return '${eff.first}-${eff.last}双周';
    }

    // 连续单区间（如 1-18）与非连续多段（如 1-3, 5-12）统一复用 WeekParser.toText
    return '${WeekParser.toText(eff, WeekParser.allWeeks)}周';
  }
}