import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/semester.dart';
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
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final rawSize = boundary.size;
      // WB_SPEC_237 §8：像素比封顶（宽 ≤1080、高 ≤1920），基准 3.0 倍。
      final pixelRatio = cappedExportPixelRatio(rawSize.width, rawSize.height);
      final pngBytes = await renderWithinLimit(
        (ratio) => _renderPng(boundary, ratio),
        pixelRatio,
      );
      if (pngBytes == null) throw StateError('图片生成失败');
      final week = ref.read(displayWeekProvider);
      await SharePlus.instance.share(
        ShareParams(
        files: [
          XFile.fromData(
            pngBytes,
            name: '小马课表-第$week周.png',
            mimeType: 'image/png',
          ),
        ],
        // WB_SPEC_232 第 4 节：分享文案不再带「· 小马课表」
        text: '我的课表（第 $week 周）',
        ),
      );
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
      courses: courses,
      overrides: overrides,
      week: week,
    );
    final displayDays = computeDisplayDays(
      effective,
      week,
      showOther,
      autoCollapse,
    );
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
                  color: Theme.of(context).colorScheme.outline,
                ),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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

  int _bandsBefore(int section) => bands.where((b) => section > b.after).length;

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
                  child: Text(
                    title,
                      style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                dateRange,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
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
                    child: Text(
                      '${dates.first.month}月',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ),
                ),
                for (final d in displayDays)
                  SizedBox(
                    width: colW,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _weekNames[d - 1],
                          style: TextStyle(fontSize: 10, color: scheme.outline),
                        ),
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
                    child: Container(height: 0.5, color: scheme.outlineVariant),
                  ),
                for (final b in bands)
                  Positioned(
                    top: topOf(b.after + 1),
                    left: 0,
                    right: 0,
                    child: Container(height: 0.5, color: scheme.outlineVariant),
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
                        width: 0.5,
                        color: scheme.outlineVariant,
                      ),
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
                        Text(
                          '${s.section}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (ui.axisShowTime) ...[
                          Text(
                            s.startTime,
                              style: TextStyle(
                              fontSize: 8,
                              color: scheme.outline,
                            ),
                          ),
                          Text(
                            s.endTime,
                              style: TextStyle(
                              fontSize: 8,
                              color: scheme.outline,
                            ),
                          ),
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
                              color: scheme.outline.withValues(alpha: 0.8),
                              letterSpacing: 4,
                            ),
                          ),
                          if (b.interval.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              b.interval,
                              style: TextStyle(
                                  fontSize: 11,
                                color: scheme.outline.withValues(alpha: 0.8),
                              ),
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
        badgeText: slot.extraCount > 0 ? '+${slot.extraCount}' : null,
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

/// 2MB 体积上限常量（WB_SPEC_237 / WB_SPEC_239 §3 & §5）
const int kMaxPngBytes = 2 * 1024 * 1024;

/// 方案 C：整学期一张图课表画布（WB_SPEC_239 §3 & §4）
///
/// 关键尺寸（375dp 宽 → 1080px 导出宽，pixelRatio 2.88）：
/// - 标题栏 54dp（主标题 17sp 加粗，副标题 11sp）
/// - 星期表头 34dp（11sp 加粗，周一～周日）
/// - 时间轴宽 34dp（节次 10sp 加粗，时间 7.5sp）
/// - 单节行高 36dp；午间/晚间分隔带 20dp（文字 9.5sp）
class SemesterSingleImageSheet extends StatelessWidget {
  const SemesterSingleImageSheet({
    super.key,
    this.width = 375.0,
    required this.semester,
    required this.courses,
    required this.slots,
    required this.bands,
    required this.ui,
    required this.displayDays,
  });

  final double width;
  final Semester semester;
  final List<Course> courses;
  final List<TimeSlot> slots;
  final List<GridBand> bands;
  final UiSettings ui;
  final List<int> displayDays;

  static const List<String> _dayNames = [
    '',
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  static const double kHeaderHeight = 54.0;
  static const double kWeekBarHeight = 34.0;
  // 时间轴宽与本周导出图（_ExportSheet）共用 kTimeAxisWidth（50dp）：
  // f5 初版自造的 34dp 在测试字体下连「08:00」都放不下（37.5dp），
  // 换行后把 36dp 的行高撑爆 7.5px；真机数字约 0.5em 虽能放下，
  // 但与现有导出图不一致，统一用共享常量。
  static const double kAxisWidth = kTimeAxisWidth;
  static const double kRowHeight = 36.0;
  static const double kSemesterBandHeight = 20.0;

  int _bandsBefore(int section) => bands.where((b) => section > b.after).length;

  String _formatDateDot(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '${dt.year}.$m.$d';
  }

  @override
  Widget build(BuildContext context) {
    final maxWeek = SemesterExportHelper.calculateMaxWeek(courses);
    final effectiveMaxWeek = maxWeek > 0 ? maxWeek : 1;
    final start = semester.startDateParsed;
    final end = start.add(Duration(days: effectiveMaxWeek * 7 - 1));
    final dateRangeText =
        '${_formatDateDot(start)} – ${_formatDateDot(end)} · 共 $effectiveMaxWeek 周（按课表自动检测）';
    final mainTitleText = '${semester.name} · 全学期课表（1–$effectiveMaxWeek周）';

    final maxSection = slots.isEmpty ? 14 : slots.length;
    final colW = (width - kAxisWidth) / displayDays.length;
    final gridH = maxSection * kRowHeight + bands.length * kSemesterBandHeight;

    double topOf(int section) =>
        (section - 1) * kRowHeight +
        _bandsBefore(section) * kSemesterBandHeight;
    double bandTop(GridBand b) =>
        b.after * kRowHeight + _bandsBefore(b.after) * kSemesterBandHeight;

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E1C19) : const Color(0xFFFAF9F5);
    final bandBg = isDark ? const Color(0xFF2E2A24) : const Color(0xFFF2EFE9);
    final bandTextColor = isDark
        ? const Color(0xFFC9B896)
        : const Color(0xFF78716C);
    final gridLineColor = isDark
        ? const Color(0xFF3A3733)
        : const Color(0xFFEBE8E0);

    // 画布固定 375 宽：内部 MediaQuery 也按画布尺寸走，让 ConflictBlock
    // 的小屏字号判定（视口 ≤600）与画布一致——否则在平板/宽视口设备上
    // 导出会走宽屏字号，标签塞不进 46dp 的列而溢出；导出图在任何设备
    // 上都应长一个样（WB_SPEC_239 §3：1080×1920 固定尺寸）。
    final sheetHeight = kHeaderHeight + kWeekBarHeight + gridH + 8.0;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(size: Size(width, sheetHeight)),
      child: Container(
        width: width,
        color: sheetBg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 顶部标题栏（54dp）
            SizedBox(
              height: kHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mainTitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateRangeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. 星期表头（34dp，写周一～周日）
            Container(
              height: kWeekBarHeight,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: gridLineColor, width: 0.5),
                  bottom: BorderSide(color: gridLineColor, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: kAxisWidth,
                    child: Center(
                      child: Text(
                        '节次',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  for (final d in displayDays)
                    Expanded(
                      child: Center(
                        child: Text(
                          _dayNames[d],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 3. 周视图网格主体
            SizedBox(
              width: width,
              height: gridH,
              child: Stack(
                children: [
                  // 左侧时间轴（宽 34dp，节次 10sp 加粗，起止时间 7.5sp）
                  for (final slot in slots)
                    Positioned(
                      left: 0,
                      top: topOf(slot.section),
                      width: kAxisWidth,
                      height: kRowHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: gridLineColor, width: 0.5),
                            bottom: BorderSide(
                              color: gridLineColor.withValues(alpha: 0.5),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${slot.section}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: scheme.onSurface,
                                height: 1.1,
                              ),
                            ),
                            if (ui.axisShowTime) ...[
                              // 起止时间拆成两个独立 Text（与本周导出图 _ExportSheet
                              // 同款写法）：一个 Text 里写 '08:00\n08:40' 时，
                              // 轴宽不够会把每行都换行，行高直接撑爆。
                              Text(
                                slot.startTime,
                                style: TextStyle(
                                  fontSize: 7.5,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.05,
                                ),
                              ),
                              Text(
                                slot.endTime,
                                style: TextStyle(
                                  fontSize: 7.5,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // 午间 / 晚间分隔带（高 20dp，文字 9.5sp）
                  for (final b in bands)
                    Positioned(
                      left: 0,
                      top: bandTop(b),
                      width: width,
                      height: kSemesterBandHeight,
                      child: Container(
                        color: bandBg,
                        alignment: Alignment.center,
                        child: Text(
                          '${b.label} ${b.interval}',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: bandTextColor,
                          ),
                        ),
                      ),
                    ),

                  // 课程块与冲突块渲染
                  for (var di = 0; di < displayDays.length; di++)
                    for (final mSlot
                        in SemesterExportHelper.layoutSemesterMasterDay(
                          dayCourses: courses,
                          dayOfWeek: displayDays[di],
                          maxSection: maxSection,
                        ))
                      Positioned(
                        left: kAxisWidth + di * colW + 1.0,
                        top: topOf(mSlot.startSection) + 1.0,
                        width: colW - 2.0,
                        height: mSlot.span * kRowHeight - 2.0,
                        child: _buildMasterSlotWidget(
                          mSlot,
                          colW - 2.0,
                          mSlot.span * kRowHeight - 2.0,
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterSlotWidget(SemesterMasterSlot mSlot, double w, double h) {
    switch (mSlot.kind) {
      case SemesterMasterSlotKind.conflict:
        final pair = mSlot.conflictPair!;
        return ConflictBlock(
          topCourse: pair.topCourse,
          bottomCourse: pair.bottomCourse,
          width: w,
          height: h,
          colorId: ui.conflictBlockColorId,
          intensity: ui.conflictGradientIntensity,
          blurEnabled: ui.conflictBlurEnabled,
        );
      case SemesterMasterSlotKind.parityPair:
        final topC = mSlot.courses[0];
        final botC = mSlot.courses[1];
        return Column(
          children: [
            Expanded(
              child: _SingleMasterCard(course: topC, ui: ui, compact: true),
            ),
            const SizedBox(height: 1.5),
            Expanded(
              child: _SingleMasterCard(course: botC, ui: ui, compact: true),
            ),
          ],
        );
      case SemesterMasterSlotKind.single:
        return _SingleMasterCard(
          course: mSlot.courses.first,
          ui: ui,
          compact: false,
        );
    }
  }
}

/// 方案 C 普通课程卡片（课名 10sp 加粗、教室/老师 8.5sp、周次胶囊 7.5sp 加粗白底 65%）
class _SingleMasterCard extends StatelessWidget {
  const _SingleMasterCard({
    required this.course,
    required this.ui,
    required this.compact,
  });

  final Course course;
  final UiSettings ui;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bgColor = Color(mapCourseColor(course.colorValue, ui.colorScheme));
    final weekCapsule = SemesterExportHelper.formatWeekCapsule(course);
    final metaParts = <String>[
      if (ui.showClassroom &&
          course.classroom != null &&
          course.classroom!.trim().isNotEmpty)
        course.classroom!.trim(),
      if (!compact &&
          ui.showTeacher &&
          course.teacher != null &&
          course.teacher!.trim().isNotEmpty)
        course.teacher!.trim(),
    ];
    final metaText = metaParts.join(' · ');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 3, vertical: compact ? 1.5 : 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(compact ? 5 : 7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.name,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 8.5 : 10.0,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1F2937),
                  height: 1.2,
                ),
              ),
              if (metaText.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  metaText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 7.5 : 8.5,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF374151),
                    height: 1.15,
                  ),
                ),
              ],
            ],
          ),
          if (weekCapsule.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                weekCapsule,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 离屏渲染整学期单张 PNG 并调用 SharePlus 分享（WB_SPEC_239 §2 & §3）
///
/// 像素比与体积降级复用本文件已有的 [cappedExportPixelRatio] /
/// [renderWithinLimit]（与本周 PNG 同一套口径，不另起签名）。
/// [invokeShare] 为 false 时只返回字节、不调分享面板——导出 BottomSheet
/// 先收起 sheet、弹「正在打开分享面板」提示，再自己调分享（P1-2 时序）。
///
/// 注意：形参名用 [uiSettings] 而不用 `ui`——`ui` 会遮住本文件顶部的
/// `dart:ui as ui` 前缀，导致 `ui.ImageByteFormat` 解析到 UiSettings 上。
Future<Uint8List> generateAndShareSemesterSinglePng({
  required BuildContext context,
  required Semester semester,
  required List<Course> courses,
  required List<TimeSlot> slots,
  required List<GridBand> bands,
  required UiSettings uiSettings,
  List<int> displayDays = const [1, 2, 3, 4, 5, 6, 7],
  bool invokeShare = true,
}) async {
  final boundaryKey = GlobalKey();
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: -2000,
      top: 0,
      child: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SemesterSingleImageSheet(
            width: 375.0,
            semester: semester,
            courses: courses,
            slots: slots,
            bands: bands,
            ui: uiSettings,
            displayDays: displayDays,
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final pngBytes = await renderWithinLimit((ratio) async {
      final img = await boundary.toImage(pixelRatio: ratio);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bd == null) throw StateError('整学期图片编码失败');
      return bd.buffer.asUint8List();
    }, cappedExportPixelRatio(boundary.size.width, boundary.size.height));
    if (pngBytes == null) throw StateError('整学期图片编码失败');

    if (invokeShare) {
      final fileName = '${semester.name}课表.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(pngBytes, name: fileName, mimeType: 'image/png'),
          ],
          text: '这是${semester.name}完整课表，请查收',
        ),
      );
    }
    return pngBytes;
  } finally {
    entry.remove();
  }
}
