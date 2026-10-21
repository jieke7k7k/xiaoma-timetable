import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/fonts_service.dart';
import '../ui/grid_metrics.dart';
import '../utils/color_schemes.dart';
import '../utils/morandi_palette.dart';
import '../utils/override_effect.dart';
import '../utils/slot_layout.dart';
import '../widgets/course_card.dart';

/// 界面设置页（1.1.1）：格子外观、显示内容、课程配色、主题颜色、显示字体。
///
/// 顶部是实时预览：所有调节都会立即反映到预览（以及整个 App——主题色/
/// 字体在 MaterialApp 层监听同一份设置），所见即所得。
class UiSettingsPage extends ConsumerWidget {
  const UiSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    void apply(UiSettings next) => notifier.apply(next);

    // 预览 1:1 所需的真实网格参数：列数与主页当前周完全同源计算，
    // 节次时间取真实作息，保证预览不是「差不多」而是同一套尺寸
    final courses = ref.watch(coursesProvider).value ?? const [];
    final overrides = ref.watch(courseOverridesProvider).value ?? const [];
    final displayWeek = ref.watch(displayWeekProvider);
    final showOther = ref.watch(showOtherWeeksProvider);
    final autoCollapse = ref.watch(autoCollapseWeekendProvider);
    final previewDays = computeDisplayDays(
      effectiveCoursesForWeek(
        courses: courses,
        overrides: overrides,
        week: displayWeek,
      ),
      displayWeek,
      showOther,
      autoCollapse,
    );
    final slots = ref.watch(timeSlotsProvider).value ?? const <TimeSlot>[];

