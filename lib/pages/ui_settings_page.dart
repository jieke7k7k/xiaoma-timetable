import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../utils/color_schemes.dart';
import '../utils/morandi_palette.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('界面设置'), centerTitle: true),
      body: ListView(
        children: [
          const _Header('实时预览'),
          _Preview(ui: ui),
          const _Header('格子外观'),
          _SliderRow(
            label: '课程格子高度',
            valueText: '${ui.cellHeight.round()} px',
            value: ui.cellHeight,
            min: 44,
            max: 96,
            divisions: 26,
            onChanged: (v) => apply(ui.copyWith(cellHeight: v)),
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
          SwitchListTile(
            title: const Text('格子加粗边框'),
            subtitle: const Text('边框取格子颜色的加深版'),
            value: ui.boldBorder,
            onChanged: (v) => apply(ui.copyWith(boldBorder: v)),
          ),
          SwitchListTile(
            title: const Text('节数栏显示时间'),
            subtitle: const Text('关掉后左侧只显示节次数字'),
            value: ui.axisShowTime,
            onChanged: (v) => apply(ui.copyWith(axisShowTime: v)),
          ),
          const _Header('卡片显示'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                const Expanded(child: Text('卡片文字大小')),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('小')),
                    ButtonSegment(value: 1, label: Text('中')),
                    ButtonSegment(value: 2, label: Text('大')),
                  ],
                  selected: {ui.cardTextSize},
                  onSelectionChanged: (s) =>
                      apply(ui.copyWith(cardTextSize: s.first)),
                ),
              ],
            ),
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
          for (final scheme in kCourseColorSchemes)
            ListTile(
              leading: _ColorStrip(colors: scheme.colors),
              title: Text(scheme.name),
              trailing: ui.colorSchemeId == scheme.id
                  ? Icon(Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () => apply(ui.copyWith(colorSchemeId: scheme.id)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: Text(
                    '顺带应用推荐主题色「${themePresetById(ui.colorScheme.recommendedThemeId).name}」'),
                onPressed: () => apply(ui.copyWith(
                  themePresetId: ui.colorScheme.recommendedThemeId,
                  clearThemeCustomColor: true,
                )),
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
                    selected: ui.themeCustomColor == null &&
                        ui.themePresetId == preset.id,
                    onTap: () => apply(ui.copyWith(
                      themePresetId: preset.id,
                      clearThemeCustomColor: true,
                    )),
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
                      builder: (_) => _HsvPickerDialog(
                        initial: Color(ui.themeSeedValue),
                      ),
                    );
                    if (picked != null) {
                      apply(ui.copyWith(
                          themeCustomColor: picked.toARGB32()));
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
          const _Header('显示字体'),
          for (final font in const [
            (id: 'system', name: '系统默认', family: null),
            (id: 'lxgw', name: '霞鹜文楷', family: 'LXGWWenKai'),
            (id: 'zcool', name: '站酷快乐体', family: 'ZCOOLKuaiLe'),
          ])
            ListTile(
              leading: Icon(
                ui.fontId == font.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: ui.fontId == font.id
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(
                '小马课表 · 药理学',
                style: TextStyle(fontFamily: font.family, fontSize: 16),
              ),
              subtitle: Text(font.name),
              onTap: () => apply(ui.copyWith(fontId: font.id)),
            ),
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
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          _hsvSlider('色相', _hsv.hue, 360,
              (v) => setState(() => _hsv = _hsv.withHue(v))),
          _hsvSlider('饱和', _hsv.saturation, 1,
              (v) => setState(() => _hsv = _hsv.withSaturation(v))),
          _hsvSlider('明度', _hsv.value, 1,
              (v) => setState(() => _hsv = _hsv.withValue(v))),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, color),
            child: const Text('应用')),
      ],
    );
  }

  Widget _hsvSlider(
      String label, double value, double max, ValueChanged<double> onChanged) {
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

/// 实时预览：3 列 × 4 节的迷你课表，全部参数与真实课表共用同一套渲染
/// （CourseCard + 当前界面设置），调什么样就长什么样。
class _Preview extends StatelessWidget {
  const _Preview({required this.ui});

  final UiSettings ui;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 预览按 0.62 比例缩放格高，避免设置页被预览占满
    final rowH = ui.cellHeight * 0.62;
    const rows = 4;
    const axisW = 34.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
          color: scheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // 预览表头
            Container(
              height: 26,
              color: scheme.surfaceContainerLow,
              child: Row(
                children: [
                  const SizedBox(
                    width: axisW,
                    child: Center(
                        child: Text('10月', style: TextStyle(fontSize: 9))),
                  ),
                  for (final d in const ['一', '二', '三'])
                    Expanded(
                      child: Center(
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 10, color: scheme.outline)),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: rowH * rows,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridW = constraints.maxWidth - axisW;
                  final colW = gridW / 3;
                  return Row(
                    children: [
                      // 节数栏
                      SizedBox(
                        width: axisW,
                        child: Column(
                          children: [
                            for (var i = 1; i <= rows; i++)
                              SizedBox(
                                height: rowH,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('$i',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600)),
                                    if (ui.axisShowTime)
                                      Text(
                                        i.isOdd ? '08:00' : '08:50',
                                        style: TextStyle(
                                            fontSize: 7,
                                            color: scheme.outline),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 网格 + 示例卡片
                      Expanded(
                        child: Stack(
                          children: [
                            if (ui.showGridLines)
                              CustomPaint(
                                size: Size(gridW, rowH * rows),
                                painter: _PreviewGridPainter(
                                  colW: colW,
                                  rowH: rowH,
                                  rows: rows,
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            _previewCard(_sampleA, 0, 0, 2, colW, rowH),
                            _previewCard(_sampleB, 1, 1, 2, colW, rowH),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(
      Course course, int col, int row, int span, double colW, double rowH) {
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
        boldBorder: ui.boldBorder,
        textSizeLevel: ui.cardTextSize,
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
    required this.color,
  });

  final double colW;
  final double rowH;
  final int rows;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * rowH), Offset(size.width, r * rowH), paint);
    }
    for (var c = 1; c < 3; c++) {
      canvas.drawLine(Offset(c * colW, 0), Offset(c * colW, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_PreviewGridPainter old) =>
      old.colW != colW || old.rowH != rowH || old.color != color;
}
