import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/db_helper.dart';
import '../models/course.dart';
import '../models/course_override.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../ui/settings_line_frame.dart';
import '../utils/app_haptics.dart';
import '../utils/color_schemes.dart';
import '../utils/override_effect.dart';
import '../utils/sunday_dialog.dart';
import '../widgets/course_detail_sheet.dart';

/// 测试用可覆盖的当前时钟（默认取 sundayDialogNow，方便单测锁时间验证三态）
DateTime Function() todayViewNow = () => sundayDialogNow();

/// 今日课程时间三态（WB_SPEC_238 §4）
enum TodayCourseStatus {
  upcoming, // 未开始
  ongoing, // 正在上课
  finished, // 已上完
}

/// 今日单条排课项（已结合调课与起止时间计算）
class TodayScheduleItem {
  const TodayScheduleItem({
    required this.course,
    required this.effectiveClassroom,
    required this.startSection,
    required this.endSection,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.remark,
  });

  final Course course;
  final String? effectiveClassroom;
  final int startSection;
  final int endSection;
  final String startTime;
  final String endTime;
  final TodayCourseStatus status;
  final String? remark;
}

/// 解析 "HH:mm" 为当天的分钟数（0..1439）
int _parseMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return 0;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return h * 60 + m;
}

/// 判定课程在当前时间的三态（正在上课 / 已上完 / 未开始）
TodayCourseStatus evaluateStatus({
  required DateTime now,
  required String startTime,
  required String endTime,
}) {
  final nowMinutes = now.hour * 60 + now.minute;
  final startMin = _parseMinutes(startTime);
  final endMin = _parseMinutes(endTime);
  if (nowMinutes < startMin) {
    return TodayCourseStatus.upcoming;
  } else if (nowMinutes <= endMin) {
    return TodayCourseStatus.ongoing;
  } else {
    return TodayCourseStatus.finished;
  }
}

/// 格式化课程周次描述（如「1-16周」、「1-15单周」）
String formatWeeksLabel(Course c) {
  if (c.weeks.isEmpty) return '';
  final sorted = [...c.weeks]..sort();
  final first = sorted.first;
  final last = sorted.last;
  final paritySuffix = c.weekType == 1 ? '单周' : (c.weekType == 2 ? '双周' : '周');
  if (first == last) return '第$first周';
  return '$first-$last$paritySuffix';
}

/// 过滤并生成今日有效排课列表（含调课 CourseOverride 处理）
///
/// 调课口径与周视图一致：先走 [effectiveCoursesForWeek] 应用本周的单次调课
/// （停课移除、调整替换星期/节次/教室），再按「本周生效 + 今天星期」过滤。
/// 备注行取课程自身的 [Course.note]：仓库里没有「某课某天」的日期备注模型
/// （CourseRemark 不存在，Note 表只有日期、无课程外键），不另造数据模型。
List<TodayScheduleItem> buildTodayItems({
  required List<Course> allCourses,
  required List<CourseOverride> overrides,
  required List<TimeSlot> slots,
  required int currentWeek,
  required int todayWeekday,
  required DateTime now,
}) {
  final slotMap = <int, TimeSlot>{for (final s in slots) s.section: s};
  String startOf(int sec) => slotMap[sec]?.startTime ?? '08:00';
  String endOf(int sec) => slotMap[sec]?.endTime ?? '08:45';

  final effective = effectiveCoursesForWeek(
    courses: allCourses,
    overrides: overrides,
    week: currentWeek,
  );

  final items = <TodayScheduleItem>[];
  for (final c in effective) {
    if (!c.isActiveInWeek(currentWeek)) continue;
    if (c.dayOfWeek != todayWeekday) continue;

    final stTime = startOf(c.startSection);
    final edTime = endOf(c.endSection);
    final status = evaluateStatus(now: now, startTime: stTime, endTime: edTime);
    final note = c.note?.trim();
    items.add(
      TodayScheduleItem(
        course: c,
        effectiveClassroom: c.classroom,
        startSection: c.startSection,
        endSection: c.endSection,
        startTime: stTime,
        endTime: edTime,
        status: status,
        remark: (note != null && note.isNotEmpty) ? note : null,
      ),
    );
  }

  // §4 排序：按开始节次升序；同节次多门课按课名排序
  items.sort((a, b) {
    final cmp = a.startSection.compareTo(b.startSection);
    if (cmp != 0) return cmp;
    return a.course.name.compareTo(b.course.name);
  });

  return items;
}

