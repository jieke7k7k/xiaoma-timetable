import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/utils/conflict_detector.dart';
import 'package:xiaoma_timetable/utils/import_planner.dart';

/// 导入冲突批量计划（1.2.0）：预检范围、批量决策与执行计划
///
/// 最重要的一条是跨学期回归：池子只装目标学期的课程时，
/// 另一个学期排了完全相同的课，往空的新学期导入必须零冲突。
void main() {
  Course mk({
    int? id,
    int semesterId = 1,
    String name = '课',
    int day = 1,
    int start = 1,
    int end = 2,
    List<int> weeks = const [1, 2, 3],
  }) =>
      Course(
        id: id,
        semesterId: semesterId,
        name: name,
        colorValue: 0xFF000000,
        dayOfWeek: day,
        startSection: start,
        endSection: end,
        weeks: weeks,
      );

  group('预检范围', () {
    test('跨学期回归：目标学期为空时零冲突，哪怕别的学期有完全相同的课', () {
      // 旧学期（id=1）已有一门一模一样的课；导入目标是新学期（id=2，空）
      final otherSemesterCourses = [mk(id: 10, semesterId: 1, name: '药理学')];
      final drafts = [mk(semesterId: 0, name: '药理学')];
      // 页面契约：只把目标学期的课程传进池子（这里目标学期为空）
      final targetExisting = otherSemesterCourses
          .where((c) => c.semesterId == 2)
          .toList();
      expect(targetExisting, isEmpty);
      final items = ImportPlanner.preScan(drafts, targetExisting);
      expect(items, isEmpty, reason: '别的学期的课程绝不能产生冲突');
      // 对照组：检测器本身没坏——同池传入时确实能检出冲突
      final control = ImportPlanner.preScan(drafts, otherSemesterCourses);
      expect(control.length, 1);
    });

    test('与目标学期已有课程同时间 → 冲突，对方标记为已有课程', () {
      final existing = [mk(id: 7, name: '有机化学')];
      final items = ImportPlanner.preScan([mk(name: '药理学')], existing);
      expect(items.length, 1);
      expect(items.single.otherIsDraft, isFalse);
      expect(items.single.conflict.courseB.id, 7);
    });

    test('本批草稿之间冲突 → 对方标记为本批草稿并带下标', () {
      final drafts = [mk(name: 'A'), mk(name: 'B')];
      final items = ImportPlanner.preScan(drafts, const []);
      expect(items.length, 1);
      expect(items.single.draftIndex, 1);
      expect(items.single.otherIsDraft, isTrue);
      expect(items.single.otherDraftIndex, 0);
    });

    test('时间不重合不误报：不同星期/不重合周次均无冲突', () {
      final existing = [mk(id: 1, day: 2), mk(id: 2, weeks: const [5, 6])];
      final items = ImportPlanner.preScan([mk()], existing);
      expect(items, isEmpty);
    });
  });

  group('执行计划', () {
    test('任一冲突选跳过 → 整条草稿跳过，且不产生删除', () {
      final existing = [mk(id: 7), mk(id: 8, start: 2, end: 3)];
      final drafts = [mk(start: 1, end: 3)];
      final items = ImportPlanner.preScan(drafts, existing);
      expect(items.length, 2);
      final plan = ImportPlanner.buildPlan(drafts, items, [
        ConflictResolution.overwrite,
        ConflictResolution.skip,
      ]);
      expect(plan.single.shouldImport, isFalse);
      expect(plan.single.deleteExistingIds, isEmpty);
    });

    test('覆盖已有课程 → 删除清单含其 id', () {
      final existing = [mk(id: 7)];
      final drafts = [mk()];
      final items = ImportPlanner.preScan(drafts, existing);
      final plan = ImportPlanner.buildPlan(
          drafts, items, [ConflictResolution.overwrite]);
      expect(plan.single.shouldImport, isTrue);
      expect(plan.single.deleteExistingIds, [7]);
    });

    test('覆盖本批草稿 → 删除清单含对方草稿下标', () {
      final drafts = [mk(name: 'A'), mk(name: 'B')];
      final items = ImportPlanner.preScan(drafts, const []);
      final plan = ImportPlanner.buildPlan(
          drafts, items, [ConflictResolution.overwrite]);
      expect(plan[1].shouldImport, isTrue);
      expect(plan[1].deleteDraftIndexes, [0]);
      expect(plan[0].shouldImport, isTrue);
    });

    test('保留两者 → 导入且不删任何课', () {
      final existing = [mk(id: 7)];
      final drafts = [mk()];
      final items = ImportPlanner.preScan(drafts, existing);
      final plan = ImportPlanner.buildPlan(
          drafts, items, [ConflictResolution.keepBoth]);
      expect(plan.single.shouldImport, isTrue);
      expect(plan.single.deleteExistingIds, isEmpty);
      expect(plan.single.deleteDraftIndexes, isEmpty);
    });

    test('无冲突时全部草稿都计划导入（十几门批量场景）', () {
      final drafts = [
        for (var i = 0; i < 15; i++) mk(name: '课$i', day: (i % 7) + 1, start: 1 + (i ~/ 7) * 2, end: 2 + (i ~/ 7) * 2),
      ];
      final items = ImportPlanner.preScan(drafts, const []);
      expect(items, isEmpty);
      final plan = ImportPlanner.buildPlan(drafts, items, const []);
      expect(plan.length, 15);
      expect(plan.every((p) => p.shouldImport), isTrue);
    });
  });
}
