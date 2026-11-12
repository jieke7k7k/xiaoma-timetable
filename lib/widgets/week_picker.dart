import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/week_parser.dart';

/// 周次选择器（阶段二重点组件）
///
/// 两种方式选周次：
/// 1. 可视化网格点选：1~N 周按钮 +「全选 / 单周 / 双周」快捷按钮
/// 2. 文本解析：输入「1-8, 10-16单周」这类简写，解析成周次数组
///
/// 外部通过 [weeks] / [weekType] 读写选择结果，解析失败时内联红字提示。
class WeekPicker extends ConsumerStatefulWidget {
  const WeekPicker({
    super.key,
    required this.initialWeeks,
    required this.initialWeekType,
    required this.onChanged,
  });

  final List<int> initialWeeks;
  final int initialWeekType;
  final void Function(List<int> weeks, int weekType) onChanged;

  @override
  ConsumerState<WeekPicker> createState() => _WeekPickerState();
}

class _WeekPickerState extends ConsumerState<WeekPicker> {
  late Set<int> _selected;
  late int _weekType;
  late TextEditingController _textController;
  String? _parseError;

  /// 待配对起点（WB_SPEC_232 第 3.1 节）：非空表示「上一颗点中的芯片正等着
  /// 配对成区间」，此时再点另一颗就把 min..max 一次连选。null = 待命。
  int? _anchorWeek;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialWeeks.toSet();
    _weekType = widget.initialWeekType;
    _textController =
        TextEditingController(text: WeekParser.toText(_selected.toList(), _weekType));
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_selected.toList()..sort(), _weekType);
  }

  /// 芯片 / 快捷按钮改动后把结果同步进周次文本框（与 [_quickSelect] 同一口径），
  /// 顺带清掉上一次解析失败的红字
  void _syncText() {
    _textController.text =
        WeekParser.toText(_selected.toList()..sort(), _weekType);
    _parseError = null;
  }

  /// 点一颗周次芯片：三态——立锚点 / 连成区间 / 取消已选
  ///
  /// 连选两段不连续区间互不干扰：点 1 → 点 6（连好 1–6，锚点清空）→ 再点 9
  /// （定新锚点）→ 点 14（连好 9–14），第 3 下不会冲掉前面选好的。
  void _toggleWeek(int week) {
    // 点选周次方块的触感反馈
    HapticFeedback.selectionClick();
    final anchor = _anchorWeek;
    setState(() {
      if (_selected.contains(week)) {
        // 点已选的芯片 = 单独取消这一颗（例：连选 1–16 后第 5 周放假，点 5 只掉 5）
        _selected.remove(week);
        _anchorWeek = null;
      } else if (anchor == null) {
        _selected.add(week);
        _anchorWeek = week;
      } else {
        final start = anchor < week ? anchor : week;
        final end = anchor < week ? week : anchor;
        for (var w = start; w <= end; w++) {
          _selected.add(w);
        }
        _anchorWeek = null;
      }
      _syncText();
    });
    _emit();
  }

  /// 单周 / 双周在「已有局部区间」时只过滤区间内部（WB_SPEC_232 第 3.2 节）：
  /// 已选 3–14 点单周 → 3,5,7,9,11,13；空选 / 全选 / 已是纯单双周时走全局切换。
  Set<int> _oddEvenWithinSelection(
    int total, {
    required bool odd,
  }) {
    final all = List.generate(total, (i) => i + 1);
    final pureOdd = _selected.every((w) => w.isOdd);
    final pureEven = _selected.every((w) => w.isEven);
    final isFull = _selected.length >= all.length;
    // 非空真子集、且还不是纯单/双周 → 只过滤当前选中的那些周次
    final localized = _selected.isNotEmpty && !isFull && !pureOdd && !pureEven;
    final base = localized ? _selected : all;
    return {
      for (final w in base)
        if (odd ? w.isOdd : w.isEven) w,
    };
  }

  void _quickSelect(String action) {
    // 快捷按钮的触感反馈
    HapticFeedback.selectionClick();
    setState(() {
      final total = ref.read(currentSemesterProvider).value?.totalWeeks ?? 20;
      // 任何快捷按钮都是「重新给出一份选择」，待配对起点一律清空
      _anchorWeek = null;
      switch (action) {
        case 'all':
          _selected = List.generate(total, (i) => i + 1).toSet();
          _weekType = WeekParser.allWeeks;
          break;
        case 'odd':
          // 单双周语义直接落到周次选择，不设全局 weekType
          _selected = _oddEvenWithinSelection(total, odd: true);
          _weekType = WeekParser.allWeeks;
          break;
        case 'even':
          _selected = _oddEvenWithinSelection(total, odd: false);
          _weekType = WeekParser.allWeeks;
          break;
        case 'clear':
          _selected = {};
          _weekType = WeekParser.allWeeks;
          break;
      }
      _syncText();
    });
    _emit();
  }

  void _parseText() {
    try {
      final result = WeekParser.parse(_textController.text);
      setState(() {
        _selected = result.weeks.toSet();
        _weekType = result.weekType;
        _parseError = null;
        // 文本解析重写了整份选择，旧锚点已无意义
        _anchorWeek = null;
      });
      _emit();
    } on WeekParseException catch (e) {
      setState(() => _parseError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(currentSemesterProvider).value;
    final totalWeeks = semester?.totalWeeks ?? 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 快捷按钮
        Wrap(
          spacing: 8,
          children: [
            _QuickButton(
                label: '全选', onTap: () => _quickSelect('all')),
            _QuickButton(
                label: '单周', onTap: () => _quickSelect('odd')),
            _QuickButton(
                label: '双周', onTap: () => _quickSelect('even')),
            _QuickButton(
                label: '清空', onTap: () => _quickSelect('clear')),
          ],
        ),
        const SizedBox(height: 12),
        // 可视化周次点选网格（每行 7 个）
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var w = 1; w <= totalWeeks; w++)
              _WeekButton(
                week: w,
                selected: _selected.contains(w),
                anchor: _anchorWeek == w,
                onTap: () => _toggleWeek(w),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // 文本解析
        TextField(
          controller: _textController,
          decoration: InputDecoration(
            labelText: '周次文本（可选）',
            hintText: '如 1-8, 10-16单周',
            errorText: _parseError,
            suffixIcon: IconButton(
              icon: const Icon(Icons.auto_fix_high),
              tooltip: '解析文本',
              onPressed: _parseText,
            ),
          ),
          onSubmitted: (_) => _parseText(),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(17)),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _WeekButton extends StatelessWidget {
  const _WeekButton({
    required this.week,
    required this.selected,
    required this.anchor,
    required this.onTap,
  });

  final int week;
  final bool selected;

  /// 待配对起点（WB_SPEC_232 第 3.1 节）：已选外观之外再加一圈 1.5dp 外圈描边
  final bool anchor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 已选/未选外观完全沿用改前（231 定版的 chip 外观，不改成实心主色）
    final chip = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        // 周次方块是 chip 级小元素，圆角统一取全局常量
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: Border.all(
          color: selected
              ? colorScheme.primary
              : colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        '$week',
        style: TextStyle(
          fontSize: 13,
          color: selected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return GestureDetector(
      key: ValueKey('week-chip-$week'),
      onTap: onTap,
      // 外层尺寸恒为 38×34、Wrap 间距恒为 6：锚点外圈画在盒子内部（内缩 1.5dp），
      // 不用 padding/margin 撑大，整行布局不会被顶歪
      child: SizedBox(
        width: 38,
        height: 34,
        child: anchor
            ? Container(
                key: ValueKey('week-anchor-$week'),
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  // 外圈半径比内芯大 1.5，两圈同心
                  borderRadius:
                      BorderRadius.circular(AppRadii.chip + 1.5),
                  border: Border.all(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                child: chip,
              )
            : chip,
      ),
    );
  }
}