/// WB_SPEC_238：日程（今日视图）一级页面
class TodayViewPage extends ConsumerStatefulWidget {
  const TodayViewPage({super.key, this.onNavigateToSchedule});

  /// 空状态点击「课表」二字时切换到课表 Tab 的回调
  final VoidCallback? onNavigateToSchedule;

  @override
  ConsumerState<TodayViewPage> createState() => _TodayViewPageState();
}

class _TodayViewPageState extends ConsumerState<TodayViewPage> {
  static const List<String> _weekdayNames = [
    '',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  @override
  Widget build(BuildContext context) {
    final now = todayViewNow();

    final allCourses = ref.watch(coursesProvider).value ?? const <Course>[];
    final overrides =
        ref.watch(courseOverridesProvider).value ?? const <CourseOverride>[];
    final slotsValue = ref.watch(timeSlotsProvider).value;
    final slots = (slotsValue == null || slotsValue.isEmpty)
        ? defaultTimeSlots
        : slotsValue;
    final seg =
        ref.watch(segmentSettingsProvider).value ??
        const SegmentSettings(lunchAfterSection: 5, dinnerAfterSection: 9);
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();

    // 当前周次与周视图同口径：todayWeekProvider（按开学日期算，不另算）
    final currentWeek = ref.watch(todayWeekProvider);
    final todayWeekday = now.weekday;
    final parityStr = currentWeek.isOdd ? '单周' : '双周';

    final todayItems = buildTodayItems(
      allCourses: allCourses,
      overrides: overrides,
      slots: slots,
      currentWeek: currentWeek,
      todayWeekday: todayWeekday,
      now: now,
    );

    final totalCount = todayItems.length;
    final remainingCount = todayItems
        .where((e) => e.status != TodayCourseStatus.finished)
        .length;

    // 查找正在上课的焦点课程
    TodayScheduleItem? ongoingItem;
    for (final item in todayItems) {
      if (item.status == TodayCourseStatus.ongoing) {
        ongoingItem = item;
        break;
      }
    }

    // 按上午 / 下午 / 晚上三段分组（分段点取自作息设置，不写死）
    final morningItems = todayItems
        .where((e) => e.startSection <= seg.lunchAfterSection)
        .toList();
    final afternoonItems = todayItems
        .where(
          (e) =>
              e.startSection > seg.lunchAfterSection &&
              e.startSection <= seg.dinnerAfterSection,
        )
        .toList();
    final eveningItems = todayItems
        .where((e) => e.startSection > seg.dinnerAfterSection)
        .toList();

    String rangeText(int fromSec, int toSec) {
      if (slots.isEmpty) return '';
      final st = slots.firstWhere(
        (s) => s.section == fromSec,
        orElse: () => slots.first,
      );
      final ed = slots.firstWhere(
        (s) => s.section == toSec,
        orElse: () => slots.last,
      );
      return '${st.startTime}–${ed.endTime}';
    }

    final morningRange = rangeText(1, seg.lunchAfterSection);
    final afternoonRange = rangeText(
      seg.lunchAfterSection + 1,
      seg.dinnerAfterSection,
    );
    final eveningRange = rangeText(seg.dinnerAfterSection + 1, slots.length);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            // 1. 顶部：日期 + 星期 + 周次 pill
            Row(
              children: [
                Text(
                  '${now.month}月${now.day}日 ${_weekdayNames[todayWeekday]}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '第 $currentWeek 周 · $parityStr',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 大标题「今日课程」+ 右上角汇总
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '今日课程',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? const Color(0xFFF4F4F5)
                        : const Color(0xFF1F2937),
                  ),
                ),
                if (totalCount > 0)
                  Text(
                    '共 $totalCount 门 · 剩余 $remainingCount 门',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFFA1A1AA)
                          : const Color(0xFF6B7280),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // 2. 焦点播报条（有正在上的课时才显示，无则不占位）
            if (ongoingItem != null) ...[
              _OngoingFocusBanner(item: ongoingItem),
              const SizedBox(height: 16),
            ],

            // 3. 课程分组或空状态
            if (todayItems.isEmpty)
              _EmptyTodayCard(onTapSchedule: widget.onNavigateToSchedule)
            else ...[
              if (morningItems.isNotEmpty) ...[
                _BandSectionGroup(
                  title: '上午',
                  timeRange: morningRange,
                  items: morningItems,
                  ui: ui,
                ),
                const SizedBox(height: 16),
              ],
              if (afternoonItems.isNotEmpty) ...[
                _BandSectionGroup(
                  title: '下午',
                  timeRange: afternoonRange,
                  items: afternoonItems,
                  ui: ui,
                ),
                const SizedBox(height: 16),
              ],
              if (eveningItems.isNotEmpty) ...[
                _BandSectionGroup(
                  title: '晚上',
                  timeRange: eveningRange,
                  items: eveningItems,
                  ui: ui,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 焦点播报条（正在上课时显示）
class _OngoingFocusBanner extends StatelessWidget {
  const _OngoingFocusBanner({required this.item});

  final TodayScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secLabel = item.startSection == item.endSection
        ? '第 ${item.startSection} 节'
        : '第 ${item.startSection}–${item.endSection} 节';
    final roomPart =
        (item.effectiveClassroom != null &&
            item.effectiveClassroom!.trim().isNotEmpty)
        ? ' · ${item.effectiveClassroom}'
        : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.30),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '正在上课 · $secLabel',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.course.name}$roomPart',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFF4F4F5)
                        : const Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${item.endTime} 下课',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 时段分组（上午 / 下午 / 晚上）
class _BandSectionGroup extends StatelessWidget {
  const _BandSectionGroup({
    required this.title,
    required this.timeRange,
    required this.items,
    required this.ui,
  });

  final String title;
  final String timeRange;
  final List<TodayScheduleItem> items;
  final UiSettings ui;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark
        ? const Color(0xFFA1A1AA)
        : const Color(0xFF6B7280);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: headerColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                timeRange,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: headerColor,
                ),
              ),
            ],
          ),
        ),
        SettingsLineFrame(
          title: title,
          showTitle: false,
          children: [
            for (final item in items) _TodayCourseRow(item: item, ui: ui),
          ],
        ),
      ],
    );
  }
}

