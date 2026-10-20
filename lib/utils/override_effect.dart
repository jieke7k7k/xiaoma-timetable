import '../models/course.dart';
import '../models/course_override.dart';

/// 单次调课（阶段五·节假日调课）的纯逻辑工具
///
/// 全部为纯函数，不依赖 Flutter / 平台通道，便于单元测试。
/// 周视图渲染、上课提醒（reminder_plan）、常驻通知（ongoing_notice）、
/// 桌面小组件（widget_service）在计算「某周/某天有哪些课」时，
/// 都必须先经过这里应用单次调课，保证四处口径一致。
///
/// 语义约定（与 course_override.dart 模型注释一致）：
/// - 每条 CourseOverride 针对 (courseId, originalWeek) 的那一次上课；
/// - originalWeek 指当前学期开学起算的第几周（与周视图浏览周对应）；
/// - targetWeek == cancelFlag 表示「本次停课」；
/// - 调整类型（非停课）targetWeek == originalWeek：只在本周内改星期/节次/教室，
///   星期与节次总是存完整值（用户没改就存原值），教室为 null 表示沿用原教室；
/// - 调课只影响这一次，不改变课程本身的周次规律（weeks 不动）；
/// - 若课程在 originalWeek 本就不上课（weeks 不含该周），该条 override 无效，忽略。

/// 取某周的全部调课记录，按课程 id 索引。
/// 同一 (courseId, originalWeek) 至多一条（落库时 upsert 已保证），后者覆盖前者。
Map<int, CourseOverride> overridesForWeek(
    List<CourseOverride> overrides, int week) {
  final map = <int, CourseOverride>{};
  for (final o in overrides) {
    if (o.originalWeek == week) {
      map[o.courseId] = o;
    }
  }
  return map;
}

/// 某课程在 [week] 周的单次调课记录；没有则返回 null
CourseOverride? overrideForCourse(
    List<CourseOverride> overrides, int courseId, int week) {
  for (final o in overrides) {
    if (o.courseId == courseId && o.originalWeek == week) return o;
  }
  return null;
}

/// [week] 周被「调整」（非停课）的课程 id 集合，周视图渲染「调」角标用
Set<int> movedCourseIds(List<CourseOverride> overrides, int week) => {
      for (final o in overrides)
        if (o.originalWeek == week && !o.isCancellation) o.courseId,
    };

/// 应用单次调课后，[week] 周的有效上课实例列表。
///
/// 规则：
/// 1. 该周有「停课」记录的课程：移除（本次不显示/不提醒）；
/// 2. 该周有「调整」记录的课程：替换为改过星期/节次/教室的副本
///    （copyWith 不改 weeks，其他周不受影响）；
/// 3. 该周没有调课记录、或课程该周本就不上课：原样保留
///    （非本周课程原样返回，由调用方自行按 isActiveInWeek 过滤置灰）。
List<Course> effectiveCoursesForWeek({
  required List<Course> courses,
  required List<CourseOverride> overrides,
  required int week,
}) {
  final byCourse = overridesForWeek(overrides, week);
  final result = <Course>[];
  for (final c in courses) {
    // 草稿课程（id 为空，导入核对场景）不可能有调课记录，原样保留
    final o = c.id == null ? null : byCourse[c.id!];
    // 课程该周本就不上课：override 无效，忽略
    if (o == null || !c.isActiveInWeek(week)) {
      result.add(c);
      continue;
    }
    if (o.isCancellation) continue; // 本次停课：直接移除
    result.add(c.copyWith(
      dayOfWeek: o.targetDayOfWeek ?? c.dayOfWeek,
      startSection: o.targetStartSection ?? c.startSection,
      endSection: o.targetEndSection ?? c.endSection,
      // 教室为 null 表示沿用原教室
      classroom: o.targetClassroom ?? c.classroom,
    ));
  }
  return result;
}

