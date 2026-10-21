import 'package:flutter/material.dart';

/// 开学日期确认弹窗（1.2.1）
///
/// 开学日期错一位，全表周次全错。新学期创建与课程导入两个入口共用：
/// 大字展示开学日期与第 1 周范围，「改日期」在弹窗内换日期（自动对齐周一），
/// 「确认无误」返回最终日期，用户取消返回 null。
/// 调用方负责把返回的日期落库/用于建学期。
Future<DateTime?> showSemesterStartConfirmDialog(
  BuildContext context, {
  required String semesterName,
  required DateTime initialStart,
  required int totalWeeks,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _StartConfirmDialog(
      semesterName: semesterName,
      initialStart: initialStart,
      totalWeeks: totalWeeks,
    ),
  );
}

class _StartConfirmDialog extends StatefulWidget {
  const _StartConfirmDialog({
    required this.semesterName,
    required this.initialStart,
    required this.totalWeeks,
  });

  final String semesterName;
  final DateTime initialStart;
  final int totalWeeks;

  @override
  State<_StartConfirmDialog> createState() => _StartConfirmDialogState();
}

class _StartConfirmDialogState extends State<_StartConfirmDialog> {
  late DateTime _date = DateTime(
      widget.initialStart.year, widget.initialStart.month, widget.initialStart.day);

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  String _fmt(DateTime d) => '${d.year}年${d.month}月${d.day}日';
  String _fmtShort(DateTime d) => '${d.month}月${d.day}日';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择开学日期（自动对齐到周一）',
    );
    if (picked == null) return;
    // 与全 App 口径一致：开学日对齐到所在周的周一
    final monday = picked.subtract(Duration(days: picked.weekday - 1));
    setState(() => _date = DateTime(monday.year, monday.month, monday.day));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weekEnd = _date.add(const Duration(days: 6));
    return AlertDialog(
      title: const Text('确认开学日期'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('学期：${widget.semesterName}',
              style: TextStyle(color: scheme.outline)),
          const SizedBox(height: 10),
          Text(
            _fmt(_date),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '星期${_weekdayNames[_date.weekday - 1]}开学 · '
            '第 1 周：${_fmtShort(_date)} – ${_fmtShort(weekEnd)} · '
            '全学期共 ${widget.totalWeeks} 周',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Text(
            '所有课程的周次都按这个日期推算，错一位全表错位，请核对无误。',
            style: TextStyle(fontSize: 12, color: scheme.error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _pickDate, child: const Text('改日期')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _date),
          child: const Text('确认无误'),
        ),
      ],
    );
  }
}
