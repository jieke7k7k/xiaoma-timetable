import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/utils/conflict_detector.dart';

Course _course({
  int? id,
  String name = '课程',
  int dayOfWeek = 1,
  int startSection = 1,
  int endSection = 2,
  List<int> weeks = const [1, 2, 3, 4, 5],
}) =>
    Course(
      id: id,
      semesterId: 1,
      name: name,
      colorValue: 0xFF000000,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
    );

void main() {
  group('ConflictDetector.detect', () {
    test('无冲突：不同星期', () {
      final a = _course(dayOfWeek: 1, startSection: 1, endSection: 2);
      final b = _course(dayOfWeek: 2, startSection: 1, endSection: 2);
      expect(ConflictDetector.detect(a, [b]), isEmpty);
    });

    test('无冲突：同星期但节次不重合', () {
      final a = _course(startSection: 1, endSection: 2);
      final b = _course(startSection: 3, endSection: 4);
      expect(ConflictDetector.detect(a, [b]), isEmpty);
    });

    test('无冲突：同星期同节次但周次不重合', () {
      final a = _course(weeks: [1, 2, 3]);
      final b = _course(weeks: [4, 5, 6]);
      expect(ConflictDetector.detect(a, [b]), isEmpty);
    });

    test('冲突：同星期+周次重合+节次重合', () {
      final a = _course(name: '药物分析', startSection: 1, endSection: 2);
      final b = _course(name: '药理学', startSection: 2, endSection: 3);
      final conflicts = ConflictDetector.detect(a, [b]);
      expect(conflicts, isNotEmpty);
      expect(conflicts.first.overlapSections, [2]); // 只在第 2 节重合
    });

    test('冲突：完全重叠的两节课', () {
      final a = _course(name: 'A', startSection: 3, endSection: 4);
      final b = _course(name: 'B', startSection: 3, endSection: 4);
      final conflicts = ConflictDetector.detect(a, [b]);
      expect(conflicts.length, 1);
      expect(conflicts.first.overlapSections, [3, 4]);
      expect(conflicts.first.overlapWeeks, [1, 2, 3, 4, 5]);
    });

    test('忽略自身 id（编辑场景不与自己冲突）', () {
      final a = _course(id: 10, startSection: 1, endSection: 2);
      final conflicts = ConflictDetector.detect(a, [a], ignoreCourseId: 10);
      expect(conflicts, isEmpty);
    });

    test('批量导入：与多门课冲突返回多条', () {
      final candidate = _course(startSection: 1, endSection: 2, weeks: [1, 2, 3, 4, 5]);
      final existing = [
        _course(name: 'B', startSection: 1, endSection: 1, weeks: [1, 2, 3, 4, 5]),
        _course(name: 'C', startSection: 2, endSection: 2, weeks: [1, 2, 3, 4, 5]),
      ];
      final conflicts = ConflictDetector.detect(candidate, existing);
      expect(conflicts.length, 2);
    });

    test('手动改课：候选课与同学期已有课冲突，且排除自身', () {
      // 编辑《药理学》时把它挪到与另一门课重叠的时段：池子里既有它自己
      // （原时段，与候选值重叠）也有《药物分析》，只应检出与《药物分析》的一处
      final candidate = _course(
        id: 10,
        name: '药理学',
        startSection: 3,
        endSection: 4,
      );
      final existing = [
        _course(id: 10, name: '药理学', startSection: 3, endSection: 4),
        _course(id: 11, name: '药物分析', startSection: 3, endSection: 4),
      ];
      final conflicts =
          ConflictDetector.detect(candidate, existing, ignoreCourseId: 10);
      expect(conflicts.length, 1);
      expect(conflicts.first.courseB.name, '药物分析');
    });

    test('手动建课：周次仅在端点相交也算冲突（与导入链路同一套语义）', () {
      final candidate =
          _course(startSection: 1, endSection: 2, weeks: [1, 2, 3, 4, 5, 6, 7, 8]);
      final existing = [_course(name: 'B', weeks: [8, 9, 10])];
      final conflicts = ConflictDetector.detect(candidate, existing);
      expect(conflicts.length, 1);
      expect(conflicts.first.overlapWeeks, [8]);
    });

    test('describe 描述包含课程名与周次节次', () {
      final a = _course(name: '药物分析', startSection: 3, endSection: 4);
      final b = _course(name: '药理学', startSection: 3, endSection: 4);
      final conflicts = ConflictDetector.detect(a, [b]);
      final desc = conflicts.first.describe();
      expect(desc, contains('药物分析'));
      expect(desc, contains('药理学'));
      expect(desc, contains('第 3-4 节'));
    });

    test('describe 描述包含星期几', () {
      final a = _course(name: 'A', dayOfWeek: 1, startSection: 3, endSection: 4);
      final b = _course(name: 'B', dayOfWeek: 1, startSection: 3, endSection: 4);
      final desc = ConflictDetector.detect(a, [b]).first.describe();
      expect(desc, contains('周一'));
      final c = _course(name: 'C', dayOfWeek: 5, startSection: 1, endSection: 2);
      final d = _course(name: 'D', dayOfWeek: 5, startSection: 1, endSection: 2);
      expect(ConflictDetector.detect(c, [d]).first.describe(), contains('周五'));
    });
  });
}
