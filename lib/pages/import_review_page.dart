import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../utils/conflict_detector.dart';
import '../utils/ics_parser.dart';
import '../utils/morandi_palette.dart';
import '../utils/slot_calibrator.dart';
import '../utils/week_parser.dart';
import '../widgets/conflict_dialog.dart';
import '../widgets/draft_edit_dialog.dart';
import '../widgets/empty_state.dart';

/// 导入人工核对页
///
/// 展示导入解析出的草稿课程，逐条可编辑字段、删除误识别项、手动补录漏识别项。
/// 点击「确认导入」经过冲突检测后才正式写入数据库。
class ImportReviewPage extends ConsumerStatefulWidget {
  const ImportReviewPage({
    super.key,
    required this.drafts,
    this.timeBlocks = const [],
  });

  final List<Course> drafts;

  /// ICS 导入解析出的作息校准块；图片/PDF 等路径不传、保持空列表
  final List<IcsTimeBlock> timeBlocks;

  @override
  ConsumerState<ImportReviewPage> createState() => _ImportReviewPageState();
}

class _ImportReviewPageState extends ConsumerState<ImportReviewPage> {
  late final List<Course> _drafts;
  bool _importing = false;
  // 导入完成后允许直接返回，不再弹「放弃核对」确认
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _drafts = List.of(widget.drafts);
  }

  void _editDraft(int index) async {
    final edited = await showDraftEditDialog(context, _drafts[index]);
    if (edited != null && mounted) {
      setState(() => _drafts[index] = edited);
    }
  }

  void _removeDraft(int index) {
    setState(() => _drafts.removeAt(index));
  }

  Future<void> _addDraft() async {
    // 手动补录默认填满整学期周次：空周次会导致课程永久不显示且无报错
    final totalWeeks = ref.read(currentSemesterProvider).value?.totalWeeks ?? 20;
    final blank = Course(
      semesterId: 0,
      name: '新课程',
      colorValue: MorandiPalette.defaultColor,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: List.generate(totalWeeks, (i) => i + 1),
    );
    final edited = await showDraftEditDialog(context, blank);
    if (edited != null && mounted) {
      setState(() => _drafts.add(edited));
    }
  }

  Future<void> _importAll() async {
    if (_drafts.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可导入的课程')));
      return;
    }
    // 空周次拦截：周次为空的课程入库后永不显示，必须先补
    for (var i = 0; i < _drafts.length; i++) {
      if (_drafts[i].weeks.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '第 ${i + 1} 门课《${_drafts[i].name}》未设置上课周次，请点击卡片补充后再导入'),
        ));
        return;
      }
    }
    setState(() => _importing = true);
    try {
      final dao = Dao.instance;
      final semester = ref.read(currentSemesterProvider).value!;
      final existing = await dao.getCoursesBySemester(semester.id!);

      var imported = 0;
      var skipped = 0;
      var overwritten = 0;

      for (final draft in _drafts) {
        final conflicts = ConflictDetector.detect(draft, existing);
        var shouldImport = true;
        // 覆盖的旧课先收集，等该草稿全部冲突确认且决定导入后再统一删除，
        // 避免中途选了跳过时前面已删的旧课无法恢复
        final toDelete = <Course>[];

        for (final conflict in conflicts) {
          if (!mounted) return;
          final resolution = await showConflictDialog(context, conflict);
          if (resolution == null || resolution == ConflictResolution.skip) {
            shouldImport = false;
            skipped++;
            break;
          }
          if (resolution == ConflictResolution.overwrite) {
            toDelete.add(conflict.courseB);
          }
          // keepBoth：不做特殊处理，继续导入
        }

        if (shouldImport) {
          for (final old in toDelete) {
            if (old.id != null) {
              await dao.deleteCourse(old.id!);
              existing.removeWhere((c) => c.id == old.id);
              overwritten++;
            }
          }
          final newId =
              await dao.insertCourse(draft.copyWith(semesterId: semester.id!));
          // 同步加入内存，让同批后续草稿能与这门刚入库的课冲突检测
          existing.add(draft.copyWith(id: newId, semesterId: semester.id!));
          imported++;
        }
      }

      // 刷新 provider 让周视图同步
      await ref.read(coursesProvider.notifier).reload();

      // 课程全部导入成功后，按课表文件校准作息时间。
      // 校准失败（异常）不回滚已导入的课程，仅静默记录日志。
      var calibrated = false;
      if (widget.timeBlocks.isNotEmpty) {
        try {
          final currentSlots = ref.read(timeSlotsProvider).value ?? const [];
          final newSlots =
              SlotCalibrator.calibrate(currentSlots, widget.timeBlocks);
          final notifier = ref.read(timeSlotsProvider.notifier);
          for (final ns in newSlots) {
            // 校准可能扩出原作息没有的新节次（如第 13 节），找不到旧值时直接新增
            TimeSlot? old;
            for (final s in currentSlots) {
              if (s.section == ns.section) {
                old = s;
                break;
              }
            }
            if (old == null ||
                old.startTime != ns.startTime ||
                old.endTime != ns.endTime) {
              await notifier.updateSlot(ns);
            }
          }
          calibrated = true;
        } catch (e) {
          debugPrint('作息时间校准失败：$e');
        }
      }

      if (mounted) {
        _done = true; // 导入完成，直接返回不再弹确认
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('导入完成：新增 $imported 门，覆盖 $overwritten 门，跳过 $skipped 门'),
        ));
        if (calibrated) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已按课表文件校准作息时间')));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 防误触返回：草稿非空时先弹窗确认，避免辛苦核对的成果被一次滑动丢掉
    return PopScope(
      canPop: _drafts.isEmpty || _done,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('放弃本次导入？'),
            content: const Text('确定放弃本次导入核对吗？草稿不会被保存。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续核对')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('放弃')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _done = true;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('核对导入结果（${_drafts.length} 门）'),
        ),
      body: _drafts.isEmpty
          // 统一空状态占位（阶段五·视觉打磨）：图标 + 文案 + 手动补录入口
          ? EmptyState(
              icon: Icons.inbox_outlined,
              title: '没有解析出课程',
              message: '可以手动补录，或返回重新导入',
              actionLabel: '手动补录',
              onAction: _addDraft,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _drafts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final draft = _drafts[index];
                return _DraftCard(
                  course: draft,
                  onTap: () => _editDraft(index),
                  onDelete: () => _removeDraft(index),
                );
              },
            ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importing ? null : _addDraft,
                    icon: const Icon(Icons.add),
                    label: const Text('手动补录'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _importing ? null : _importAll,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_importing ? '导入中…' : '确认导入'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.course,
    required this.onTap,
    required this.onDelete,
  });

  final Course course;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static const _weekNames = ['', '一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Container(
          width: 14,
          height: 42,
          decoration: BoxDecoration(
            color: Color(course.colorValue),
            // 色条是微小装饰元素，4px 微圆角不便归入 AppRadii 体系
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(course.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '周${_weekNames[course.dayOfWeek]} 第${course.startSection}'
          '${course.endSection > course.startSection ? "-${course.endSection}" : ""}节'
          ' · ${course.classroom?.isNotEmpty == true ? course.classroom : "未填教室"}'
          ' · ${course.weeks.isEmpty ? "周次未设置" : WeekParser.toText(course.weeks, course.weekType)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: '删除此条',
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}
