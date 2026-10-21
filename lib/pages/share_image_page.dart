import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../utils/color_schemes.dart';
import '../utils/override_effect.dart';
import '../utils/slot_layout.dart';
import '../utils/week_calc.dart';
import '../widgets/course_card.dart';

/// 课表导出图片页（1.2.0）
///
/// 把当前浏览周渲染成一张静态课表图（布局与主页同一套 SlotLayout 算法，
/// 配色/字体/字号/显示项跟随界面设置；固定浅色底，方便在微信等场景转发），
/// 通过系统分享面板发出去。导出图不含午休/晚餐分隔带（每节起止时间都标在
/// 左侧轴上，信息不丢），其余与 App 内所见一致。
class ShareImagePage extends ConsumerStatefulWidget {
  const ShareImagePage({super.key});

  @override
  ConsumerState<ShareImagePage> createState() => _ShareImagePageState();
}

class _ShareImagePageState extends ConsumerState<ShareImagePage> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  /// 导出图逻辑宽度（px）；截图时按 2 倍像素比出图，实际约 1440px 宽
  static const double _exportWidth = 720;
  static const double _axisWidth = 50;
  static const double _rowHeight = 56;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
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

    return Scaffold(
      appBar: AppBar(title: const Text('导出课表图片'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              '正在导出第 $week 周 · 在下方预览，点「分享图片」发给同学或保存',
              style: TextStyle(
                  fontSize: 13, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Theme(
                  // 导出图固定浅色：卡片用存储色原色，深色模式下也不发灰
                  data: ThemeData(
                    useMaterial3: true,
                    brightness: Brightness.light,
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: Color(ui.themeSeedValue)),
                    fontFamily: ui.fontFamily,
                  ),
                  child: _ExportSheet(
                    title: '${semester.name} · 第 $week 周课表',
                    dateRange:
                        '${dates.first.month}月${dates.first.day}日 - ${dates.last.month}月${dates.last.day}日',
                    displayDays: displayDays,
                    dates: dates,
                    slots: sortedSlots,
                    maxSection: maxSection,
                    pool: effective,
                    week: week,
                    ui: ui,
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

/// 导出图本体：标题 + 表头 + 时间轴/网格（尺寸固定，截图即成品）
class _ExportSheet extends StatelessWidget {
  const _ExportSheet({
    required this.title,
    required this.dateRange,
    required this.displayDays,
    required this.dates,
    required this.slots,
    required this.maxSection,
    required this.pool,
    required this.week,
    required this.ui,
  });

  final String title;
  final String dateRange;
  final List<int> displayDays;
  final List<DateTime> dates;
  final List<TimeSlot> slots;
  final int maxSection;

  /// 该周有效课程池（已应用调课）
  final List<Course> pool;
  final int week;
  final UiSettings ui;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    const width = _ShareImagePageState._exportWidth;
    const axisW = _ShareImagePageState._axisWidth;
    const rowH = _ShareImagePageState._rowHeight;
    final colW = (width - axisW) / displayDays.length;
    final gridH = maxSection * rowH;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题区
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                Text('小马课表',
                    style: TextStyle(fontSize: 13, color: scheme.outline)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(dateRange,
                  style: TextStyle(fontSize: 13, color: scheme.outline)),
            ),
          ),
          // 表头
          Container(
            height: 44,
            color: scheme.surfaceContainerLow,
            child: Row(
              children: [
                SizedBox(
                  width: axisW,
                  child: Center(
                    child: Text('${dates.first.month}月',
                        style:
                            TextStyle(fontSize: 12, color: scheme.outline)),
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
                                fontSize: 12, color: scheme.outline)),
                        Text('${dates[d - 1].day}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 网格区
          SizedBox(
            height: gridH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 时间轴
                SizedBox(
                  width: axisW,
                  child: Column(
                    children: [
                      for (final s in slots)
                        SizedBox(
                          height: rowH,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${s.section}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              Text(s.startTime,
                                  style: TextStyle(
                                      fontSize: 9, color: scheme.outline)),
                              Text(s.endTime,
                                  style: TextStyle(
                                      fontSize: 9, color: scheme.outline)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // 课程列
                for (final d in displayDays)
                  SizedBox(
                    width: colW,
                    child: Stack(
                      children: [
                        // 网格线
                        for (var r = 1; r < maxSection; r++)
                          Positioned(
                            top: r * rowH,
                            left: 0,
                            right: 0,
                            child: Container(
                                height: 0.5, color: scheme.outlineVariant),
                          ),
                        for (final slot in SlotLayout.layoutDay(
                          dayCourses: [
                            for (final c in pool)
                              if (c.dayOfWeek == d) c,
                          ],
                          week: week,
                          showDimmed: false,
                          maxSection: maxSection,
                        ))
                          if (!slot.isEmpty)
                            Positioned(
                              left: 1.5,
                              top: (slot.startSection - 1) * rowH + 1.5,
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
                                    slot.courses.first.colorValue,
                                    ui.colorScheme),
                                cornerRadius: ui.cornerRadius,
                                boldBorder: ui.boldBorder,
                                textScale: ui.cardTextScale,
                                showClassroom: ui.showClassroom,
                                showTeacher: ui.showTeacher,
                                showNote: ui.showNote,
                              ),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 页脚
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('由小马课表生成 · 无广告课表',
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
        ],
      ),
    );
  }
}
