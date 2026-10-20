import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/course_override.dart';
import '../providers/providers.dart';
import '../utils/override_effect.dart';
import '../utils/slot_layout.dart';
import '../utils/week_calc.dart';
import '../ui/app_styles.dart';
import '../widgets/course_card.dart';
import '../widgets/course_detail_sheet.dart';
import '../widgets/empty_state.dart';

/// 周视图主页
///
/// 经典 7 列 × N 节次网格（周末无课时自动收起为 5 列）：
/// - 顶部栏：第 X 周 · 单/双周、当前月份、回到本周；点击展开周次快速跳转条
/// - 表头：月份列 + 周一~周日（几月几日，今天高亮）
/// - 网格：左侧节次号与上下课时间，右侧日期列，跨节次课程合并为圆角卡片
/// - 午休 / 晚间分隔带：位置由「作息分段设置」驱动（默认第 5 / 9 节后），各一条 20px 通栏分隔带（高度守恒）
/// - 格子三态布局（见 slot_layout.dart）：本周课优先，非本周课置灰且不遮挡本周课；
///   同格多课收敛为一张卡片 + 「+N」角标，点击先选课程再进详情
/// - PageView 左右滑动切换周次；严格按 weeksJson 与单双周过滤
class WeekViewPage extends ConsumerStatefulWidget {
  const WeekViewPage({super.key});

  @override
  ConsumerState<WeekViewPage> createState() => _WeekViewPageState();
}

/// 分隔带高度（参与总高度计算，高度守恒）
const _bandHeight = 20.0;

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

/// 第 [section] 节卡片顶部的纵向偏移（含之前分隔带的累计高度）
double yOffsetTop(int section, double rowHeight, int bandCountBefore) =>
    (section - 1) * rowHeight + bandCountBefore * _bandHeight;

/// 第 [section] 节之前有几条分隔带
int bandsBefore(int section, List<({int after, String label})> activeBands) {
  var n = 0;
  for (final b in activeBands) {
    if (section > b.after) n++;
  }
  return n;
}

class _WeekViewPageState extends ConsumerState<WeekViewPage> {
  PageController? _pageController;
  bool _showJumper = false;

  /// 编辑模式：开启后才能点空白新建课程、长按课程编辑/删除；
  /// 关闭时点空白无反应、点课程只看详情，防止误触（用户真机反馈）
  bool _editMode = false;

  /// 时间轴宽度
  static const double _timeAxisWidth = 50;

