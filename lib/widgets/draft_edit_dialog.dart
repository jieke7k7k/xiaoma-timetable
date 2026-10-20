import 'package:flutter/material.dart';

import '../models/course.dart';
import '../utils/week_parser.dart';

/// 草稿课程编辑对话框（人工核对页内使用）
///
/// 编辑导入草稿的关键字段：名称/老师/教室/星期/节次/周次文本。
/// 返回编辑后的 [Course]；取消返回 null。
Future<Course?> showDraftEditDialog(
  BuildContext context,
  Course draft, {
  int maxSections = 12,
}) async {
  final nameController = TextEditingController(text: draft.name);
  final teacherController = TextEditingController(text: draft.teacher ?? '');
  final classroomController =
      TextEditingController(text: draft.classroom ?? '');
  final weeksController = TextEditingController(
      text: WeekParser.toText(draft.weeks, draft.weekType));
  var dayOfWeek = draft.dayOfWeek;
  var startSection = draft.startSection;
  var endSection = draft.endSection;
  String? weekError;

  final result = await showDialog<Course>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        return AlertDialog(
          title: const Text('编辑导入课程'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '课程名 *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: teacherController,
                  decoration: const InputDecoration(labelText: '老师'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: classroomController,
                  decoration: const InputDecoration(labelText: '教室'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: dayOfWeek,
                        decoration: const InputDecoration(labelText: '星期'),
                        items: [
                          for (var d = 1; d <= 7; d++)
                            DropdownMenuItem(
                                value: d,
                                child: Text('周${'一二三四五六日'[d - 1]}')),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => dayOfWeek = v ?? dayOfWeek),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: startSection,
                        decoration: const InputDecoration(labelText: '开始节次'),
                        items: [
                          for (var s = 1; s <= maxSections; s++)
                            DropdownMenuItem(value: s, child: Text('$s')),
                        ],
                        onChanged: (v) => setDialogState(() {
                          startSection = v ?? startSection;
                          if (endSection < startSection) {
                            endSection = startSection;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: endSection,
                        decoration: const InputDecoration(labelText: '结束节次'),
                        items: [
                          for (var s = 1; s <= maxSections; s++)
                            DropdownMenuItem(value: s, child: Text('$s')),
                        ],
                        onChanged: (v) => setDialogState(() {
                          endSection = v ?? endSection;
                          if (startSection > endSection) {
                            startSection = endSection;
                          }
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weeksController,
                  decoration: InputDecoration(
                    labelText: '周次（如 1-16 或 1-8,10-16单周）',
                    errorText: weekError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => weekError = '课程名不能为空');
                  return;
                }
                List<int> weeks;
                int weekType;
                try {
                  final parsed = WeekParser.parse(weeksController.text);
                  weeks = parsed.weeks;
                  weekType = parsed.weekType;
                } on WeekParseException catch (e) {
                  setDialogState(() => weekError = e.message);
                  return;
                }
                Navigator.pop(
                  ctx,
                  draft.copyWith(
                    name: name,
                    teacher: teacherController.text.trim().isEmpty
                        ? null
                        : teacherController.text.trim(),
                    classroom: classroomController.text.trim().isEmpty
                        ? null
                        : classroomController.text.trim(),
                    dayOfWeek: dayOfWeek,
                    startSection: startSection,
                    endSection: endSection,
                    weeks: weeks,
                    weekType: weekType,
                  ),
                );
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    ),
  );
  return result;
}
