import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/fonts_service.dart';
import '../utils/app_haptics.dart';
import '../ui/app_styles.dart';
import '../ui/grid_metrics.dart';
import '../utils/color_schemes.dart';
import '../utils/override_effect.dart';
import '../utils/semester_export_helper.dart';
import '../utils/slot_layout.dart';
import '../utils/week_calc.dart';
import '../widgets/conflict_block.dart';
import '../widgets/course_card.dart';

/// WB_SPEC_243 §2：相册保存处理器（默认调 Gal.putImageBytes，测试时可替换为 mock）。
typedef SaveImageToGalleryHandler = Future<void> Function(
  Uint8List bytes, {
  required String name,
});

Future<void> _defaultSaveImageToGallery(
  Uint8List bytes, {
  required String name,
}) async {
  await Gal.putImageBytes(bytes, name: name);
}

SaveImageToGalleryHandler saveImageToGalleryHandler =
    _defaultSaveImageToGallery;

/// WB_SPEC_243 §2：本周导出 PNG 渲染处理器（默认真实 toImage 渲染；测试时
/// 可替换为假字节——flutter_tester 里调 toImage 会死等，见 WB_SPEC_239
/// 测试注释。只替换单次光栅化，像素比封顶与 2MB 降级循环仍在 _obtainPngBytes）。
typedef WeekPngRenderer = Future<Uint8List?> Function(
  RenderRepaintBoundary boundary,
  double pixelRatio,
);