  @override
  void initState() {
    super.initState();
    final todayWeek = ref.read(todayWeekProvider);
    _pageController = PageController(
      initialPage: todayWeek > 0 ? todayWeek - 1 : 0,
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  void _jumpToWeek(int week) {
    final total = ref.read(currentSemesterProvider).value?.totalWeeks ?? 20;
    if (week < 1 || week > total) return;
    ref.read(displayWeekProvider.notifier).setWeek(week);
    _pageController?.animateToPage(
      week - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToday() {
    final todayWeek = ref.read(todayWeekProvider);
    if (todayWeek <= 0) return;
    _jumpToWeek(todayWeek);
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(currentSemesterProvider).value;
    if (semester == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final displayWeek = ref.watch(displayWeekProvider);
    final todayWeek = ref.watch(todayWeekProvider);
    final courses = ref.watch(coursesProvider).value ?? [];
    final overrides = ref.watch(courseOverridesProvider).value ?? [];
    final showOther = ref.watch(showOtherWeeksProvider);
    final autoCollapse = ref.watch(autoCollapseWeekendProvider);
    // 周末自适应收起也要看调课结果：某节课被单次调到周六/周日时不能收起
    final displayWeekCourses = effectiveCoursesForWeek(
        courses: courses, overrides: overrides, week: displayWeek);
    final displayDays = computeDisplayDays(
        displayWeekCourses, displayWeek, showOther, autoCollapse);
    final dates =
        WeekCalc.weekDatesOf(DateTime.parse(semester.startDate), displayWeek);

    // 学期切换联动：semester 变化时把 PageController 跳到新学期的「本周」，
    // 并 clamp 防止旧学期残留的页码超出新学期总周数导致越界
    ref.listen(currentSemesterProvider, (prev, next) {
      final prevId = prev?.value?.id;
      final nextSemester = next.value;
      if (prevId == null ||
          nextSemester == null ||
          prevId == nextSemester.id) {
        return;
      }
      final w = ref.read(todayWeekProvider);
      final maxPage = nextSemester.totalWeeks - 1;
      final page = (w > 0 ? w - 1 : 0).clamp(0, maxPage < 0 ? 0 : maxPage);
      _pageController?.jumpToPage(page);
    });

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: InkWell(
          onTap: () => setState(() => _showJumper = !_showJumper),
          borderRadius: BorderRadius.circular(AppRadii.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(WeekCalc.weekTitle(displayWeek),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(
                      '${dates.first.month}月${dates.first.day}日 - '
                      '${dates.last.month}月${dates.last.day}日',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                Icon(_showJumper ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        actions: [
          // 编辑模式开关（右上角）：防误触——不开时点空白不新建、长按不出菜单
          if (_editMode)
            TextButton.icon(
              onPressed: () => setState(() => _editMode = false),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            )
          else
            IconButton(
              tooltip: '编辑模式（开启后可添加/修改课程）',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _editMode = true);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('编辑模式已开启：点击空白处新建课程，长按课程可编辑'),
                  duration: Duration(seconds: 2),
                ));
              },
            ),
          // 考试倒计时入口（阶段五）：首页一键直达，高频查看不绕设置页
          IconButton(
            tooltip: '考试倒计时',
            icon: const Icon(Icons.event_note_outlined),
            onPressed: () =>
                Navigator.pushNamed(context, '/exam-countdown'),
          ),
          if (displayWeek != todayWeek)
            TextButton.icon(
              onPressed: _goToday,
              icon: const Icon(Icons.event_available, size: 18),
              label: const Text('回到本周'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 周次快速跳转条
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showJumper
                ? _WeekJumper(
                    totalWeeks: semester.totalWeeks,
                    currentWeek: displayWeek,
                    todayWeek: todayWeek,
                    onTap: (w) {
                      _jumpToWeek(w);
                      setState(() => _showJumper = false);
                    },
                  )
                : const SizedBox.shrink(),
          ),
          // 周日收尾提醒：今天是周日且正看着本周时，提醒本周已结束，
          // 避免把周日误看成下周的课；可一键跳到下周
          if (displayWeek == todayWeek &&
              DateTime.now().weekday == DateTime.sunday)
            _SundayEndBanner(
              onNextWeek: displayWeek < semester.totalWeeks
                  ? () => _jumpToWeek(displayWeek + 1)
                  : null,
            ),
          // 表头（列数由 displayDays 驱动）
          _HeaderRow(
            dates: dates,
            displayDays: displayDays,
            timeAxisWidth: _timeAxisWidth,
            today: DateTime.now(),
          ),
          const Divider(height: 1),
          // 网格区
          Expanded(
            child: _GridArea(
              pageController: _pageController!,
              displayWeek: displayWeek,
              displayDays: displayDays,
              timeAxisWidth: _timeAxisWidth,
              editMode: _editMode,
              onWeekChanged: (page) =>
                  ref.read(displayWeekProvider.notifier).setWeek(page + 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 周日收尾提醒横幅：今天是周日时提示本周已结束，防止误看成下周课表
class _SundayEndBanner extends StatelessWidget {
  const _SundayEndBanner({this.onNextWeek});

  /// 跳到下周的回调；已是最后一周时为 null，不显示按钮
  final VoidCallback? onNextWeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.weekend_outlined,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '今天是周日，本周已结束',
              style:
                  TextStyle(fontSize: 13, color: scheme.onSecondaryContainer),
            ),
          ),
          if (onNextWeek != null)
            TextButton(
              onPressed: onNextWeek,
              child: const Text('看下周'),
            ),
        ],
      ),
    );
  }
}

/// 表头行：月份列 + 日期列（列数由 displayDays 驱动）
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.dates,
    required this.displayDays,
    required this.timeAxisWidth,
    required this.today,
  });

  final List<DateTime> dates;
  final List<int> displayDays;
  final double timeAxisWidth;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 月份列
          SizedBox(
            width: timeAxisWidth,
            child: Center(
              child: Text(
                '${dates.first.month}月',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.outline,
                ),
              ),
            ),
          ),
          // 日期列
          Expanded(
            child: Row(
              children: [
                for (final d in displayDays)
                  Expanded(
                    child: _DayCell(
                      date: dates[d - 1],
                      isToday: _isSameDay(dates[d - 1], today),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.isToday});

  final DateTime date;
  final bool isToday;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '周${_weekNames[date.weekday - 1]}',
          style: TextStyle(
            fontSize: 10,
            color: isToday ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday ? colorScheme.primary : Colors.transparent,
            // 今天日期小圆点是正圆（半径=宽高一半），不属于 AppRadii 圆角体系
            borderRadius: BorderRadius.circular(11),
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              color: isToday
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 周次快速跳转条
class _WeekJumper extends StatelessWidget {
  const _WeekJumper({
    required this.totalWeeks,
    required this.currentWeek,
    required this.todayWeek,
    required this.onTap,
  });

  final int totalWeeks;
  final int currentWeek;
  final int todayWeek;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var w = 1; w <= totalWeeks; w++)
            GestureDetector(
              onTap: () => onTap(w),
              child: Container(
                width: 38,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: w == currentWeek
                      ? colorScheme.primary
                      : (w == todayWeek
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(
                  '$w',
                  style: TextStyle(
                    fontSize: 12,
                    color: w == currentWeek
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 网格区：左侧时间轴固定 + PageView 承载每周网格
///
/// 在这里统一计算布局度量（列宽 / 行高 / 生效分隔带），时间轴与周网格共用，
/// 保证分隔带两侧严格对齐（高度守恒）。
class _GridArea extends ConsumerWidget {
  const _GridArea({
    required this.pageController,
    required this.displayWeek,
    required this.displayDays,
    required this.timeAxisWidth,
    required this.onWeekChanged,
    required this.editMode,
  });

  final PageController pageController;
  final int displayWeek;
  final List<int> displayDays;
  final double timeAxisWidth;
  final ValueChanged<int> onWeekChanged;
  final bool editMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semester = ref.watch(currentSemesterProvider).value;
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    if (semester == null || slots.isEmpty) return const SizedBox.shrink();
    final sectionCount = slots.length;
    // 分隔带位置由「作息分段设置」驱动；provider 未加载完成时回退默认值（午休 5 / 晚间 9）
    final seg = ref.watch(segmentSettingsProvider).value;
    final lunchAfter = seg?.lunchAfterSection ?? 5;
    final dinnerAfter = seg?.dinnerAfterSection ?? 9;
    // 生效的分隔带：只保留落在节次范围内的（after < sectionCount）
    final activeBands = [
      (after: lunchAfter, label: '午休'),
      (after: dinnerAfter, label: '晚间'),
    ].where((b) => b.after < sectionCount).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = displayDays.length;
        final cellWidth =
            (constraints.maxWidth - timeAxisWidth - 1) / columnCount;
        // 高度守恒：分隔带参与总高度计算，行高 = 剩余高度 / 节次数
        final rowHeight =
            (constraints.maxHeight - activeBands.length * _bandHeight) /
                sectionCount;
        return Row(
          children: [
            // 左侧时间轴（固定，与网格共用行高 + 分隔带占位）
            _TimeAxis(
              slots: slots,
              width: timeAxisWidth,
              rowHeight: rowHeight,
              activeBands: activeBands,
            ),
            const VerticalDivider(width: 1),
            // 右侧周网格（可左右滑动）
            Expanded(
              child: PageView.builder(
                controller: pageController,
                onPageChanged: (page) {
                  // 切周成功的轻触感反馈
                  HapticFeedback.lightImpact();
                  onWeekChanged(page);
                },
                itemCount: semester.totalWeeks,
                itemBuilder: (context, index) {
                  final week = index + 1;
                  return _WeekGrid(
                    key: ValueKey(week),
                    week: week,
                    sectionCount: sectionCount,
                    displayDays: displayDays,
                    cellWidth: cellWidth,
                    rowHeight: rowHeight,
                    activeBands: activeBands,
                    editMode: editMode,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 左侧时间轴：节次号 + 起止时间（固定高度，与右侧网格严格对齐）
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.slots,
    required this.width,
    required this.rowHeight,
    required this.activeBands,
  });

  final List<dynamic> slots;
  final double width;
  final double rowHeight;
  final List<({int after, String label})> activeBands;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          for (var i = 0; i < slots.length; i++) ...[
            SizedBox(
              height: rowHeight,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: colorScheme.outlineVariant, width: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${slots[i].section}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant)),
                    Text(slots[i].startTime,
                        style:
                            TextStyle(fontSize: 8, color: colorScheme.outline)),
                    Text(slots[i].endTime,
                        style:
                            TextStyle(fontSize: 8, color: colorScheme.outline)),
                  ],
                ),
              ),
            ),
            // 分隔带占位（与右侧网格的午休/晚间带对齐）
            if (activeBands.any((b) => b.after == slots[i].section))
              const SizedBox(height: _bandHeight),
          ],
        ],
      ),
    );
  }
}

/// 某一周的网格：N 列 × M 节次，课程按三态布局段绝对定位
class _WeekGrid extends ConsumerWidget {
  const _WeekGrid({
    super.key,
    required this.week,
    required this.sectionCount,
    required this.displayDays,
    required this.cellWidth,
    required this.rowHeight,
    required this.activeBands,
    required this.editMode,
  });

  final int week;
  final int sectionCount;
  final List<int> displayDays;
  final double cellWidth;
  final double rowHeight;
  final List<({int after, String label})> activeBands;
  final bool editMode;

  double _topOf(int section) =>
      yOffsetTop(section, rowHeight, bandsBefore(section, activeBands));

  /// 段内第一门课在该周的单次调课记录。
  /// 草稿课（无 id）或该周本就不上课的课程（调课记录无效）返回 null。
  CourseOverride? _overrideForSlot(
      Map<int, CourseOverride> overrideMap, DisplaySlot slot, int week) {
    final first = slot.courses.first;
    if (first.id == null || !first.isActiveInWeek(week)) return null;
    return overrideMap[first.id];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allCourses = ref.watch(coursesProvider).value ?? [];
    final overrides = ref.watch(courseOverridesProvider).value ?? [];
    final showOther = ref.watch(showOtherWeeksProvider);
    // 应用单次调课（阶段五）：停课的本次不显示，调课的按新时间/教室显示。
    // 调课副本保留原 course id 与 weeks，三态布局与详情页无需感知差异。
    final effective = effectiveCoursesForWeek(
        courses: allCourses, overrides: overrides, week: week);
    // 需显示的课程：本周课 +（开关开时）非本周课
    final visible = showOther
        ? effective
        : effective.where((c) => c.isActiveInWeek(week)).toList();
    // 该周每门课的单次调课记录（长按菜单 / 「调」角标用）
    final overrideMap = overridesForWeek(overrides, week);

    // 按天分组，每一天做三态布局
    final byDay = <int, List<Course>>{};
    for (final c in visible) {
      (byDay[c.dayOfWeek] ??= []).add(c);
    }
    final daySlots = <int, List<DisplaySlot>>{
      for (final d in displayDays)
        d: SlotLayout.layoutDay(
          dayCourses: byDay[d] ?? const [],
          week: week,
          showDimmed: showOther,
          maxSection: sectionCount,
        ),
    };

    // 分隔带顶部坐标
    final bandTops = [
      for (final b in activeBands)
        b.after * rowHeight + bandsBefore(b.after, activeBands) * _bandHeight,
    ];
    final totalHeight =
        sectionCount * rowHeight + activeBands.length * _bandHeight;

    return GestureDetector(
      // 点击空白格新建课程（自动带入星期与节次）；非编辑模式直接忽略，防误触
      onTapUp: (details) {
        if (!editMode) return;
        final col = (details.localPosition.dx / cellWidth).floor();
        if (col < 0 || col >= displayDays.length) return;
        // 逐节比对纵向坐标（已含分隔带偏移）；点到分隔带上则忽略
        int? row;
        for (var s = 1; s <= sectionCount; s++) {
          final top = _topOf(s);
          if (details.localPosition.dy >= top &&
              details.localPosition.dy < top + rowHeight) {
            row = s;
            break;
          }
        }
        if (row == null) return;
        final day = displayDays[col];
        // 若点到已有课程则不处理（卡片自带手势）
        for (final slot in daySlots[day]!) {
          if (!slot.isEmpty &&
              row >= slot.startSection &&
              row <= slot.endSection) {
            return;
          }
        }
        Navigator.pushNamed(context, '/course-edit', arguments: {
          'dayOfWeek': day,
          'startSection': row,
        });
      },
      child: Stack(
        children: [
          // 网格背景线
          _GridLines(
            cellWidth: cellWidth,
            rowHeight: rowHeight,
            sectionCount: sectionCount,
            columnCount: displayDays.length,
            activeBands: activeBands,
            totalHeight: totalHeight,
          ),
          // 午休 / 晚间分隔带
          for (var i = 0; i < activeBands.length; i++)
            Positioned(
              top: bandTops[i],
              left: 0,
              right: 0,
              height: _bandHeight,
              child: _DividerBand(label: activeBands[i].label),
            ),
          // 课程卡片（按三态布局段绝对定位）
          for (var dayIndex = 0;
              dayIndex < displayDays.length;
              dayIndex++)
            for (final slot in daySlots[displayDays[dayIndex]]!)
              if (!slot.isEmpty)
                _PositionedCourseCard(
                  slot: slot,
                  week: week,
                  courseOverride: _overrideForSlot(overrideMap, slot, week),
                  left: dayIndex * cellWidth,
                  top: _topOf(slot.startSection),
                  width: cellWidth,
                  height: slot.span * rowHeight,
                  editMode: editMode,
                ),
          // 空周占位提示（阶段五·视觉打磨）：网格全空时给中文引导，
          // IgnorePointer 保证点击穿透到空白格的新建手势
          if (visible.isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: '本周没有课程',
                  message: editMode
                      ? '点击空白格子新建，或从底部「新建」导入课表'
                      : '点右上角的编辑按钮开启编辑模式后，可添加课程',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 午休 / 晚间分隔带：浅色通栏 + 淡淡的文字
class _DividerBand extends StatelessWidget {
  const _DividerBand({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: colorScheme.outline.withValues(alpha: 0.8),
          letterSpacing: 8,
        ),
      ),
    );
  }
}

/// 网格线背景（横线跳过分隔带位置）
class _GridLines extends StatelessWidget {
  const _GridLines({
    required this.cellWidth,
    required this.rowHeight,
    required this.sectionCount,
    required this.columnCount,
    required this.activeBands,
    required this.totalHeight,
  });

  final double cellWidth;
  final double rowHeight;
  final int sectionCount;
  final int columnCount;
  final List<({int after, String label})> activeBands;
  final double totalHeight;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return CustomPaint(
      size: Size(cellWidth * columnCount, totalHeight),
      painter: _GridPainter(
        cellWidth: cellWidth,
        rowHeight: rowHeight,
        sectionCount: sectionCount,
        columnCount: columnCount,
        activeBands: activeBands,
        color: color,
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.cellWidth,
    required this.rowHeight,
    required this.sectionCount,
    required this.columnCount,
    required this.activeBands,
    required this.color,
  });

  final double cellWidth;
  final double rowHeight;
  final int sectionCount;
  final int columnCount;
  final List<({int after, String label})> activeBands;
  final Color color;

  double _topOf(int section) =>
      yOffsetTop(section, rowHeight, bandsBefore(section, activeBands));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    // 横线（每节一条，分隔带处由分隔带覆盖故跳过）
    for (var r = 1; r < sectionCount; r++) {
      if (activeBands.any((b) => b.after == r)) continue;
      final y = _topOf(r + 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // 竖线（列分隔）
    for (var c = 1; c < columnCount; c++) {
      final x = c * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cellWidth != cellWidth ||
      old.rowHeight != rowHeight ||
      old.sectionCount != sectionCount ||
      old.columnCount != columnCount ||
      old.color != color;
}

/// 绝对定位的课程卡片（一段 = 一张卡片）
///
/// multi（同格多课）时只渲染最上层一张 + 「+N」角标，
/// 点击先弹出该格子的课程选择列表，再进入所选课程详情。
/// 该课在该周有单次调整时右上角显示「调」角标（停课的课根本不会渲染到这里）。
class _PositionedCourseCard extends StatelessWidget {
  const _PositionedCourseCard({
    required this.slot,
    required this.week,
    required this.courseOverride,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.editMode,
  });

  final DisplaySlot slot;
  final int week;
  final bool editMode;

  /// 该课在该周的单次调课记录（无则 null）
  final CourseOverride? courseOverride;
  final double left;
  final double top;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    const pad = 1.5;
    final isMulti = slot.kind == SlotKind.multi;
    // 「调」角标：仅单课时段显示；multi 时让位给「+N」（调整信息在详情里仍可见）
    final isMoved = courseOverride != null && !courseOverride!.isCancellation;
    return Positioned(
      left: left + pad,
      top: top + pad,
      width: width - pad * 2,
      height: height - pad * 2,
      child: CourseCard(
        course: slot.courses.first,
        dimmed: slot.dimmed,
        badgeText: isMulti
            ? '+${slot.extraCount}'
            : (isMoved ? '调' : null),
        showNoteDot:
            slot.courses.first.note?.trim().isNotEmpty == true,
        onTap: () => isMulti
            ? _showSlotPicker(context, slot)
            : CourseDetailSheet.show(context, slot.courses.first,
                allowEdit: editMode),
        // 非编辑模式长按无反应，防止误触进修改菜单
        onLongPress: () {
          if (editMode) {
            _showMenu(context, slot.courses.first, week, courseOverride);
          }
        },
      ),
    );
  }

  /// 同格多课时的迷你选择列表
  void _showSlotPicker(BuildContext context, DisplaySlot slot) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '该时段有 ${slot.courses.length} 门课程',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final c in slot.courses)
              ListTile(
                leading: Container(
                  width: 14,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(c.colorValue),
                    // 色条是微小装饰元素，4px 微圆角不便归入 AppRadii 体系
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(c.name),
                subtitle: Text(
                  '第${c.startSection}'
                  '${c.endSection > c.startSection ? "-${c.endSection}" : ""}节'
                  ' · ${c.classroom?.isNotEmpty == true ? c.classroom : "未填教室"}'
                  '${slot.dimmed ? " · 非本周" : ""}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  CourseDetailSheet.show(context, c, allowEdit: editMode);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 长按菜单：单次调整（阶段五）+ 编辑 / 删除
  ///
  /// [courseOverride] 非空表示该课在 [week] 周已有单次调整，
  /// 菜单项变为「查看/撤销本次调整」；否则为「调整本次」。
  void _showMenu(BuildContext context, Course course, int week,
      CourseOverride? courseOverride) {
    // 长按弹出菜单的中触感反馈
    HapticFeedback.mediumImpact();
    // 草稿课程（id 为空）没有落库，无法建立调课关联
    final canOverride = course.id != null;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canOverride)
              ListTile(
                leading: Icon(courseOverride == null
                    ? Icons.event_repeat_outlined
                    : Icons.visibility_outlined),
                title: Text(courseOverride == null
                    ? '调整本次'
                    : '查看/撤销本次调整'),
                subtitle: Text(
                  courseOverride == null
                      ? '只改这一节课的时间/教室，不影响其他周'
                      : describeOverride(courseOverride),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, '/course-override',
                      arguments: {'courseId': course.id, 'week': week});
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑课程'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/course-edit',
                    arguments: course.id);
              },
            ),
            Consumer(
              builder: (ctx2, ref, _) => ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除课程'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('删除课程'),
                      content: Text('确定删除《${course.name}》吗？'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(d, false),
                            child: const Text('取消')),
                        FilledButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('删除')),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    try {
                      await ref
                          .read(coursesProvider.notifier)
                          .deleteCourse(course.id!);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已删除《${course.name}》')));
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('删除失败：$e')));
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
