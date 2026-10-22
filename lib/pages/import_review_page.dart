import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../ui/app_styles.dart';
import '../utils/conflict_detector.dart';
import '../utils/ics_parser.dart';
import '../utils/import_planner.dart';
import '../utils/morandi_palette.dart';
import '../utils/slot_calibrator.dart';
import '../utils/week_infer.dart';
import '../utils/week_parser.dart';
import '../widgets/draft_edit_dialog.dart';
import '../widgets/empty_state.dart';
import 'import_conflicts_page.dart';

/// 导入人工核对页
///
/// 展示导入解析出的草稿课程，逐条可编辑字段、删除误识别项、手动补录漏识别项。
/// 目标学期由导入页显式传入（[targetSemester]），页头横幅明示去向；
/// 点击「确认导入」先用 [ImportPlanner] 全量预检冲突——有冲突进批量清单页
/// 统一决策（1.2.0 起取代逐条弹窗），无冲突直接按计划写入数据库。
class ImportReviewPage extends ConsumerStatefulWidget {
  const ImportReviewPage({
    super.key,
    required this.drafts,
    required this.targetSemester,
    this.timeBlocks = const [],
  });

  final List<Course> drafts;

  /// 本次导入的目标学期：冲突检测与入库都严格限定在它之内
  final Semester targetSemester;

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
  // 周次超出学期总周数时，是否顺手把总周数扩到推断值（默认勾选）
  bool _extendTotalWeeks = true;

  /// 草稿最晚周次超过目标学期总周数时，建议调整到的总周数；否则 null（不展示任何提示）
  ///
  /// 钳到 1~30（2.0.0 复审 C7）：与学期表单校验、[Semester.fromMap] 同一区间。
  /// 提示条里写的数就是保存时写进库的数，不会出现「说好改成 40 周、结果 30 周」。
  int? get _inferredTotalWeeks {
    final inferred = WeekInfer.inferredTotalWeeks(
      _drafts,
      widget.targetSemester.totalWeeks,
    );
    if (inferred == null) return null;
    return inferred.clamp(1, 30);
  }

  /// 数据变更后的三项联动（提醒重排 / 备注常驻通知 / 桌面小部件）。
  ///
  /// 与 providers 里 `_notifyDataChanged` 同一口径，多补一条备注通知（那份是给
  /// 课程类变更用的，不含备注通知）。导入一次可能落几十门课，提醒计划、常驻
  /// 通知、小部件都得重算；三个服务各自读库且内部已捕获异常，fire-and-forget
  /// 不阻塞完成弹窗。
  void _notifyDataChanged() {
    unawaited(NotificationService.instance.rescheduleAll());
    unawaited(NotificationService.instance.refreshNoteNotice());
    unawaited(WidgetService.instance.refreshWidgets());
  }

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
    // 手动补录默认填满目标学期总周次：空周次会导致课程永久不显示且无报错
    final totalWeeks = widget.targetSemester.totalWeeks;
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
      final target = widget.targetSemester;
      // 冲突池严格限定目标学期：其它学期的课程永远不会进来（跨学期误报的根源修复）
      final existing = await dao.getCoursesBySemester(target.id!);

