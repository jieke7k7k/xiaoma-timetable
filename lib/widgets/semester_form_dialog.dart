import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/semester.dart';
import '../utils/week_calc.dart';

/// 弹出新建学期表单；确认返回填好的学期（无 id），取消返回 null。
/// 学期管理页与导入页（选目标学期时当场新建）共用。
Future<Semester?> showSemesterFormDialog(BuildContext context) {
  return showDialog<Semester>(
    context: context,
    builder: (ctx) => const SemesterFormDialog(),
  );
}

/// 新建学期表单对话框
class SemesterFormDialog extends ConsumerStatefulWidget {
  const SemesterFormDialog();

  @override
  ConsumerState<SemesterFormDialog> createState() =>
      SemesterFormDialogState();
}

class SemesterFormDialogState extends ConsumerState<SemesterFormDialog> {
  final _nameController = TextEditingController();
  final _weeksController = TextEditingController(text: '20');
  DateTime? _startDate;

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

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写学期名称')));
      return;
    }
    final weeks = int.tryParse(_weeksController.text.trim());
    if (weeks == null || weeks < 1 || weeks > 30) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入 1~30 之间的周数')));
      return;
    }
    // 默认开学日期：今天对齐到周一（用户没选就给一个合理初值）
    final start =
        WeekCalc.alignToMonday(_startDate ?? DateTime.now());
    Navigator.pop(
      context,
      Semester(
        name: name,
        startDate: DateFormat('yyyy-MM-dd').format(start),
        totalWeeks: weeks,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _startDate == null
        ? '默认从本周开始'
        : '${DateFormat('yyyy-MM-dd').format(_startDate!)}（周一）';
    return AlertDialog(
      title: const Text('新建学期'),
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
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
