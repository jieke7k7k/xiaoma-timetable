import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../ui/app_select_field.dart';
import '../utils/week_parser.dart';
import 'app_dialog.dart';

/// 草稿课程编辑对话框（人工核对页内使用）
///
/// 编辑导入草稿的关键字段：名称/老师/教室/星期/节次/周次文本。
/// 返回编辑后的 [Course]；取消返回 null。
///
/// WB_SPEC_232 第 5.3 节：三个下拉换成统一选择框（同编辑页同一套选项构造器），
/// 节次上限不再写死 12，改为跟 `timeSlotsProvider` 的实际节次数（DB 默认 13 节）
/// ——旧的 12 上限是 latent bug：作息是 13 节时第 13 节在弹窗里选不到。
Future<Course?> showDraftEditDialog(
  BuildContext context,
  Course draft,
) async {
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
    builder: (ctx) => Consumer(
      // Consumer 只为读作息/分段点；表单状态仍由下面的 StatefulBuilder 管
      builder: (ctx, ref, _) {
        final slots = ref.watch(timeSlotsProvider).value ?? const <TimeSlot>[];
        // 作息还没读出来时按内置默认 13 节兜底（与 DB 种子一致）
        final sectionSlots = slots.isNotEmpty
            ? slots
            : [
                for (var s = 1; s <= 13; s++)
                  TimeSlot(section: s, startTime: '', endTime: ''),
              ];
        final seg = ref.watch(segmentSettingsProvider).value;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // WB_SPEC_230 第 4.2 节第 5 类：只换外层壳，表单逻辑与
            // SingleChildScrollView 全部不动
            return AppDialog(
              title: '编辑导入课程',
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
                          child: AppSelectField<int>(
                            labelText: '星期',
                            value: dayOfWeek,
                            options: buildWeekdayOptions(),
                            // 抽屉要从 Dialog 之上弹出，否则会被 Dialog 裁剪
                            useRootNavigator: true,
                            onChanged: (v) =>
                                setDialogState(() => dayOfWeek = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppSelectField<int>(
                            labelText: '开始节次',
                            value: startSection,
                            options: buildSectionOptions(
                              slots: sectionSlots,
                              seg: seg,
                            ),
                            useRootNavigator: true,
                            onChanged: (v) => setDialogState(() {
                              startSection = v;
                              if (endSection < startSection) {
                                endSection = startSection;
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppSelectField<int>(
                            labelText: '结束节次',
                            value: endSection,
                            options: buildSectionOptions(
                              slots: sectionSlots,
                              seg: seg,
                              minSection: startSection,
                            ),
                            useRootNavigator: true,
                            onChanged: (v) => setDialogState(() {
                              endSection = v;
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
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
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
        );
      },
    ),
  );
  return result;
}
