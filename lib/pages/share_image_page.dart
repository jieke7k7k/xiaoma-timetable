import 'dart:typed_data';
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
import '../utils/app_haptics.dart';
import '../ui/grid_metrics.dart';
import '../utils/color_schemes.dart';
import '../utils/override_effect.dart';
import '../utils/semester_export_helper.dart';
import '../utils/slot_layout.dart';
import '../utils/week_calc.dart';
import '../widgets/conflict_block.dart';
import '../widgets/course_card.dart';

/// 导出图像素比封顶（WB_SPEC_237 §8）：宽 ≤1080、高 ≤1920，基准 3.0 倍。
/// 纯函数，可单元测试。
double cappedExportPixelRatio(double width, double height) {
  var ratio = 3.0;
  if (width * ratio > 1080) ratio = 1080 / width;
  if (height * ratio > 1920) ratio = 1920 / height;
  return ratio;
}

/// 体积上限 2MB：逐档降像素比重渲，每次复核体积，直到 ≤2MB 或降到 1.0。
///
/// 抽成顶层纯逻辑（P1-8）：循环本身不依赖 widget，只依赖「按像素比渲染」
/// 这个回调；抽出来后单测可以直接喂假渲染断言 ≤2MB 的兜底行为，
/// 不用在 flutter_tester 里调 toImage（会死等）。
/// 行为与原来内联在 _share() 里的循环一致：某次重渲返回 null 时保留
/// 上一次的字节；降到 1.0 仍超限时照样返回（由调用方决定是否分享）。
Future<Uint8List?> renderWithinLimit(
  Future<Uint8List?> Function(double ratio) render,
  double initialRatio, {
  int maxBytes = 2 * 1024 * 1024,
}) async {
  var ratio = initialRatio;
  var bytes = await render(ratio);
  while (bytes != null && bytes.lengthInBytes > maxBytes && ratio > 1.0) {
    ratio = (ratio * 0.75).clamp(1.0, 3.0);
    final retry = await render(ratio);
    if (retry == null) break;
    bytes = retry;
  }
  return bytes;
}

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
      final rawSize = boundary.size;
      // WB_SPEC_237 §8：像素比封顶（宽 ≤1080、高 ≤1920），基准 3.0 倍。
      final pixelRatio =
          cappedExportPixelRatio(rawSize.width, rawSize.height);
      final pngBytes = await renderWithinLimit(
        (ratio) => _renderPng(boundary, ratio),
        pixelRatio,
      );
      if (pngBytes == null) throw StateError('图片生成失败');
      final week = ref.read(displayWeekProvider);
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(
            pngBytes,
            name: '小马课表-第$week周.png',
            mimeType: 'image/png',
          ),
        ],
        // WB_SPEC_232 第 4 节：分享文案不再带「· 小马课表」
        text: '我的课表（第 $week 周）',
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

  Future<Uint8List?> _renderPng(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    // P1-3：toImage() 拿到的 ui.Image 必须 dispose，否则 >2MB 重渲循环
    // 里连建多张全尺寸位图不释放，内存峰值越堆越高。
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
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
    final bandSettings =
        ref.watch(bandSettingsProvider).value ?? const BandSettings();
    if (semester == null || slots.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final effective = effectiveCoursesForWeek(
        courses: courses, overrides: overrides, week: week);
    final displayDays =
        computeDisplayDays(effective, week, showOther, autoCollapse);
    final dates = WeekCalc.weekDatesOf(semester.startDateParsed, week);
    final sortedSlots = [...slots]
      ..sort((a, b) => a.section.compareTo(b.section));
    final maxSection = sortedSlots.last.section;
    // 分隔带与主页同源（WB_SPEC_209 第 6 节）：位置来自分段设置，显隐与
    // 标注时间来自休息时段设置，与主页共用 computeActiveBands 同一份口径，
    // 保证主页隐藏/自定义时间的带子在导出图里同样生效，不出现不一致。
    final bands = computeActiveBands(
      lunchAfter: seg?.lunchAfterSection ?? 5,
      dinnerAfter: seg?.dinnerAfterSection ?? 9,
      sectionCount: maxSection,
      settings: bandSettings,
    );
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
                  // 导出图固定浅色：卡片用存储色原色，深色模式下也不发灰；
                  // 配色走生产唯一入口，与 App 内同口径（中性 surface/容器）
                  data: ThemeData(
                    useMaterial3: true,
                    brightness: Brightness.light,
                    colorScheme: buildAppColorScheme(
                      Color(ui.themeSeedValue),
                      Brightness.light,
                    ),
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
          // WB_SPEC_235 跟进 §1-16：分享图片主按钮 = 轻点档
          child: FilledButton.icon(
            style: FilledButton.styleFrom(enableFeedback: false),
            onPressed: _sharing
                ? null
                : () {
                    AppHaptics.tap();
                    _share();
                  },
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
        // 复查优化 1：与 topOf/_bandsBefore 同口径，不再手写 where 计数
        b.after * rowH + _bandsBefore(b.after) * kBandHeight;
    final scheme = Theme.of(context).colorScheme;
    final bandColor = scheme.surfaceContainerHighest.withValues(alpha: 0.6);

    return Container(
      width: width,
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题区（紧凑一行 + 日期范围）
          //
          // WB_SPEC_232 第 4 节：右上角「小马课表」水印已删，标题独占整行；
          // Expanded 保留（标题仍可占满宽度、不与右侧挤在一起），不留占位空块。
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
                // 横向网格线：每节底边（节次分隔线，含带子顶边）+ 带子底边；
                // 带子内部无线。与主页 _FullWidthLinesPainter 口径一致（不含最后一条底边）
                for (var r = 1; r < maxSection; r++)
                  Positioned(
                    top: topOf(r) + rowH,
                    left: 0,
                    right: 0,
                    child: Container(
                        height: 0.5, color: scheme.outlineVariant),
                  ),
                for (final b in bands)
                  Positioned(
                    top: topOf(b.after + 1),
                    left: 0,
                    right: 0,
                    child: Container(
                        height: 0.5, color: scheme.outlineVariant),
                  ),
                // 纵向列线：竖线按节次段分段，跳过休息带（WB_SPEC_210 第 2 节，
                // 与主页共用 verticalLineSegments 同一份口径，带子内不画竖线）
                for (var c = 0; c <= displayDays.length; c++)
                  for (final seg in verticalLineSegments(
                    rowHeight: rowH,
                    sectionCount: maxSection,
                    activeBands: bands,
                  ))
                    Positioned(
                      left: axisW + c * colW,
                      top: seg.start,
                      height: seg.end - seg.start,
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
                      _slotWidget(
                        slot: slot,
                        left: axisW + di * colW + 1.5,
                        top: topOf(slot.startSection) + 1.5,
                        width: colW - 3,
                        height: slot.span * rowH - 3,
                      ),
              ],
            ),
          ),
          // WB_SPEC_232 第 4 节：页脚「由小马课表生成 · 无广告课表」整块删除。
          // 页脚原来是网格下唯一的留白来源，删掉后在外层容器补等量底部内边距
          // ——原页脚的外层内边距是 8dp，这里保留同一档，网格不贴图片下边缘。
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 一格课程卡：双课冲突且按 §4.1 分组时画 ConflictBlock（checkConflict
  /// 只调一次，结果复用），否则画原样 CourseCard。
  /// P1-5：三门及以上同格不画冲突块（只画两门）——已统计，测试学期
  /// 数据（8 门课，18 周）逐周数过，最大同格 2 门，≥3 同格 0 处，
  /// 所以这个 fallback 目前走不到；真出现三门同格时按规格 §14 报他定，
  /// 不擅自改（见 wb237 测试 §4.1 的统计用例）。
  Widget _slotWidget({
    required DisplaySlot slot,
    required double left,
    required double top,
    required double width,
    required double height,
  }) {
    if (slot.kind == SlotKind.multi && slot.courses.length == 2) {
      final pair = SemesterExportHelper.checkConflict(
        slot.courses[0],
        slot.courses[1],
        week,
      );
      if (pair != null) {
        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: ConflictBlock(
            topCourse: pair.topCourse,
            bottomCourse: pair.bottomCourse,
            height: height,
            width: width,
            colorId: ui.conflictBlockColorId,
            intensity: ui.conflictGradientIntensity,
            blurEnabled: ui.conflictBlurEnabled,
          ),
        );
      }
    }
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: CourseCard(
        course: slot.courses.first,
        onTap: () {},
        onLongPress: () {},
        badgeText:
            slot.extraCount > 0 ? '+${slot.extraCount}' : null,
        displayColorValue: mapCourseColor(
          slot.courses.first.colorValue,
          ui.colorScheme,
        ),
        cornerRadius: ui.cornerRadius,
        borderWidth: ui.borderWidth,
        textScale: ui.cardTextScale,
        showClassroom: ui.showClassroom,
        showTeacher: ui.showTeacher,
        showNote: ui.showNote,
      ),
    );
  }
}