    return Scaffold(
      appBar: AppBar(title: const Text('界面设置'), centerTitle: true),
      body: ListView(
        children: [
          const _Header('实时预览'),
          _Preview(ui: ui, columnCount: previewDays.length, slots: slots),
          const _Header('格子外观'),
          SwitchListTile(
            title: const Text('行高自适应一屏'),
            subtitle: const Text('按屏幕高度均分行高，整张课表不用上下滚'),
            value: ui.autoFitHeight,
            onChanged: (v) => apply(ui.copyWith(autoFitHeight: v)),
          ),
          _SliderRow(
            label: '课程格子高度',
            valueText: ui.autoFitHeight
                ? '自适应中'
                : '${ui.cellHeight.round()} px',
            value: ui.cellHeight,
            min: 44,
            max: 96,
            divisions: 26,
            onChanged: ui.autoFitHeight
                ? (_) {}
                : (v) => apply(ui.copyWith(cellHeight: v)),
          ),
          _SliderRow(
            label: '格子圆角半径',
            valueText: '${ui.cornerRadius.round()} px',
            value: ui.cornerRadius,
            min: 0,
            max: 20,
            divisions: 20,
            onChanged: (v) => apply(ui.copyWith(cornerRadius: v)),
          ),
          SwitchListTile(
            title: const Text('显示网格线'),
            value: ui.showGridLines,
            onChanged: (v) => apply(ui.copyWith(showGridLines: v)),
          ),
          _SliderRow(
            label: '格子边框粗细',
            valueText: ui.borderWidth <= 0
                ? '无边框'
                : '${ui.borderWidth.toStringAsFixed(1)} px',
            value: ui.borderWidth,
            min: UiSettings.borderWidthMin,
            max: UiSettings.borderWidthMax,
            divisions: 30,
            onChanged: (v) => apply(ui.copyWith(borderWidth: v)),
          ),
          SwitchListTile(
            title: const Text('节数栏显示时间'),
            subtitle: const Text('关掉后左侧只显示节次数字'),
            value: ui.axisShowTime,
            onChanged: (v) => apply(ui.copyWith(axisShowTime: v)),
          ),
          SwitchListTile(
            title: const Text('标题显示单双周'),
            subtitle: const Text('关掉后左上角只显示「第 X 周」'),
            value: ui.showParityLabel,
            onChanged: (v) => apply(ui.copyWith(showParityLabel: v)),
          ),
          const _Header('卡片显示'),
          _SliderRow(
            label: '卡片文字大小',
            valueText: '${(ui.cardTextScale * 100).round()}%',
            value: ui.cardTextScale,
            min: UiSettings.textScaleMin,
            max: UiSettings.textScaleMax,
            divisions: 50,
            onChanged: (v) => apply(ui.copyWith(cardTextScale: v)),
          ),
          SwitchListTile(
            title: const Text('显示教室'),
            value: ui.showClassroom,
            onChanged: (v) => apply(ui.copyWith(showClassroom: v)),
          ),
          SwitchListTile(
            title: const Text('显示老师'),
            value: ui.showTeacher,
            onChanged: (v) => apply(ui.copyWith(showTeacher: v)),
          ),
          SwitchListTile(
            title: const Text('显示备注'),
            subtitle: const Text('备注以小字显示在卡片上'),
            value: ui.showNote,
            onChanged: (v) => apply(ui.copyWith(showNote: v)),
          ),
          const _Header('课程配色'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DropdownButtonFormField<String>(
              key: ValueKey('scheme_${ui.colorSchemeId}'),
              initialValue: ui.colorSchemeId,
              decoration: const InputDecoration(
                labelText: '课程配色',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final scheme in kCourseColorSchemes)
                  DropdownMenuItem(
                    value: scheme.id,
                    child: Row(
                      children: [
                        _ColorStrip(colors: scheme.colors),
                        const SizedBox(width: 10),
                        Text(scheme.name),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) apply(ui.copyWith(colorSchemeId: v));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: Text(
                  '顺带应用推荐主题色「${themePresetById(ui.colorScheme.recommendedThemeId).name}」',
                ),
                onPressed: () => apply(
                  ui.copyWith(
                    themePresetId: ui.colorScheme.recommendedThemeId,
                    clearThemeCustomColor: true,
                  ),
                ),
              ),
            ),
          ),
          const _Header('主题颜色'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in kThemePresets)
                  _ThemeChip(
                    name: preset.name,
                    color: Color(preset.seed),
                    selected:
                        ui.themeCustomColor == null &&
                        ui.themePresetId == preset.id,
                    onTap: () => apply(
                      ui.copyWith(
                        themePresetId: preset.id,
                        clearThemeCustomColor: true,
                      ),
                    ),
                  ),
                _ThemeChip(
                  name: '自定义',
                  color: ui.themeCustomColor != null
                      ? Color(ui.themeCustomColor!)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  selected: ui.themeCustomColor != null,
                  isCustom: true,
                  onTap: () async {
                    final picked = await showDialog<Color>(
                      context: context,
                      builder: (_) =>
                          _HsvPickerDialog(initial: Color(ui.themeSeedValue)),
                    );
                    if (picked != null) {
                      apply(ui.copyWith(themeCustomColor: picked.toARGB32()));
                    }
                  },
                ),
              ],
            ),
          ),
          if (ui.themeCustomColor != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () =>
                      apply(ui.copyWith(clearThemeCustomColor: true)),
                  child: const Text('清除自定义，回到预置主题色'),
                ),
              ),
            ),
          _FontSection(ui: ui, apply: apply),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          SizedBox(width: 108, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(valueText, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// 方案色带：前 6 个颜色的小色块（设置页里一眼看全方案气质）
class _ColorStrip extends StatelessWidget {
  const _ColorStrip({required this.colors});

  final List<int> colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colors.take(6))
          Container(
            width: 13,
            height: 22,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: Color(c),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// 主题色圆点选项（预置与自定义共用）
class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: isCustom
                  ? const Icon(Icons.colorize, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(name),
          ],
        ),
      ),
    );
  }
}

/// 自定义主题色取色器：HSV 三滑杆 + 实时预览（无第三方依赖）
class _HsvPickerDialog extends StatefulWidget {
  const _HsvPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_HsvPickerDialog> createState() => _HsvPickerDialogState();
}

