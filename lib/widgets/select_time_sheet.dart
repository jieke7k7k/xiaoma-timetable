import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/next_class.dart';
import '../utils/week_calc.dart';

/// 「在课表上选」弹层（WB_SPEC_232 第 6 节）
///
/// 从编辑页「星期与节次」组头右侧的入口打开：给出一个只读迷你周视图，
/// 点两下就在网格上圈出「星期三 第 3–4 节」，确认后一次性回填编辑页的三个状态量。
///
/// 设计边界（规格第 6.2 节）：
/// - **不复用** `week_view_page.dart` 的 `_WeekGrid`（它绑页面状态、手势翻周、
///   整页联动，塞不进弹层）；这里自建轻量只读网格，但占用判定复用主页同一份
///   口径（[sessionsOnDay]，含单次调课与周次过滤），不另造一套；
/// - 翻周只为「看哪一周格子空着」作参考，点选只决定星期与节次，
///   **不改**编辑页下方的周次选择（两者正交解耦）；
/// - 不做拖拽选区（会和纵向滚动抢手势），只做「点两下定一段」。
Future<({int dayOfWeek, int startSection, int endSection})?>
    showSelectTimeSheet({
  required BuildContext context,
  required int dayOfWeek,
  required int startSection,
  required int endSection,
}) {
  return showModalBottomSheet<({int dayOfWeek, int startSection, int endSection})>(
    context: context,
    isScrollControlled: true,
    // 圆角走全局 bottomSheetTheme（AppRadii.sheet），不在调用点重复 shape
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _SelectTimeSheet(
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
      ),
    ),
  );
}

class _SelectTimeSheet extends ConsumerStatefulWidget {
  const _SelectTimeSheet({
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
  });

  final int dayOfWeek;
  final int startSection;
  final int endSection;

  @override
  ConsumerState<_SelectTimeSheet> createState() => _SelectTimeSheetState();
}

class _SelectTimeSheetState extends ConsumerState<_SelectTimeSheet> {
  /// 选区：day 固定，start..end 为节次区间（start == end 表示只选了一节）
  late int _day;
  late int _start;
  late int _end;

  /// 本格是否还在「等第二下」：true = 下一格与同一天则连成区间，否则重置为新起点
  bool _awaitingSecond = false;

  /// 当前展示的周次（只影响占用显示）
  late int _week;

