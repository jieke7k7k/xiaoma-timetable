import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/utils/same_name_weeks.dart';

Course _c({
  int? id,
  String name = '实验室',
  int dayOfWeek = 3,
  int startSection = 6,
  int endSection = 9,
  required List<int> weeks,
  int weekType = 0,
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
      weekType: weekType,
    );

void main() {
  test('实验室四条例子：检出一组不一致，目标为 2–21 周', () {
    final courses = [
      _c(id: 1, dayOfWeek: 3, startSection: 6, weeks: List.generate(20, (i) => i + 2)),
      _c(id: 2, dayOfWeek: 6, startSection: 6, weeks: List.generate(20, (i) => i + 2)),
      _c(id: 3, dayOfWeek: 5, startSection: 10, weeks: List.generate(19, (i) => i + 2)),
      _c(id: 4, dayOfWeek: 6, startSection: 10, weeks: List.generate(18, (i) => i + 2)),
    ];
    final groups = findInconsistentWeekGroups(courses);
    expect(groups.length, 1);
    expect(groups.first.name, '实验室');
    expect(groups.first.targetWeeks, List.generate(20, (i) => i + 2));
    expect(groups.first.distinctWeeks.length, 3);
  });

  test('全一致的组不检出', () {
    final courses = [
      _c(id: 1, weeks: [1, 2, 3]),
      _c(id: 2, dayOfWeek: 5, weeks: [3, 2, 1]),
    ];
    expect(findInconsistentWeekGroups(courses), isEmpty);
  });

  test('单条同名不检出', () {
    final courses = [_c(id: 1, weeks: [1, 2, 3])];
    expect(findInconsistentWeekGroups(courses), isEmpty);
  });

  test('空 weeks 不参与分组', () {
    final courses = [
      _c(id: 1, weeks: []),
      _c(id: 2, weeks: [1, 2, 3]),
    ];
    expect(findInconsistentWeekGroups(courses), isEmpty);
  });

  test('目标选择并列规则：等长时取出现最多的', () {
    final courses = [
      _c(id: 1, dayOfWeek: 1, startSection: 1, weeks: [1, 2, 3]),
      _c(id: 2, dayOfWeek: 2, startSection: 1, weeks: [1, 2, 3]),
      _c(id: 3, dayOfWeek: 3, startSection: 1, weeks: [4, 5, 6]),
    ];
    final groups = findInconsistentWeekGroups(courses);
    expect(groups.length, 1);
    expect(groups.first.targetWeeks, [1, 2, 3]);
  });

  test('weeksListEquals 按集合比较', () {
    expect(weeksListEquals([1, 2, 3], [3, 2, 1]), isTrue);
    expect(weeksListEquals([1, 2, 3], [1, 2]), isFalse);
    expect(weeksListEquals([1, 2, 3], [1, 2, 4]), isFalse);
  });

  // ---- 编辑页行为（WB_SPEC_246 §2，复用 wb231 的内存库 + 泵页套路） ----
  group('编辑页周次同步', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late Database db;
    late List<int> ids;

    Course twoSlotCourse({
      required String name,
      required int day,
      required int start,
      required int end,
    }) =>
        Course(
          semesterId: 1,
          name: name,
          colorValue: 0xFF8FA3B0,
          dayOfWeek: day,
          startSection: start,
          endSection: end,
          weeks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
        );

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(db);
    });

    tearDown(() async {
      Dao.debugBeforeUpdateCourse = null;
      await db.close();
    });

    Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }

    Future<void> openEditor(WidgetTester tester, int courseId) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              navigatorKey: navKey,
              home: const Scaffold(body: Text('HOME_PAGE')),
            ),
          ),
        );
      });
      await drain(tester, rounds: 2);
      await tester.runAsync(() async {
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => CourseEditPage(courseId: courseId),
          ),
        );
      });
      await drain(tester);
    }

    Future<List<Course>> allCourses(WidgetTester tester) async {
      final list = await tester.runAsync<List<Course>>(
        () => Dao.instance.getCoursesBySemester(1),
      );
      return list ?? const [];
    }

    Course byId(List<Course> list, int id) =>
        list.firstWhere((c) => c.id == id);

    Future<void> seedTwoSlots() async {
      ids = [
        await Dao.instance.insertCourse(
          twoSlotCourse(name: '药理学', day: 2, start: 1, end: 2),
        ),
        await Dao.instance.insertCourse(
          twoSlotCourse(name: '药理学', day: 4, start: 3, end: 4),
        ),
      ];
    }

    testWidgets('改周次保存：默认同步兄弟时段', (tester) async {
      await tester.runAsync(seedTwoSlots);
      await openEditor(tester, ids[0]);

      // 没改周次时开关行不出现（与颜色同步行同款门控）
      expect(find.byKey(const ValueKey('weeks-sync-all')), findsNothing);

      // 点「单周」把 1–16 周改成单周 1、3、5…15（weekType 保持全部），
      // 开关行随即出现，默认选中「应用到本课全部」。
      // 周次选择器在表单中部，先滑下去（ListView 只建可见子项）
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.tap(find.text('单周'));
      await tester.pump();
      expect(find.byKey(const ValueKey('weeks-sync-all')), findsOneWidget);

      await tester.tap(find.text('保存修改'));
      await drain(tester);

      final list = await allCourses(tester);
      const odd = [1, 3, 5, 7, 9, 11, 13, 15];
      expect(byId(list, ids[0]).weeks, odd);
      expect(byId(list, ids[1]).weeks, odd, reason: '默认一起改');
      expect(byId(list, ids[1]).weekType, 0);
      expect(find.text('已同步到本课共 2 个时段'), findsOneWidget);
      await drain(tester, rounds: 4);
      await tester.pump(const Duration(seconds: 5));
      await drain(tester, rounds: 2);
    });

    testWidgets('周次开关关：仅改本节，兄弟保留原周次', (tester) async {
      await tester.runAsync(seedTwoSlots);
      await openEditor(tester, ids[0]);

      // 先改周次让开关行出现，再把周次开关切到「仅改本节」。
      // 周次选择器在表单中部，先滑下去（ListView 只建可见子项）
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      await tester.tap(find.text('单周'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('weeks-sync-current')));
      await tester.pump();
      await tester.tap(find.text('保存修改'));
      await drain(tester);

      final list = await allCourses(tester);
      expect(byId(list, ids[0]).weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
      expect(
        byId(list, ids[1]).weeks,
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
        reason: '开关关时兄弟保留原周次',
      );
      await drain(tester, rounds: 4);
      await tester.pump(const Duration(seconds: 5));
      await drain(tester, rounds: 2);
    });
  });
}