class _HsvPickerDialogState extends State<_HsvPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: const Text('自定义主题色'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _hsvSlider(
            '色相',
            _hsv.hue,
            360,
            (v) => setState(() => _hsv = _hsv.withHue(v)),
          ),
          _hsvSlider(
            '饱和',
            _hsv.saturation,
            1,
            (v) => setState(() => _hsv = _hsv.withSaturation(v)),
          ),
          _hsvSlider(
            '明度',
            _hsv.value,
            1,
            (v) => setState(() => _hsv = _hsv.withValue(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget _hsvSlider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 实时预览（1.2.0 改 1:1）：从真实课表「截一角」出来渲染——
/// 格高 = 真实格高、列宽 =（屏宽 − 节次栏宽）÷ 主页当前列数、
/// 表头高/节次栏宽/字号全部与主界面同一套常量和组件，
/// 所见即所得，不再有缩放比例差。
class _Preview extends StatelessWidget {
  const _Preview({
    required this.ui,
    required this.columnCount,
    required this.slots,
  });

  final UiSettings ui;

  /// 主页当前实际显示的列数（与主页同源计算），决定真实列宽
  final int columnCount;

  /// 真实作息（节次栏时间文案与主页一致）
  final List<TimeSlot> slots;

  static final _sampleA = Course(
    semesterId: 0,
    name: '药理学',
    teacher: '周老师',
    classroom: '教3-201',
    colorValue: MorandiPalette.colors[3],
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    weeks: const [1],
    note: '带实验报告',
  );
  static final _sampleB = Course(
    semesterId: 0,
    name: '有机化学',
    teacher: '李老师',
    classroom: '实验楼402',
    colorValue: MorandiPalette.colors[8],
    dayOfWeek: 2,
    startSection: 2,
    endSection: 3,
    weeks: const [1],
  );

  static const _rows = 3;
  static const _showCols = 3;
  static const _sampleDays = [('一', '7'), ('二', '8'), ('三', '9')];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    // 与主页完全相同的列宽公式（主页网格占满屏宽）
    final colW = (screenW - kTimeAxisWidth) / columnCount;
    final rowH = ui.cellHeight;
    final contentW = kTimeAxisWidth + colW * _showCols;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
          color: scheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        // 窄屏时从右侧裁切，如同透过窗口看真实课表的一角
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: contentW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 表头：与主页同高、同字号（月份 + 星期/日期）
                Container(
                  height: kGridHeaderHeight,
                  color: scheme.surfaceContainerLow,
                  child: Row(
                    children: [
                      SizedBox(
                        width: kTimeAxisWidth,
                        child: Center(
                          child: Text(
                            '9月',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ),
                      for (final d in _sampleDays)
                        SizedBox(
                          width: colW,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                d.$1,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.outline,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Center(
                                  child: Text(
                                    d.$2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: rowH * _rows,
                  child: Row(
                    children: [
                      // 节次栏：与主页同宽、同字号（节次 12 号、时间 8 号）
                      SizedBox(
                        width: kTimeAxisWidth,
                        child: Column(
                          children: [
                            for (var i = 0; i < _rows; i++)
                              SizedBox(
                                height: rowH,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (ui.axisShowTime &&
                                        slots.length > i) ...[
                                      Text(
                                        slots[i].startTime,
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: scheme.outline,
                                        ),
                                      ),
                                      Text(
                                        slots[i].endTime,
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: scheme.outline,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 网格 + 示例卡片（卡片内边距与主页同为 1.5）
                      SizedBox(
                        width: colW * _showCols,
                        child: Stack(
                          children: [
                            if (ui.showGridLines)
                              CustomPaint(
                                size: Size(colW * _showCols, rowH * _rows),
                                painter: _PreviewGridPainter(
                                  colW: colW,
                                  rowH: rowH,
                                  rows: _rows,
                                  cols: _showCols,
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            _previewCard(_sampleA, 0, 0, 2, colW, rowH),
                            _previewCard(_sampleB, 1, 1, 2, colW, rowH),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewCard(
    Course course,
    int col,
    int row,
    int span,
    double colW,
    double rowH,
  ) {
    const pad = 1.5;
    return Positioned(
      left: col * colW + pad,
      top: row * rowH + pad,
      width: colW - pad * 2,
      height: span * rowH - pad * 2,
      child: CourseCard(
        course: course,
        onTap: () {},
        onLongPress: () {},
        displayColorValue: mapCourseColor(course.colorValue, ui.colorScheme),
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

class _PreviewGridPainter extends CustomPainter {
  _PreviewGridPainter({
    required this.colW,
    required this.rowH,
    required this.rows,
    required this.cols,
    required this.color,
  });

  final double colW;
  final double rowH;
  final int rows;
  final int cols;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * rowH), Offset(size.width, r * rowH), paint);
    }
    for (var c = 1; c < cols; c++) {
      canvas.drawLine(
        Offset(c * colW, 0),
        Offset(c * colW, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewGridPainter old) =>
      old.colW != colW ||
      old.rowH != rowH ||
      old.cols != cols ||
      old.color != color;
}

/// 显示字体区（1.2.1）：内置五款单选 + 用户导入字体（列表/导入/删除）。
/// 导入字体的注册表在 FontsService（静态），本组件用本地状态触发重建。
class _FontSection extends StatefulWidget {
  const _FontSection({required this.ui, required this.apply});

  final UiSettings ui;
  final void Function(UiSettings next) apply;

  @override
  State<_FontSection> createState() => _FontSectionState();
}

class _FontSectionState extends State<_FontSection> {
  bool _importing = false;

  Future<void> _importFont() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
    );
    if (picked.isEmpty || !mounted) return;
    final path = picked.first.path;
    if (path == null) return;
    final baseName = path.split('/').last;
    final name = baseName.replaceAll(
      RegExp(r'\.(ttf|otf)$', caseSensitive: false),
      '',
    );
    setState(() => _importing = true);
    try {
      final font = await FontsService.importFont(
        File(path),
        name.isEmpty ? '导入字体' : name,
      );
      widget.apply(widget.ui.copyWith(fontId: font.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入并应用「${font.name}」')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败：这个文件不是有效的字体文件（仅支持 TTF / OTF）')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeFont(ImportedFont font) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除导入字体'),
        content: Text('确定删除「${font.name}」吗？删除后使用该字体的设置会回到系统默认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FontsService.removeFont(font);
    if (widget.ui.fontId == font.id) {
      widget.apply(widget.ui.copyWith(fontId: 'system'));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    final imported = FontsService.fonts;
    final selectedImported = imported
        .where((f) => f.id == ui.fontId)
        .firstOrNull;
    const builtins = [
      (id: 'system', name: '系统默认', family: null),
      (id: 'lxgw', name: '霞鹜文楷', family: 'LXGWWenKai'),
      (id: 'zcool', name: '站酷快乐体', family: 'ZCOOLKuaiLe'),
      (id: 'smiley', name: '得意黑', family: 'SmileySans'),
      (id: 'noto', name: '思源黑体', family: 'NotoSansSC'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header('显示字体'),
        // 当前字体预览（下拉项本身也各自用自己的字体渲染）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            '小马课表 · 药理学',
            style: TextStyle(
              fontSize: 17,
              fontFamily: FontsService.resolveFamily(ui),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String>(
            key: ValueKey('font_${ui.fontId}'),
            initialValue: ui.fontId,
            decoration: const InputDecoration(
              labelText: '显示字体',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in builtins)
                DropdownMenuItem(
                  value: f.id,
                  child: Text(f.name, style: TextStyle(fontFamily: f.family)),
                ),
              for (final f in imported)
                DropdownMenuItem(
                  value: f.id,
                  child: Text(
                    '${f.name}（导入）',
                    style: TextStyle(fontFamily: f.family),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) widget.apply(ui.copyWith(fontId: v));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('导入字体文件'),
                onPressed: _importing ? null : _importFont,
              ),
              if (selectedImported != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除所选字体'),
                  onPressed: () => _removeFont(selectedImported),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '从手机里选 TTF / OTF 字体，导入后立即全 App 生效',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
