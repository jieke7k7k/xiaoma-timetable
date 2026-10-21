import '../models/course.dart';
import 'conflict_detector.dart';

/// 导入冲突批量处理计划（1.2.0）
///
/// 取代旧版「逐条弹窗」：先一次性预检全部冲突，用户在清单页统一决策
/// （可单条选、可一键全部同选），再由本计划器生成确定性的执行计划，
/// 页面只负责照计划落库。全程纯函数，可单测。

/// 一处待处理冲突：下标为 [draftIndex] 的草稿与「池子」里的一门课冲突。
///
/// 池子 = 目标学期已有课程 + 排在其前面的草稿（按导入顺序累积）。
/// 契约：调用方只能把**目标学期**的课程作为 existing 传入——
/// 冲突检测范围严格等于传入的池子，跨学期课程永远不会出现在池子里。
class ImportConflictItem {
  const ImportConflictItem({
    required this.draftIndex,
    required this.conflict,
    required this.otherIsDraft,
    required this.otherDraftIndex,
  });

  /// 冲突的新课（草稿）下标
  final int draftIndex;

  /// 冲突详情（courseA = 草稿，courseB = 池子里的对方）
  final CourseConflict conflict;

  /// 对方是本批另一条草稿（true）还是目标学期已有课程（false）
  final bool otherIsDraft;

  /// 对方是草稿时它的下标；对方是已有课程时为 -1（按 courseB.id 定位）
  final int otherDraftIndex;
}

/// 一条草稿的执行计划
class PlannedImport {
  const PlannedImport({
    required this.draftIndex,
    required this.shouldImport,
    required this.deleteExistingIds,
    required this.deleteDraftIndexes,
  });

  final int draftIndex;

  /// 是否入库（任一冲突被选「跳过」则整条跳过）
  final bool shouldImport;

  /// 「覆盖」要删除的目标学期已有课程 id
  final List<int> deleteExistingIds;

  /// 「覆盖」要删除的本批草稿下标（执行时映射到它们入库后的新 id；
  /// 对方草稿若最终被跳过、没入库，该标记自动落空）
  final List<int> deleteDraftIndexes;
}

class ImportPlanner {
  ImportPlanner._();

  /// 预检：按顺序把每条草稿与池子比对，收集全部冲突。
  static List<ImportConflictItem> preScan(
      List<Course> drafts, List<Course> existing) {
    final items = <ImportConflictItem>[];
    final pool = <Course>[...existing];
    // 与 pool 平行：已有课程记 -1，草稿记其下标
    final poolDraftIndex = <int>[for (var i = 0; i < existing.length; i++) -1];
    for (var d = 0; d < drafts.length; d++) {
      final conflicts = ConflictDetector.detect(drafts[d], pool);
      for (final c in conflicts) {
        var otherDraftIndex = -1;
        for (var k = 0; k < pool.length; k++) {
          if (identical(pool[k], c.courseB)) {
            otherDraftIndex = poolDraftIndex[k];
            break;
          }
        }
        items.add(ImportConflictItem(
          draftIndex: d,
          conflict: c,
          otherIsDraft: otherDraftIndex >= 0,
          otherDraftIndex: otherDraftIndex,
        ));
      }
      pool.add(drafts[d]);
      poolDraftIndex.add(d);
    }
    return items;
  }

  /// 按用户对每处冲突的选择（与 [items] 等长同序）生成执行计划。
  static List<PlannedImport> buildPlan(
    List<Course> drafts,
    List<ImportConflictItem> items,
    List<ConflictResolution> choices,
  ) {
    assert(items.length == choices.length);
    final byDraft = <int, List<int>>{};
    for (var i = 0; i < items.length; i++) {
      byDraft.putIfAbsent(items[i].draftIndex, () => []).add(i);
    }
    final plans = <PlannedImport>[];
    for (var d = 0; d < drafts.length; d++) {
      var skip = false;
      final delIds = <int>{};
      final delDrafts = <int>{};
      for (final i in byDraft[d] ?? const <int>[]) {
        switch (choices[i]) {
          case ConflictResolution.skip:
            skip = true;
          case ConflictResolution.overwrite:
            final item = items[i];
            if (item.otherIsDraft) {
              delDrafts.add(item.otherDraftIndex);
            } else if (item.conflict.courseB.id != null) {
              delIds.add(item.conflict.courseB.id!);
            }
          case ConflictResolution.keepBoth:
            break;
        }
      }
      plans.add(PlannedImport(
        draftIndex: d,
        shouldImport: !skip,
        // 跳过的草稿不带任何删除动作：计划自洽，执行端无需再判一次
        deleteExistingIds: skip ? const [] : delIds.toList(),
        deleteDraftIndexes: skip ? const [] : delDrafts.toList(),
      ));
    }
    return plans;
  }
}