  static const double _axisW = 34;
  static const double _rowH = 34;
  static const double _bandH = 22;
  static const double _headH = 26;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    // 打开时把编辑页当前「星期 + 开始~结束节次」渲染成高亮（反向同步）
    _day = widget.dayOfWeek;
    _start = math.min(widget.startSection, widget.endSection);
    _end = math.max(widget.startSection, widget.endSection);
    final total = ref.read(currentSemesterProvider).value?.totalWeeks ?? 20;
    final current = ref.read(displayWeekProvider);
    // 默认看当前周，钳到 1..totalWeeks（没开学时 displayWeek 可能是 0）
    _week = current.clamp(1, total == 0 ? 1 : total);
  }

  /// 点一格：三态状态机（WB_SPEC_232 第 6.3 节）
  void _tapCell(int day, int section) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_awaitingSecond && day == _day) {
        // 同一天的第二下：以第一下为锚点正序合成（先点第 4 再点第 3 也得 3–4）
        final anchor = _start;
        _start = math.min(anchor, section);
        _end = math.max(anchor, section);
        _awaitingSecond = false;
      } else {
        // 第一下、或连成一段之后的第三下、或点到另一天：以最新点击格为新起点
        _day = day;
        _start = section;
        _end = section;
        _awaitingSecond = true;
      }
    });
  }

  void _confirm() {
    Navigator.pop(
      context,
      (dayOfWeek: _day, startSection: _start, endSection: _end),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semester = ref.watch(currentSemesterProvider).value;
    final slots = ref.watch(timeSlotsProvider).value ?? const <TimeSlot>[];
    final courses = ref.watch(coursesProvider).value ?? const <Course>[];
    final overrides = ref.watch(courseOverridesProvider).value ?? const [];
    final seg = ref.watch(segmentSettingsProvider).value;
    final totalWeeks = semester?.totalWeeks ?? 20;

    final sorted = [...slots]..sort((a, b) => a.section.compareTo(b.section));
    // 作息未读出时回退 13 节，与 DB 种子一致（Kimi 复审低：四处回退值统一为 13）
    final sectionCount = sorted.isNotEmpty ? sorted.last.section : 13;
    final slotMap = {for (final s in sorted) s.section: s};

    // 分隔带：午休/晚餐按分段点落在第 X 节之后（弹层只做时间参考，
    // 主页「休息时段设置」里的显隐/自定义时间不参与，见规格第 6.2 节）
    final bands = <({int after, String label})>[];
    final lunchAfter = seg?.lunchAfterSection ?? 5;
    final dinnerAfter = seg?.dinnerAfterSection ?? 9;
    if (lunchAfter < sectionCount) bands.add((after: lunchAfter, label: '午休'));
    if (dinnerAfter < sectionCount) {
      bands.add((after: dinnerAfter, label: '晚餐'));
    }

    // 占用判定与主页同源：某周的某天有哪些课（含单次调课、周次过滤）
    final occupied = <int, Map<int, String>>{};
    if (semester != null && sorted.isNotEmpty) {
      final dates = WeekCalc.weekDatesOf(semester.startDateParsed, _week);
      for (var d = 1; d <= 7; d++) {
        for (final s in sessionsOnDay(
          date: dates[d - 1],
          semester: semester,
          courses: courses,
          timeSlots: sorted,
          overrides: overrides,
        )) {
          final name = s.course.name;
          for (var k = s.course.startSection; k <= s.course.endSection; k++) {
            (occupied[d] ??= {})[k] = name;
          }
        }
      }
    }

    int bandsBefore(int section) =>
        bands.where((b) => section > b.after).length;
    double topOf(int section) =>
        (section - 1) * _rowH + bandsBefore(section) * _bandH;

    // 选区内第一个被占用的课程名（软提示用）
    String? occupiedName;
    for (var s = _start; s <= _end && occupiedName == null; s++) {
      occupiedName = occupied[_day]?[s];
    }

    final gridH = sectionCount * _rowH + bands.length * _bandH;
    final startSlot = slotMap[_start];
    final endSlot = slotMap[_end];
    final timeText = (startSlot == null || endSlot == null)
        ? ''
        : ' (${startSlot.startTime}-${endSlot.endTime})';
    final rangeText = _start == _end ? '第 $_start 节' : '第 $_start–$_end 节';

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.l,
              AppSpacing.s,
              AppSpacing.s,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '选择上课时间',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // 轻量周次切换器：只翻「看哪一周」，不影响回填
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _week > 1
                      ? () => setState(() => _week -= 1)
                      : null,
                  icon: const Icon(Icons.chevron_left, size: 20),
                  tooltip: '上一周',
                ),
                Text('第 $_week 周', style: const TextStyle(fontSize: 13)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _week < totalWeeks
                      ? () => setState(() => _week += 1)
                      : null,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  tooltip: '下一周',
                ),
              ],
            ),
          ),
          // 迷你网格：纵向可滚（13 节 + 2 条分隔带放不下时）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final colW = (constraints.maxWidth - _axisW) / 7;
                return SingleChildScrollView(
                  child: SizedBox(
                    height: _headH + gridH,
                    child: Stack(
                      children: [
                        // 表头：星期
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: _headH,
                          child: Row(
                            children: [
                              const SizedBox(width: _axisW),
                              for (var d = 1; d <= 7; d++)
                                SizedBox(
                                  width: colW,
                                  child: Center(
                                    child: Text(
                                      _weekNames[d - 1],
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.outline,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // 单元格背景（空格：纯白/纯黑 + 极淡十字参考点；
                        // 有课：压暗降饱和的灰底）
                        for (var d = 1; d <= 7; d++)
                          for (var s = 1; s <= sectionCount; s++)
                            Positioned(
                              left: _axisW + (d - 1) * colW,
                              top: _headH + topOf(s),
                              width: colW,
                              height: _rowH,
                              child: _MiniCell(
                                occupied: occupied[d]?[s] != null,
                                courseName: occupied[d]?[s],
                              ),
                            ),
                        // 选区：一整块圆角色块，跨过分隔带时连成一片
                        Positioned(
                          left: _axisW + (_day - 1) * colW + 1.5,
                          top: _headH + topOf(_start) + 1.5,
                          width: colW - 3,
                          height: topOf(_end) + _rowH - topOf(_start) - 3,
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.22),
                                borderRadius:
                                    BorderRadius.circular(AppRadii.chip),
                                border: Border.all(
                                  color: scheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 节次轴
                        for (var s = 1; s <= sectionCount; s++)
                          Positioned(
                            left: 0,
                            top: _headH + topOf(s),
                            width: _axisW,
                            height: _rowH,
                            child: Center(
                              child: Text(
                                '$s',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        // 午休 / 晚餐分隔带：半透明浮在选区之上，本身不可点
                        for (final b in bands)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: _headH +
                                b.after * _rowH +
                                bandsBefore(b.after) * _bandH,
                            height: _bandH,
                            child: IgnorePointer(
                              child: Container(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.72),
                                alignment: Alignment.center,
                                child: Text(
                                  b.label,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.outline,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // 点击层：每格一个透明热区（有课格子也能点，只给软提示）
                        for (var d = 1; d <= 7; d++)
                          for (var s = 1; s <= sectionCount; s++)
                            Positioned(
                              left: _axisW + (d - 1) * colW,
                              top: _headH + topOf(s),
                              width: colW,
                              height: _rowH,
                              child: GestureDetector(
                                key: ValueKey('mini-cell-$d-$s'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _tapCell(d, s),
                                child: const SizedBox.expand(),
                              ),
                            ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 软提示：选到有课格子时温和提示，不阻断、不弹窗
          if (occupiedName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.l,
                AppSpacing.s,
                AppSpacing.l,
                0,
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '该时段在部分周次已有『$occupiedName』，返回后可错开周次',
                      style: TextStyle(fontSize: 12, color: scheme.tertiary),
                    ),
                  ),
                ],
              ),
            ),
          // 底部固定 64dp 操作栏：左实时结果，右主色确认
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '周${_weekNames[_day - 1]} · $rangeText$timeText',
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  FilledButton(
                    onPressed: _confirm,
                    child: const Text('确认选定'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 迷你网格的一格：空格画极淡十字参考点，有课格子显示压暗的课程名
class _MiniCell extends StatelessWidget {
  const _MiniCell({required this.occupied, this.courseName});

  final bool occupied;
  final String? courseName;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        // 有课格子压暗降饱和（规格第 6.2 节给了浅/深两套固定值，按主题分别取）；
        // 空格子纯白/纯黑，让「空着的格子」第一眼就跳出来
        color: occupied
            ? (dark ? const Color(0xFF222428) : const Color(0xFFF1F3F5))
            : (dark ? Colors.black : Colors.white),
        // 迷你格子只有 30 多 dp 宽，4dp 微圆角属微小装饰（与主页拖动条 2px、
        // 色点 3px 同类），不套 AppRadii 的 chip/menu/sheet 三档
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: occupied
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                courseName ?? '',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.1,
                  // 课名 40% 透明度灰字，只作背景参考
                  color: scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            )
          : Center(
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
              ),
            ),
    );
  }
}