Future<Uint8List?> _defaultWeekPngRenderer(
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

WeekPngRenderer weekPngRenderer = _defaultWeekPngRenderer;

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
  bool _saving = false;

  /// WB_SPEC_243 §2：缓存当前页面渲染出的 PNG 字节，使「保存到本地」与「分享图片」
  /// 共用同一份渲染结果，避免重复渲染。签名覆盖周次、界面设置、有效课程、
  /// 节次与显示天数——任一变化都失效重算，不拿旧图。
  Uint8List? _cachedPngBytes;
  String? _cachedSignature;

  String _computeSignature({
    required int week,
    required UiSettings ui,
    required List<Course> effective,
    required List<TimeSlot> slots,
    required List<int> displayDays,
  }) {
    final courseSig = effective
        .map(
          (c) =>
              '${c.id}:${c.name}:${c.classroom}:${c.teacher}:${c.colorValue}:${c.dayOfWeek}:${c.startSection}:${c.endSection}:${c.weeks.join(',')}:${c.weekType}',
        )
        .join('|');
    final slotSig = slots
        .map((s) => '${s.section}:${s.startTime}:${s.endTime}')
        .join('|');
    return '$week|${ui.encode()}|$courseSig|$slotSig|${displayDays.join(',')}';
  }

  /// 渲染一次并缓存字节；签名未变时直接返回已渲染的字节。
  /// 与原 _share() 同款口径：像素比封顶 + 逐档降级 + 2MB 上限复核。
  Future<Uint8List> _obtainPngBytes() async {
    final week = ref.read(displayWeekProvider);
    // P1-5：用 .future 等 provider 就绪再渲染，避免首次进页 provider
    // 未就绪时按默认值存了空图（与整学期 _renderSemesterBytes 同口径）。
    final uiSettings = await ref.read(uiSettingsProvider.future);
    final courses = await ref.read(coursesProvider.future);
    final overrides = await ref.read(courseOverridesProvider.future);
    final slots = await ref.read(timeSlotsProvider.future);
    final showOther = ref.read(showOtherWeeksProvider);
    final autoCollapse = ref.read(autoCollapseWeekendProvider);
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
    final sig = _computeSignature(
      week: week,
      ui: uiSettings,
      effective: effective,
      slots: slots,
      displayDays: displayDays,
    );
    if (_cachedPngBytes != null && _cachedSignature == sig) {
      return _cachedPngBytes!;
    }

    final boundary =
        _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final rawSize = boundary.size;
    // WB_SPEC_237 §8：像素比封顶（宽 ≤1080、高 ≤1920），基准 3.0 倍。
    final pixelRatio = cappedExportPixelRatio(rawSize.width, rawSize.height);
    final pngBytes = await renderWithinLimit(
      (ratio) => weekPngRenderer(boundary, ratio),
      pixelRatio,
    );
    if (pngBytes == null) throw StateError('图片生成失败');
    // P1-5：与整学期导出同一口径——降到 1.0 仍超限时不分享/不保存超限文件。
    if (!isWithinPngLimit(pngBytes)) {
      throw StateError('图片超过 2MB 上限');
    }
    _cachedPngBytes = pngBytes;
    _cachedSignature = sig;
    return pngBytes;
  }

  /// WB_SPEC_243 §2：保存本周课表到系统相册。
  Future<void> _saveToLocal() async {
    if (_saving || _sharing) return;
    setState(() => _saving = true);
    try {
      final bytes = await _obtainPngBytes();
      final week = ref.read(displayWeekProvider);
      final fileName = '小马课表-第$week周.png';
      // gal 3.x 会按字节自行识别扩展名并拼到 name 后面（见 gal 源码
      // getUniqueFileUri），name 里不要带 .png，否则存成「.png.png」。
      await saveImageToGalleryHandler(bytes, name: '小马课表-第$week周');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存到相册：$fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing || _saving) return;
    setState(() => _sharing = true);
    try {
      final pngBytes = await _obtainPngBytes();
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
          // WB_SPEC_243 §2：保存到本地 + 分享图片双按钮，共用同一份渲染字节。
          // WB_SPEC_235 跟进 §1-16：主按钮 = 轻点档。
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('btn_save_week_png'),
                  style: OutlinedButton.styleFrom(enableFeedback: false),
                  onPressed: (_saving || _sharing)
                      ? null
                      : () {
                          AppHaptics.tap();
                          _saveToLocal();
                        },
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt),
                  label: Text(_saving ? '保存中…' : '保存到本地'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('btn_share_week_png'),
                  style: FilledButton.styleFrom(enableFeedback: false),
                  onPressed: (_sharing || _saving)
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
            ],
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
                // 分隔带（WB_SPEC_243 §1：与 App 内周视图一致——轴列写名称，
                // 通栏只留同色底，不画居中名称与时间段）
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
                    child: Container(color: bandColor),
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
                        // 跨带卡高 = 末节底 − 首节顶 − 3（含跨过的午间/晚间
                        // 分隔带；3dp 是上下各 1.5dp 留白，与 top 的 +1.5 对应）。
                        // 注意：用 topOf(end)+行高，不用 topOf(end+1)——末节
                        // 后有带子时 topOf(end+1) 会把带子也算进来，3–5 节
                        // 这种止于带前的课会盖住午间/晚间带（2.7.0 回归）。
                        // 旧公式 span × 行高 − 3 漏了带子：5–6 节跨午间带时
                        // 短 24dp。不跨带时与旧公式等价。
                        height:
                            topOf(slot.endSection) +
                            rowH -
                            topOf(slot.startSection) -
                            3,
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

/// 体积复核（P1-5）：[renderWithinLimit] 降到 1.0 仍超限时照样返回最后一次
/// 结果，调用方必须用它复核——超限不得分享（微信发不出去还占流量）。
bool isWithinPngLimit(Uint8List bytes) => bytes.lengthInBytes <= kMaxPngBytes;

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
  // 目标导出像素尺寸（WB_SPEC_239 §3）：1080×1920。
  static const double kTargetExportWidthPx = 1080.0;
  static const double kTargetExportHeightPx = 1920.0;
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

    // P1-3：课程块高度 = 末节底 - 首节顶 - 2（含跨过的午间/晚间
    // 分隔带高度）。旧公式 span × 行高 - 2 漏了带子：5–6 节跨午间带时
    // 少 20dp，卡片底边截断错位（冲突块同理）。
    // 注意：用 topOf(end)+行高，不用 topOf(end+1)——末节后有带子时
    // topOf(end+1) 会把带子也算进来，3–5 节这种止于带前的课会盖住
    // 午间/晚间带（2.7.0 回归）。
    double slotHeight(SemesterMasterSlot m) =>
        topOf(m.endSection) + kRowHeight - topOf(m.startSection) - 2.0;

    // WB_SPEC_241：导出图固定浅色（239 定案：卡片用存储色原色，深色
    // 模式下也不发灰），颜色统一走浅色 colorScheme（与 _ExportSheet
    // 的导出 Theme 同口径），不再硬编码色值；与 App 内周视图共用
    // 同一套设计 token（surface / surfaceContainer / onSurface 等）。
    final scheme = buildAppColorScheme(
      Color(ui.themeSeedValue),
      Brightness.light,
    );
    final sheetBg = scheme.surface;
    // WB_SPEC_243 §1：带子底色与 App 内周视图（_FullBand）一致，
    // 不再用 surfaceContainer。
    final bandBg = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final gridLineColor = scheme.outlineVariant;

    // P1-2：画布高度固定为 1080×1920 反推的逻辑高（375dp 宽时 666.67dp），
    // 不再随内容自然高走（14 节 + 2 带自然高只有 640dp，导出是 1080×1843；
    // 默认 13 节时自然高 604dp，导出是 1080×1740）。内容不足时底部补白，
    // 行高仍按规格 36dp 不动；节次更多、自然高超过目标时不裁内容，
    // 按自然高出图（这时不保证 1920，规格只覆盖标准 13–14 节）。
    final naturalHeight = kHeaderHeight + kWeekBarHeight + gridH + 8.0;
    final targetHeight = kTargetExportHeightPx * width / kTargetExportWidthPx;
    final sheetHeight = naturalHeight > targetHeight
        ? naturalHeight
        : targetHeight;
    final bottomPad =
        sheetHeight - (kHeaderHeight + kWeekBarHeight + gridH);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(size: Size(width, sheetHeight)),
      child: Container(
        width: width,
        height: sheetHeight,
        color: sheetBg,
        child: Column(
          mainAxisSize: MainAxisSize.max,
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

                  // WB_SPEC_243 §1：午间 / 晚间分隔带（高 20dp）——与 App 内
                  // 周视图一致：轴列写名称「午间」/「晚间」，通栏只留底色，
                  // 不写居中「午间 12:00-14:00」。
                  for (final b in bands)
                    Positioned(
                      left: 0,
                      top: bandTop(b),
                      width: width,
                      height: kSemesterBandHeight,
                      child: Container(
                        color: bandBg,
                        child: Row(
                          children: [
                            SizedBox(
                              width: kAxisWidth,
                              child: Center(
                                child: Text(
                                  b.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.outline.withValues(
                                      alpha: 0.9,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Expanded(child: SizedBox.shrink()),
                          ],
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
                        height: slotHeight(mSlot),
                        child: _buildMasterSlotWidget(
                          mSlot,
                          colW - 2.0,
                          slotHeight(mSlot),
                        ),
                      ),
                ],
              ),
            ),
            SizedBox(height: bottomPad),
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
        final halfH = (h - 1.5) / 2;
        return Column(
          children: [
            Expanded(
              child: _SingleMasterCard(course: topC, ui: ui, height: halfH),
            ),
            const SizedBox(height: 1.5),
            Expanded(
              child: _SingleMasterCard(course: botC, ui: ui, height: halfH),
            ),
          ],
        );
      case SemesterMasterSlotKind.stack:
        // P1-1 多行分块：每门各占一行，行高按实际均分传给卡片（P1-4 分档）。
        final n = mSlot.courses.length;
        final rowH = (h - 1.0 * (n - 1)) / n;
        return Column(
          children: [
            for (var k = 0; k < n; k++) ...[
              if (k > 0) const SizedBox(height: 1.0),
              Expanded(
                child: _SingleMasterCard(
                  course: mSlot.courses[k],
                  ui: ui,
                  height: rowH,
                ),
              ),
            ],
          ],
        );
      case SemesterMasterSlotKind.single:
        return _SingleMasterCard(
          course: mSlot.courses.first,
          ui: ui,
          height: h,
        );
    }
  }
}

/// 方案 C 普通课程卡片（课名 10sp 加粗、教室/老师 8.5sp、周次胶囊 7.5sp 加粗白底 65%）
///
/// WB_SPEC_243 §1：教室/老师与 CourseCard 同款 Text.rich 分行换行显示，
/// 不再拼成一行 maxLines: 1 截断（原写法教室截成「16-102 …」、老师看不到）。
/// 总行数按卡片实际高度动态算（名行 12dp、元数据行约 10dp、胶囊预留 12dp），
/// 超出行数整体省略，不溢出；矮卡显隐阈值（showMeta ≥40、showCapsule ≥30）不动。
class _SingleMasterCard extends StatelessWidget {
  const _SingleMasterCard({
    required this.course,
    required this.ui,
    required this.height,
  });

  final Course course;
  final UiSettings ui;

  /// 卡片可用高度（dp，父级按格高均分后传入）。
  final double height;

  @override
  Widget build(BuildContext context) {
    final bgColor = Color(mapCourseColor(course.colorValue, ui.colorScheme));
    // WB_SPEC_241：文字色与胶囊走浅色 colorScheme（与 App 内周视图
    // 同口径），不再硬编码 0xFF1F2937 / 0xFF374151。
    final scheme = buildAppColorScheme(
      Color(ui.themeSeedValue),
      Brightness.light,
    );
    final weekCapsule = SemesterExportHelper.formatWeekCapsule(course);
    // 矮卡先藏教室/老师，再藏周次胶囊；课名永远保留。
    final showMeta = height >= 40;
    final showCapsule = height >= 30;
    final nameSize = height >= 30 ? 10.0 : (height >= 14 ? 8.5 : 7.5);
    final padV = height >= 30 ? 3.0 : (height >= 14 ? 1.5 : 0.5);

    final classroomText = (showMeta &&
            ui.showClassroom &&
            course.classroom != null &&
            course.classroom!.trim().isNotEmpty)
        ? course.classroom!.trim()
        : null;
    final teacherText = (showMeta &&
            ui.showTeacher &&
            course.teacher != null &&
            course.teacher!.trim().isNotEmpty)
        ? course.teacher!.trim()
        : null;

    // 行数预算（P0-1 复审修正）：名行与元数据行分开计——名行高
    // nameSize×1.2（10sp 档 12dp），元数据行高 8.5×1.18（约 10dp）。
    // 用名行高一刀切会低估行数：40dp 卡只剩 1 行、教室/老师全被藏掉，
    // 52dp 卡只剩 2 行、老师被截。顺序：课名至少 1 行，剩余高度能放
    // 几行元数据就放几行（放不下时老师先被截）；胶囊预留 11dp（实高约 10.75dp）。
    final nameLineH = nameSize * 1.2;
    const metaLineH = 8.5 * 1.18;
    final reserveH = (showCapsule && weekCapsule.isNotEmpty) ? 11.0 : 0.0;
    final availTextH = (height - padV * 2 - reserveH).clamp(10.0, 400.0);
    var metaLines = 0;
    if (classroomText != null) metaLines++;
    if (teacherText != null) metaLines++;
    // 先给课名留 1 行，剩下的高度放元数据行。
    final fittedMetaLines =
        ((availTextH - nameLineH) / metaLineH).floor().clamp(0, metaLines);
    // 课名最多 2 行（与原 ≥52 档同口径），其余高度归元数据。
    final nameMaxLines = height >= 52 ? 2 : 1;
    final nameLines = ((availTextH - fittedMetaLines * metaLineH) / nameLineH)
        .floor()
        .clamp(1, nameMaxLines);
    final totalMaxLines = nameLines + fittedMetaLines;

    final metaStyle = TextStyle(
      fontSize: 8.5,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
      height: 1.18,
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 3, vertical: padV),
      decoration: BoxDecoration(
        color: bgColor,
        // WB_SPEC_241：课卡圆角与 App 内周视图一致，用 ui.cornerRadius
        //（默认 12），不再硬编码 7/5。
        borderRadius: BorderRadius.circular(ui.cornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: course.name,
                    style: TextStyle(
                      fontSize: nameSize,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      height: 1.2,
                    ),
                  ),
                  if (classroomText != null)
                    TextSpan(
                      text: '\n$classroomText',
                      style: metaStyle,
                    ),
                  if (teacherText != null)
                    TextSpan(
                      text: '\n$teacherText',
                      style: metaStyle,
                    ),
                ],
              ),
              maxLines: totalMaxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showCapsule && weekCapsule.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
              child: Text(
                weekCapsule,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
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

  // WB_SPEC_243 §1：离屏 Overlay 显式包一层浅色 Theme（种子取当前实际
  // UiSettings），杜绝深色系统下离屏渲染退回默认冷白色。
  final lightScheme = buildAppColorScheme(
    Color(uiSettings.themeSeedValue),
    Brightness.light,
  );

  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: -2000,
      top: 0,
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: lightScheme,
          scaffoldBackgroundColor: lightScheme.surface,
        ),
        child: Material(
          color: lightScheme.surface,
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
    // P1-5：renderWithinLimit 降到 1.0 仍超限时返回最后一次结果；
    // 这里复核体积，超限抛错走「导出失败」弹窗，不分享超限文件。
    if (!isWithinPngLimit(pngBytes)) {
      throw StateError('整学期图片超过 2MB 上限，导出失败');
    }

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