/// 单条今日课程行（WB_SPEC_238 §3 & §5）
class _TodayCourseRow extends StatelessWidget {
  const _TodayCourseRow({required this.item, required this.ui});

  final TodayScheduleItem item;
  final UiSettings ui;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isFinished = item.status == TodayCourseStatus.finished;
    final isOngoing = item.status == TodayCourseStatus.ongoing;

    final mappedColor = Color(
      mapCourseColor(item.course.colorValue, ui.colorScheme),
    );
    final secText = item.startSection == item.endSection
        ? '${item.startSection}节'
        : '${item.startSection}-${item.endSection}节';

    final weeksStr = formatWeeksLabel(item.course);
    final teacherStr =
        (item.course.teacher != null && item.course.teacher!.trim().isNotEmpty)
        ? item.course.teacher!.trim()
        : null;
    final metaParts = <String>[
      if (teacherStr != null) teacherStr,
      if (weeksStr.isNotEmpty) weeksStr,
    ];
    final metaLine = metaParts.join(' · ');

    final textPrimary = isDark
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF1F2937);
    final textSecondary = isDark
        ? const Color(0xFFA1A1AA)
        : const Color(0xFF6B7280);

    return Opacity(
      opacity: isFinished ? 0.48 : 1.0,
      child: InkWell(
        onTap: () {
          AppHaptics.tap();
          CourseDetailSheet.show(context, item.course);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左列：开始时间 / 结束时间 / 节次
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.startTime,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.endTime,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      secText,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 课程配色竖条
              Container(
                width: 4,
                height: item.remark != null ? 54 : 40,
                decoration: BoxDecoration(
                  color: mappedColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // 中间：课名 + 老师·周次 + 备注
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.course.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        if (isOngoing) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '上课中',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        metaLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                    if (item.remark != null && item.remark!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 13,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.remark!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // 右列：教室标签
              if (item.effectiveClassroom != null &&
                  item.effectiveClassroom!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.effectiveClassroom!.trim(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 当日无课空状态卡片（WB_SPEC_238 §3）
class _EmptyTodayCard extends StatelessWidget {
  const _EmptyTodayCard({this.onTapSchedule});

  final VoidCallback? onTapSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return SettingsLineFrame(
      title: '空状态',
      showTitle: false,
      dividers: false,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 44,
                color: isDark
                    ? const Color(0xFF71717A)
                    : const Color(0xFF9CA3AF),
              ),
              const SizedBox(height: 12),
              Text(
                '今天没有课程安排',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? const Color(0xFFF4F4F5)
                      : const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 6),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : const Color(0xFF6B7280),
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: '好好休息，或前往'),
                    TextSpan(
                      text: '「课表」',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          if (onTapSchedule != null) {
                            AppHaptics.tap();
                            onTapSchedule!();
                          }
                        },
                    ),
                    const TextSpan(text: '查看本周其他日程'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
