import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/fonts_service.dart';
import '../ui/grid_metrics.dart';
import '../utils/color_schemes.dart';
import '../utils/override_effect.dart';
import '../utils/slot_layout.dart';
import '../utils/week_calc.dart';
import '../widgets/course_card.dart';

/// 课表导出图片页
///
/// 1.2.0 初版用自定版式（720 宽、海报比例），用户反馈「形状和主页对不上」。
/// 1.2.1 改为与主页周视图完全同构：宽度 = 设备逻辑宽度、行高 = 界面设置的
/// 格子高度、节次栏 50、表头 46、分隔带通栏（名称+时间段），定位公式与主页
/// 一致；出图时按 3 倍像素比放大保证清晰。不往手机屏幕里挤——图的总高
/// 就是课表自然高度，分享出去对方滚动看即可。
class ShareImagePage extends ConsumerStatefulWidget {
  const ShareImagePage({super.key});

  @override
  ConsumerState<ShareImagePage> createState() => _ShareImagePageState();
}

class _ShareImagePageState extends ConsumerState<ShareImagePage> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('图片生成失败');
      final week = ref.read(displayWeekProvider);
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            byteData.buffer.asUint8List(),
            name: '小马课表-第$week周.png',
            mimeType: 'image/png',
          ),
        ],
        text: '我的课表（第 $week 周）· 小马课表',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分享失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(currentSemesterProvider).value;
    final courses = ref.watch(coursesProvider).value ?? const [];
    final overrides = ref.watch(courseOverridesProvider).value ?? const [];
    final slots = ref.watch(timeSlotsProvider).value ?? const <TimeSlot>[];
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final week = ref.watch(displayWeekProvider);
    final showOther = ref.watch(showOtherWeeksProvider);
    final autoCollapse = ref.watch(autoCollapseWeekendProvider);
    final seg = ref.watch(segmentSettingsProvider).value;
    if (semester == null || slots.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final effective = effectiveCoursesForWeek(
        courses: courses, overrides: overrides, week: week);
    final displayDays =
        computeDisplayDays(effective, week, showOther, autoCollapse);
    final dates =
        WeekCalc.weekDatesOf(DateTime.parse(semester.startDate), week);
    final sortedSlots = [...slots]
      ..sort((a, b) => a.section.compareTo(b.section));
    final maxSection = sortedSlots.last.section;
    // 分隔带与主页同源：位置来自分段设置，时间段按作息实时算
    final lunchAfter = seg?.lunchAfterSection ?? 5;
    final dinnerAfter = seg?.dinnerAfterSection ?? 9;
    String bandInterval(int after) {
      TimeSlot? cur, nxt;
      for (final t in sortedSlots) {
        if (t.section == after) cur = t;
        if (t.section == after + 1) nxt = t;
      }
      if (cur == null || nxt == null) return '';
      return '${cur.endTime}–${nxt.startTime}';
    }

    final bands = [
      (after: lunchAfter, label: '午休', interval: bandInterval(lunchAfter)),
      (after: dinnerAfter, label: '晚间', interval: bandInterval(dinnerAfter)),
    ].where((b) => b.after < maxSection).toList();
    // 导出宽度 = 设备逻辑宽度，与主页课表严丝合缝同宽
    final sheetWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(title: const Text('导出课表图片'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '正在导出第 $week 周 · 与主页同比例出图，点「分享图片」发给同学或保存',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Theme(
                  // 导出图固定浅色：卡片用存储色原色，深色模式下也不发灰
                  data: ThemeData(
                    useMaterial3: true,
                    brightness: Brightness.light,
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Color(ui.themeSeedValue)),
                    fontFamily: FontsService.resolveFamily(ui),
                  ),
                  child: _ExportSheet(
                    width: sheetWidth,
                    title: '${semester.name} · 第 $week 周课表',
                    dateRange:
                        '${dates.first.month}月${dates.first.day}日 - ${dates.last.month}月${dates.last.day}日',
                    displayDays: displayDays,
                    dates: dates,
                    slots: sortedSlots,
                    maxSection: maxSection,
                    bands: bands,
                    pool: effective,
                    week: week,
                    ui: ui,
                    today: DateTime.now(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share_outlined),
            label: Text(_sharing ? '生成中…' : '分享图片'),
          ),
        ),
      ),
    );
  }
}

/// 导出图本体：标题 + 表头 + 网格，几何与主页周视图同构
/// （整表一张 Stack：时间轴、通栏分隔带、课程卡都用主页的定位公式）
class _ExportSheet extends StatelessWidget {
  const _ExportSheet({
    required this.width,
    required this.title,
    required this.dateRange,
    required this.displayDays,
    required this.dates,
    required this.slots,
    required this.maxSection,
    required this.bands,
    required this.pool,
    required this.week,
    required this.ui,
    required this.today,
  });

  final double width;
  final String title;
  final String dateRange;
  final List<int> displayDays;
  final List<DateTime> dates;
  final List<TimeSlot> slots;
  final int maxSection;
  final List<GridBand> bands;

  /// 该周有效课程池（已应用调课）
  final List<Course> pool;
  final int week;
  final UiSettings ui;
  final DateTime today;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  int _bandsBefore(int section) =>
      bands.where((b) => section > b.after).length;

