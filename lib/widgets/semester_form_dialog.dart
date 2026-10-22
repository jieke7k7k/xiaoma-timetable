import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/semester.dart';
import '../utils/week_calc.dart';
import 'semester_start_dialog.dart';

/// 弹出学期表单；确认返回填好的学期，取消返回 null。
/// 学期管理页与导入页（选目标学期时当场新建）共用。
///
/// 传 [initial] 即进入编辑模式：回填该学期的名称 / 开学日期 / 总周数，
/// 返回时保留原 id 与 isCurrent；不传就是原来的新建模式（返回无 id 的学期）。
Future<Semester?> showSemesterFormDialog(
  BuildContext context, {
  Semester? initial,
}) {
  return showDialog<Semester>(
    context: context,
    builder: (ctx) => SemesterFormDialog(initial: initial),
  );
}

/// 学期表单校验（新建与编辑共用同一套，不要另写一份）。
///
/// 通过返回 null，否则返回中文提示文案，调用方直接拿去弹 SnackBar。
/// 抽成纯函数是为了可单测（页面里的对话框不好测）。
String? validateSemesterForm({
  required String name,
  required String weeks,
}) {
  if (name.trim().isEmpty) return '请填写学期名称';
  final v = int.tryParse(weeks.trim());
  if (v == null || v < 1 || v > 30) return '请输入 1~30 之间的周数';
  return null;
}

/// 学期表单对话框（新建 / 编辑共用）
class SemesterFormDialog extends ConsumerStatefulWidget {
  const SemesterFormDialog({this.initial});

  /// 非 null 即编辑模式：回填该学期并在返回时保留 id / isCurrent
  final Semester? initial;

  @override
  ConsumerState<SemesterFormDialog> createState() =>
      SemesterFormDialogState();
}

class SemesterFormDialogState extends ConsumerState<SemesterFormDialog> {
  final _nameController = TextEditingController();
  final _weeksController = TextEditingController(text: '20');
  DateTime? _startDate;

  /// 编辑中的原学期（新建为 null）
  Semester? get _initial => widget.initial;

  @override
  void initState() {
    super.initState();
    final initial = _initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _weeksController.text = '${initial.totalWeeks}';
      // 库里的开学日期恒为周一；脏数据（未对齐）也在回填时就归一化
      _startDate = WeekCalc.alignToMonday(initial.startDateParsed);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择开学日期',
    );
    if (picked == null) return;
    // 与全局约定一致：开学日期自动对齐到所在周的周一
    setState(() => _startDate = WeekCalc.alignToMonday(picked));
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final weeksText = _weeksController.text.trim();
    final error = validateSemesterForm(name: name, weeks: weeksText);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final weeks = int.parse(weeksText);
    // 默认开学日期：今天对齐到周一（用户没选就给一个合理初值）
    final start = WeekCalc.alignToMonday(_startDate ?? DateTime.now());
    // 1.2.1：落库前强制过目确认开学日期（错一位全表周次错位），弹窗内可改。
    // 编辑模式下只有真的换了日期才弹——只改名/改周数不该反复打扰。
    DateTime confirmed = start;
    final initial = _initial;
    if (initial == null || DateFormat('yyyy-MM-dd').format(start) != initial.startDate) {
      final res = await showSemesterStartConfirmDialog(
        context,
        semesterName: name,
        initialStart: start,
        totalWeeks: weeks,
      );
      if (res == null || !mounted) return;
      confirmed = res;
    }
    final iso = DateFormat('yyyy-MM-dd').format(confirmed);
    Navigator.pop(
      context,
      // 编辑模式保留 id 与 isCurrent（落库按 id 更新同一行）
      initial == null
          ? Semester(
              name: name,
              startDate: iso,
              totalWeeks: weeks,
            )
          : initial.copyWith(
              name: name,
              startDate: iso,
              totalWeeks: weeks,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = _initial != null;
    final dateText = _startDate == null
        ? '默认从本周开始'
        : '${DateFormat('yyyy-MM-dd').format(_startDate!)}（周一）';
    return AlertDialog(
      title: Text(editing ? '编辑学期' : '新建学期'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '学期名称',
              hintText: '如：大三下学期',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('开学日期'),
            subtitle: Text(dateText),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
          TextField(
            controller: _weeksController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '总周数',
              suffixText: '周',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: _submit, child: Text(editing ? '保存' : '创建')),
      ],
    );
  }
}
