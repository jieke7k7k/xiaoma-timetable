import '../models/course.dart';

/// 周视图「日 × 节」格子三态解析（纯 Dart，无 Flutter 依赖，可单元测试）
///
/// 思路借鉴 SchedU（MIT）的三态解析：渲染前先把每一天的每个节次解析成
/// empty（无课）/ single（一门课）/ multi（多门课冲突），UI 只负责摆放。
/// 这样可以从根本上避免两类遮挡坑：
/// 1. 非本周置灰课盖住本周课 —— 本周生效课程永远优先同节渲染；
/// 2. 同格多门课互相覆盖 —— multi 态统一收敛为一张卡片 + 「+N」角标。
///
/// 优先级规则：
/// - 某节次只要有本周生效课程，非本周课程一律不显示（即使开了「显示非本周课程」）；
/// - 非本周课程只在开关开启、且该节次无本周课时才出现（置灰）；
/// - 连续同态（同一门课 / 同一组课 / 同为置灰）的节次合并为一段，方便绝对定位。

/// 格子显示种类
enum SlotKind {
  /// 无课
  empty,

  /// 一门课独占
  single,

  /// 多门课冲突（本周）或多门非本周课同格
  multi,
}

/// 一个连续节次段的显示单元：一段 = 周视图上的一张卡片
class DisplaySlot {
  const DisplaySlot({
    required this.startSection,
    required this.endSection,
    required this.kind,
    required this.courses,
    required this.dimmed,
  });

  final int startSection;
  final int endSection;
  final SlotKind kind;

  /// 本段要显示的课程：single 时 1 门，multi 时多门，empty 时为空
  final List<Course> courses;

  /// 是否为非本周置灰显示
  final bool dimmed;

  /// 跨越的节次数
  int get span => endSection - startSection + 1;

  bool get isEmpty => kind == SlotKind.empty;

  /// multi 时角标数字（除最上层一张外还有几门）
  int get extraCount => courses.length - 1;
}

/// 某一天的三态布局算法
class SlotLayout {
  SlotLayout._();

  /// 对某一天的课程做逐节三态解析，并把连续同态节次合并为 [DisplaySlot] 列表
  ///
  /// - [dayCourses]：该天的全部课程（本周 + 非本周）
  /// - [week]：当前浏览周次
  /// - [showDimmed]：是否显示非本周课程（置灰）
  /// - [maxSection]：最大节次数，限定解析范围
  static List<DisplaySlot> layoutDay({
    required List<Course> dayCourses,
    required int week,
    required bool showDimmed,
    required int maxSection,
  }) {
    // 第一步：逐节收集，本周课与非本周课分开
    final activeBySection = <int, List<Course>>{};
    final dimmedBySection = <int, List<Course>>{};
    for (final c in dayCourses) {
      final start = c.startSection.clamp(1, maxSection);
      final end = c.endSection.clamp(1, maxSection);
      if (start > end) continue;
      final target = c.isActiveInWeek(week) ? activeBySection : dimmedBySection;
      for (var s = start; s <= end; s++) {
        (target[s] ??= []).add(c);
      }
    }

    // 第二步：逐节定态，本周优先
    final states = <int, _SectionState>{};
    for (var s = 1; s <= maxSection; s++) {
      final actives = activeBySection[s] ?? const <Course>[];
      final dimmedList = dimmedBySection[s] ?? const <Course>[];
      if (actives.isNotEmpty) {
        states[s] = _SectionState(
          actives.length == 1 ? SlotKind.single : SlotKind.multi,
          actives,
          false,
        );
      } else if (showDimmed && dimmedList.isNotEmpty) {
        states[s] = _SectionState(
          dimmedList.length == 1 ? SlotKind.single : SlotKind.multi,
          dimmedList,
          true,
        );
      } else {
        states[s] = const _SectionState(SlotKind.empty, [], false);
      }
    }

    // 第三步：合并连续同态节次为段
    final slots = <DisplaySlot>[];
    var s = 1;
    while (s <= maxSection) {
      final cur = states[s]!;
      var e = s;
      while (e + 1 <= maxSection && _sameState(states[e + 1]!, cur)) {
        e++;
      }
      slots.add(DisplaySlot(
        startSection: s,
        endSection: e,
        kind: cur.kind,
        courses: cur.courses,
        dimmed: cur.dimmed,
      ));
      s = e + 1;
    }
    return slots;
  }

  /// 课程身份键：数据库 id 优先；草稿（id 为空）用 名称#星期#节次 兜底
  static String courseKey(Course c) => c.id != null
      ? 'id:${c.id}'
      : '${c.name}#${c.dayOfWeek}#${c.startSection}-${c.endSection}';

  /// 两节是否可合并为一段：同态 + 同置灰 + 同一组课程（顺序一致）
  static bool _sameState(_SectionState a, _SectionState b) {
    if (a.kind != b.kind || a.dimmed != b.dimmed) return false;
    if (a.courses.length != b.courses.length) return false;
    for (var i = 0; i < a.courses.length; i++) {
      if (courseKey(a.courses[i]) != courseKey(b.courses[i])) return false;
    }
    return true;
  }
}

/// 单个节次的解析状态（内部使用）
class _SectionState {
  const _SectionState(this.kind, this.courses, this.dimmed);

  final SlotKind kind;
  final List<Course> courses;
  final bool dimmed;
}

/// 当前浏览周实际显示的星期列表（7 列或 5 列）
///
/// 开启「周末无课时自动收起」且周六日均无任何需显示课程时，只显示周一~周五。
/// 表头、日列、列宽、点击列号全部由该列表驱动。
List<int> computeDisplayDays(
    List<Course> courses, int week, bool showOther, bool autoCollapse) {
  const all = [1, 2, 3, 4, 5, 6, 7];
  if (!autoCollapse) return all;
  final visible =
      showOther ? courses : courses.where((c) => c.isActiveInWeek(week));
  if (visible.any((c) => c.dayOfWeek == 6 || c.dayOfWeek == 7)) return all;
  return const [1, 2, 3, 4, 5];
}