/// 检查一次单次调课落库前是否与其他课冲突（仅针对本次所在周）。
///
/// 返回冲突的中文描述列表（可直接展示给用户），空列表表示无冲突。
/// 检查范围：
/// 1. 其他课程在 originalWeek 周的正常排课（跳过该周已停课/已被调整替换的课程，
///    被调整的课程改查它的新位置，见第 2 条）；
/// 2. 其他课程在同一周的单次调整（调到同一天且节次重叠）。
/// 本课程自己原来的上课时间不算冲突——它已被本次调整替换。
List<String> checkOverrideConflicts({
  required Course course,
  required CourseOverride override,
  required List<Course> allCourses,
  required List<CourseOverride> allOverrides,
}) {
  if (override.isCancellation) return const [];
  final week = override.originalWeek;
  final day = override.targetDayOfWeek ?? course.dayOfWeek;
  final start = override.targetStartSection ?? course.startSection;
  final end = override.targetEndSection ?? course.endSection;

  // 该周已停课 / 已被调整的课程 id：它们的「原位置」已不存在，不能算冲突
  final cancelledIds = <int>{};
  final movedIds = <int>{};
  for (final o in allOverrides) {
    if (o.originalWeek != week || o.courseId == course.id) continue;
    if (o.isCancellation) {
      cancelledIds.add(o.courseId);
    } else {
      movedIds.add(o.courseId);
    }
  }

  // 节次区间是否重叠（端点相接不算：第 2 节结束与第 3 节开始不冲突）
  bool overlaps(int otherStart, int otherEnd) =>
      end >= otherStart && otherEnd >= start;

  String sectionText() =>
      start == end ? '第 $start 节' : '第 $start-$end 节';

  final conflicts = <String>[];

  // 1. 与其他课程的正常排课比
  for (final other in allCourses) {
    if (other.id == null || other.id == course.id) continue;
    if (cancelledIds.contains(other.id) || movedIds.contains(other.id)) {
      continue;
    }
    if (!other.isActiveInWeek(week)) continue;
    if (other.dayOfWeek != day) continue;
    if (!overlaps(other.startSection, other.endSection)) continue;
    conflicts.add('与《${other.name}》的正常排课时间冲突'
        '（周${weekdayName(day)} ${sectionText()}）');
  }

  // 2. 与其他课程同周的单次调整比（两者都调到了同一时段）
  for (final o in allOverrides) {
    if (o.isCancellation ||
        o.courseId == course.id ||
        o.originalWeek != week ||
        !movedIds.contains(o.courseId)) {
      continue;
    }
    final other = _findById(allCourses, o.courseId);
    if (other == null) continue; // 找不到课程定义，无法判定，跳过
    final oDay = o.targetDayOfWeek ?? other.dayOfWeek;
    final oStart = o.targetStartSection ?? other.startSection;
    final oEnd = o.targetEndSection ?? other.endSection;
    if (oDay != day) continue;
    if (!overlaps(oStart, oEnd)) continue;
    conflicts.add('与《${other.name}》的单次调整时间冲突'
        '（周${weekdayName(day)} ${sectionText()}）');
  }
  return conflicts;
}

/// 单次调整的中文描述，供长按菜单/调整页展示：
/// - 停课：「本次停课」
/// - 调整：「调至 周三 第 3-4 节 · B203」（教室为空省略）
String describeOverride(CourseOverride o) {
  if (o.isCancellation) return '本次停课';
  final day = o.targetDayOfWeek;
  final start = o.targetStartSection;
  final end = o.targetEndSection;
  final parts = <String>['调至'];
  if (day != null) parts.add('周${weekdayName(day)}');
  if (start != null && end != null) {
    parts.add(start == end ? '第 $start 节' : '第 $start-$end 节');
  }
  final room = o.targetClassroom;
  if (room != null && room.trim().isNotEmpty) parts.add(room.trim());
  return parts.join(' ');
}

Course? _findById(List<Course> courses, int? id) {
  if (id == null) return null;
  for (final c in courses) {
    if (c.id == id) return c;
  }
  return null;
}

/// 星期数字 → 中文名（周一=1 … 周日=7）
String weekdayName(int dayOfWeek) {
  const names = ['', '一', '二', '三', '四', '五', '六', '日'];
  if (dayOfWeek >= 1 && dayOfWeek <= 7) return names[dayOfWeek];
  return '$dayOfWeek';
}
