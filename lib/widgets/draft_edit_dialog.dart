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
) {
  return showDialog<Course>(
    context: context,
    builder: (ctx) => _DraftEditDialog(draft: draft),
  );
}

/// S3-2：独立持有 4 个 TextEditingController，在 dispose() 中统一释放，
/// 避免退场动画期间误释放；S4-1：课程名错误拆出独立的 _nameError 挂在
/// 课程名输入框上，输入变化时自动清空对应错误提示。
class _DraftEditDialog extends ConsumerStatefulWidget {
  const _DraftEditDialog({required this.draft});

  final Course draft;

  @override
  ConsumerState<_DraftEditDialog> createState() => _DraftEditDialogState();
}

class _DraftEditDialogState extends ConsumerState<_DraftEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _teacherController;
  late final TextEditingController _classroomController;
  late final TextEditingController _weeksController;

  late int _dayOfWeek;
  late int _startSection;
  late int _endSection;
  String? _nameError;
  String? _weekError;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _nameController = TextEditingController(text: d.name);
    _teacherController = TextEditingController(text: d.teacher ?? '');
    _classroomController = TextEditingController(text: d.classroom ?? '');
    _weeksController = TextEditingController(
      text: WeekParser.toText(d.weeks, d.weekType),
    );
    _dayOfWeek = d.dayOfWeek;
    _startSection = d.startSection;
    _endSection = d.endSection;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _classroomController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(timeSlotsProvider).value ?? const [];
    // 作息还没读出来时按内置默认 13 节兜底（与 DB 种子一致）
    final sectionSlots = slots.isNotEmpty
        ? slots
        : [
            for (var s = 1; s <= 13; s++)
              TimeSlot(section: s, startTime: '', endTime: ''),
          ];
    final seg = ref.watch(segmentSettingsProvider).value;

    // WB_SPEC_230 第 4.2 节第 5 类：只换外层壳，表单逻辑与
    // SingleChildScrollView 全部不动
    return AppDialog(
      title: '编辑导入课程',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: '课程名 *',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _teacherController,
              decoration: const InputDecoration(labelText: '老师'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _classroomController,
              decoration: const InputDecoration(labelText: '教室'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppSelectField<int>(
                    labelText: '星期',
                    value: _dayOfWeek,
                    options: buildWeekdayOptions(),
                    // 抽屉要从 Dialog 之上弹出，否则会被 Dialog 裁剪
                    useRootNavigator: true,
                    onChanged: (v) => setState(() => _dayOfWeek = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSelectField<int>(
                    labelText: '开始节次',
                    value: _startSection,
                    options: buildSectionOptions(
                      slots: sectionSlots,
                      seg: seg,
                    ),
                    useRootNavigator: true,
                    onChanged: (v) => setState(() {
                      _startSection = v;
                      if (_endSection < _startSection) {
                        _endSection = _startSection;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppSelectField<int>(
                    labelText: '结束节次',
                    value: _endSection,
                    options: buildSectionOptions(
                      slots: sectionSlots,
                      seg: seg,
                      minSection: _startSection,
                    ),
                    useRootNavigator: true,
                    onChanged: (v) => setState(() {
                      _endSection = v;
                      if (_startSection > _endSection) {
                        _startSection = _endSection;
                      }
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _weeksController,
              decoration: InputDecoration(
                labelText: '周次（如 1-16 或 1-8,10-16单周）',
                errorText: _weekError,
              ),
              onChanged: (_) {
                if (_weekError != null) setState(() => _weekError = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        // WB_SPEC_235 跟进 §1-15 / §4：弹窗按钮走标准 action 构造
        AppDialogAction(
          label: '取消',
          onPressed: () => Navigator.pop(context),
        ),
        AppDialogAction(
          label: '确定',
          primary: true,
          // 草稿改动落库前的一步确认（保存语义）→ 中档
          haptic: AppDialogHaptic.medium,
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              setState(() => _nameError = '课程名不能为空');
              return;
            }
            List<int> weeks;
            int weekType;
            try {
              final parsed = WeekParser.parse(_weeksController.text);
              weeks = parsed.weeks;
              weekType = parsed.weekType;
            } on WeekParseException catch (e) {
              setState(() => _weekError = e.message);
              return;
            }
            Navigator.pop(
              context,
              widget.draft.copyWith(
                name: name,
                teacher: _teacherController.text.trim().isEmpty
                    ? null
                    : _teacherController.text.trim(),
                classroom: _classroomController.text.trim().isEmpty
                    ? null
                    : _classroomController.text.trim(),
                dayOfWeek: _dayOfWeek,
                startSection: _startSection,
                endSection: _endSection,
                weeks: weeks,
                weekType: weekType,
              ),
            );
          },
        ),
      ],
    );
  }
}
