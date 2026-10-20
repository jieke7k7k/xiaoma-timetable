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

  void _toggleWeek(int week) {
    // 点选周次方块的触感反馈
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(week)) {
        _selected.remove(week);
      } else {
        _selected.add(week);
      }
    });
    _emit();
  }

  void _quickSelect(String action) {
    // 快捷按钮的触感反馈
    HapticFeedback.selectionClick();
    setState(() {
      final total = ref.read(currentSemesterProvider).value?.totalWeeks ?? 20;
      switch (action) {
        case 'all':
          _selected = List.generate(total, (i) => i + 1).toSet();
          _weekType = WeekParser.allWeeks;
          break;
        case 'odd':
          // 单双周语义直接落到周次选择，不设全局 weekType
          _selected = List.generate(total, (i) => i + 1)
              .where((w) => w.isOdd)
              .toSet();
          _weekType = WeekParser.allWeeks;
          break;
        case 'even':
          _selected = List.generate(total, (i) => i + 1)
              .where((w) => w.isEven)
              .toSet();
          _weekType = WeekParser.allWeeks;
          break;
        case 'clear':
          _selected = {};
          _weekType = WeekParser.allWeeks;
          break;
      }
      _textController.text = WeekParser.toText(_selected.toList(), _weekType);
      _parseError = null;
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
    required this.onTap,
  });

  final int week;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 34,
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
      ),
    );
  }
}