  @override
  Widget build(BuildContext context) {
    final rowH = ui.cellHeight;
    const axisW = kTimeAxisWidth;
    final colW = (width - axisW) / displayDays.length;
    final gridH = maxSection * rowH + bands.length * kBandHeight;
    double topOf(int section) =>
        (section - 1) * rowH + _bandsBefore(section) * kBandHeight;
    double bandTop(GridBand b) =>
        b.after * rowH +
        bands.where((x) => x.after < b.after).length * kBandHeight;
    final scheme = Theme.of(context).colorScheme;
    final bandColor = scheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return Container(
      width: width,
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题区（紧凑一行 + 日期范围）
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                Text('小马课表',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(dateRange,
                  style: TextStyle(fontSize: 11, color: scheme.outline)),
            ),
          ),
          // 表头（与主页同高同结构：左月、星期+日期，今天带圆点）
          Container(
            height: kGridHeaderHeight,
            color: scheme.surfaceContainerLow,
            child: Row(
              children: [
                SizedBox(
                  width: axisW,
                  child: Center(
                    child: Text('${dates.first.month}月',
                        style:
                            TextStyle(fontSize: 11, color: scheme.outline)),
                  ),
                ),
                for (final d in displayDays)
                  SizedBox(
                    width: colW,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_weekNames[d - 1],
                            style: TextStyle(
                                fontSize: 10, color: scheme.outline)),
                        const SizedBox(height: 2),
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _isSameDay(dates[d - 1], today)
                                ? scheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            '${dates[d - 1].day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: _isSameDay(dates[d - 1], today)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: _isSameDay(dates[d - 1], today)
                                  ? scheme.onPrimary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 网格区：单张 Stack，时间轴/分隔带/课程卡同主页公式定位
          SizedBox(
            height: gridH,
            child: Stack(
              children: [
                // 横向网格线（跳过分隔带处，与主页一致）
                for (var r = 1; r < maxSection; r++)
                  if (!bands.any((b) => b.after == r))
                    Positioned(
                      top: topOf(r + 1),
                      left: 0,
                      right: 0,
                      child: Container(
                          height: 0.5, color: scheme.outlineVariant),
                    ),
                // 纵向列线
                for (var c = 0; c <= displayDays.length; c++)
                  Positioned(
                    left: axisW + c * colW,
                    top: 0,
                    bottom: 0,
                    child: Container(
                        width: 0.5, color: scheme.outlineVariant),
                  ),
                // 时间轴：节次 + 起止时间（跟随界面设置 axisShowTime）
                for (final s in slots)
                  Positioned(
                    left: 0,
                    top: topOf(s.section),
                    width: axisW,
                    height: rowH,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${s.section}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant)),
                        if (ui.axisShowTime) ...[
                          Text(s.startTime,
                              style: TextStyle(
                                  fontSize: 8, color: scheme.outline)),
                          Text(s.endTime,
                              style: TextStyle(
                                  fontSize: 8, color: scheme.outline)),
                        ],
                      ],
                    ),
                  ),
                // 分隔带（通栏：左段名称 + 右段名称与时间段，与主页一致）
                for (final b in bands) ...[
                  Positioned(
                    left: 0,
                    top: bandTop(b),
                    width: axisW,
                    height: kBandHeight,
                    child: Container(
                      color: bandColor,
                      alignment: Alignment.center,
                      child: Text(
                        b.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: scheme.outline.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: axisW,
                    top: bandTop(b),
                    right: 0,
                    height: kBandHeight,
                    child: Container(
                      color: bandColor,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            b.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  scheme.outline.withValues(alpha: 0.8),
                              letterSpacing: 4,
                            ),
                          ),
                          if (b.interval.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              b.interval,
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      scheme.outline.withValues(alpha: 0.8)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                // 课程卡（布局与主页同一套 SlotLayout）
                for (var di = 0; di < displayDays.length; di++)
                  for (final slot in SlotLayout.layoutDay(
                    dayCourses: [
                      for (final c in pool)
                        if (c.dayOfWeek == displayDays[di]) c,
                    ],
                    week: week,
                    showDimmed: false,
                    maxSection: maxSection,
                  ))
                    if (!slot.isEmpty)
                      Positioned(
                        left: axisW + di * colW + 1.5,
                        top: topOf(slot.startSection) + 1.5,
                        width: colW - 3,
                        height: slot.span * rowH - 3,
                        child: CourseCard(
                          course: slot.courses.first,
                          onTap: () {},
                          onLongPress: () {},
                          badgeText: slot.extraCount > 0
                              ? '+${slot.extraCount}'
                              : null,
                          displayColorValue: mapCourseColor(
                              slot.courses.first.colorValue, ui.colorScheme),
                          cornerRadius: ui.cornerRadius,
                          borderWidth: ui.borderWidth,
                          textScale: ui.cardTextScale,
                          showClassroom: ui.showClassroom,
                          showTeacher: ui.showTeacher,
                          showNote: ui.showNote,
                        ),
                      ),
              ],
            ),
          ),
          // 页脚
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('由小马课表生成 · 无广告课表',
                style: TextStyle(fontSize: 10, color: scheme.outline)),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