      // 全量预检冲突；有冲突先进批量清单页统一决策，不再逐条弹窗
      final items = ImportPlanner.preScan(_drafts, existing);
      var choices = List<ConflictResolution>.filled(
          items.length, ConflictResolution.keepBoth);
      if (items.isNotEmpty) {
        if (!mounted) return;
        final result = await Navigator.push<List<ConflictResolution>>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ImportConflictsPage(drafts: _drafts, items: items),
          ),
        );
        if (result == null) {
          // 用户在清单页返回 = 取消本次导入，停留在核对页
          if (mounted) setState(() => _importing = false);
          return;
        }
        choices = result;
      }

      // 照计划落库：删除覆盖对象 → 插入保留的草稿（盖上目标学期 id）。
      // 整段包进一个事务（1.3.1）：旧课逐条删除与新课逐条插入要么全成功、
      // 要么整体回滚，中途失败不会留下「旧课已删、新课没进」的半批数据。
      final plan = ImportPlanner.buildPlan(_drafts, items, choices);
      final insertedIds = <int, int>{};
      final result = await dao.runInTransaction((txn) async {
        var imported = 0;
        var skipped = 0;
        var overwritten = 0;
        for (final p in plan) {
          if (!p.shouldImport) {
            skipped++;
            continue;
          }
          for (final id in p.deleteExistingIds) {
            await dao.deleteCourse(id, txn: txn);
            overwritten++;
          }
          for (final di in p.deleteDraftIndexes) {
            final nid = insertedIds[di];
            if (nid != null) {
              await dao.deleteCourse(nid, txn: txn);
              overwritten++;
            }
          }
          final newId = await dao.insertCourse(
            _drafts[p.draftIndex].copyWith(semesterId: target.id!),
            txn: txn,
          );
          insertedIds[p.draftIndex] = newId;
          imported++;
        }
        return (imported: imported, skipped: skipped, overwritten: overwritten);
      });
      final imported = result.imported;
      final skipped = result.skipped;
      final overwritten = result.overwritten;

      // 刷新 provider 让周视图同步
      await ref.read(coursesProvider.notifier).reload();
      // 课程整批换过了：提醒计划 / 常驻通知 / 小部件都要按新数据重算
      _notifyDataChanged();

      // 周次溢出：导入的课最晚周次超过学期总周数时，按用户勾选把总周数补齐。
      // 放在落库成功之后——课程已安全入库，这里失败也不回滚（与作息校准同一策略）。
      var extendedTo = 0;
      // 钳到 1~30（C7）：写进库的与提示条上写的必须是同一个数
      final inferred = WeekInfer.maxWeek(_drafts).clamp(1, 30);
      if (_extendTotalWeeks && target.id != null && inferred > target.totalWeeks) {
        try {
          final updated = target.copyWith(totalWeeks: inferred);
          // 走学期管理页「编辑学期」的同一个入口（2.0.0 复审 C2）：改库 → 当前
          // 学期同步内存 state → 刷学期列表 → 浏览周按新总周数钳制 → 三联动。
          // 本页不再自己拼这一串，免得日后一边加了联动另一边忘了
          await ref.read(semestersProvider.notifier).updateSemester(updated);
          extendedTo = updated.totalWeeks;
          // 再补一次备注通知（providers 那份三联动不含备注通知）
          _notifyDataChanged();
        } catch (e) {
          debugPrint('调整学期总周数失败：$e');
        }
      }

      // 课程全部导入成功后，按课表文件校准作息时间。
      // 校准失败（异常）不回滚已导入的课程，仅静默记录日志。
      // 1.2.0：校准差异逐条记下，随完成弹窗一起给用户看，不再只有一句笼统提示。
      final calibrationDiffs = <String>[];
      if (widget.timeBlocks.isNotEmpty) {
        try {
          final currentSlots = ref.read(timeSlotsProvider).value ?? const [];
          final newSlots =
              SlotCalibrator.calibrate(currentSlots, widget.timeBlocks);
          final notifier = ref.read(timeSlotsProvider.notifier);
          for (final ns in newSlots) {
            TimeSlot? old;
            for (final s in currentSlots) {
              if (s.section == ns.section) {
                old = s;
                break;
              }
            }
            if (old == null) {
              calibrationDiffs
                  .add('新增第 ${ns.section} 节 ${ns.startTime}–${ns.endTime}');
              await notifier.updateSlot(ns);
            } else if (old.startTime != ns.startTime ||
                old.endTime != ns.endTime) {
              calibrationDiffs.add('第 ${ns.section} 节 '
                  '${old.startTime}–${old.endTime} → ${ns.startTime}–${ns.endTime}');
              await notifier.updateSlot(ns);
            }
          }
        } catch (e) {
          debugPrint('作息时间校准失败：$e');
          calibrationDiffs.clear();
        }
      }

      if (mounted) {
        _done = true; // 导入完成，弹窗关闭后直接返回，不再弹「放弃核对」
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导入完成'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已导入到《${target.name}》：\n'
                      '新增 $imported 门，覆盖 $overwritten 门，跳过 $skipped 门'),
                  if (extendedTo > 0) ...[
                    const SizedBox(height: 8),
                    Text('《${target.name}》的总周数已调整为 $extendedTo 周'
                        '（原 ${target.totalWeeks} 周）'),
                  ],
                  if (calibrationDiffs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('作息已按课表文件校准：',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    for (final d in calibrationDiffs) Text('· $d'),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('好的')),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  /// 周次溢出提示条：草稿最晚周次超过目标学期总周数时才出现，
  /// 勾选后随「确认导入」一起把学期总周数扩到 [inferred] 周；
  /// 不勾选则原样保存，学期总周数不动
  Widget _weekOverflowBanner(BuildContext context, int inferred) {
    final total = widget.targetSemester.totalWeeks;
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.l,
        vertical: AppSpacing.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '导入的课程最晚到第 $inferred 周，超过当前学期的总周数 $total 周',
            style: const TextStyle(fontSize: 13),
          ),
          InkWell(
            onTap: () => setState(() => _extendTotalWeeks = !_extendTotalWeeks),
            child: Row(
              children: [
                Checkbox(
                  value: _extendTotalWeeks,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) =>
                      setState(() => _extendTotalWeeks = v ?? false),
                ),
                Expanded(
                  child: Text(
                    '保存时把总周数调整为 $inferred 周',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 防误触返回：草稿非空时先弹窗确认，避免辛苦核对的成果被一次滑动丢掉
    final inferred = _inferredTotalWeeks;
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
        body: Column(
          children: [
            // 目标学期横幅：导入去向全程可见，导错学期当场能发现
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '导入到《${widget.targetSemester.name}》 · '
                '开学 ${widget.targetSemester.startDate} · '
                '共 ${widget.targetSemester.totalWeeks} 周',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            // 周次溢出提示：不改动任何数据，只在用户勾选时随保存一起生效
            if (inferred != null) _weekOverflowBanner(context, inferred),
            Expanded(
              child: _drafts.isEmpty
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
            ),
          ],
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
