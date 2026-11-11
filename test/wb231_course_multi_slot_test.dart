import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';

/// WB_SPEC_231 第 10 节：多时段一起编辑（自动同步）。
///
/// 覆盖规格第 10.5 节的验收点：其他时段区、共享字段同步、时间/周次/考试日期不动、
/// 教室异构保护、三选切换、改名撞车、冲突只算当前时段、写失败整批回滚。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  /// 两时段样例课的 id：[0] 周二 1-2（302），[1] 周四 3-4（105）
  late List<int> ids;

  Course course({
    required String name,
    required int day,
    required int start,
    required int end,
    String? teacher,
    String? classroom,
    int colorValue = 0xFF8FA3B0,
  }) {
    return Course(
      semesterId: 1,
      name: name,
      teacher: teacher,
      classroom: classroom,
      colorValue: colorValue,
      dayOfWeek: day,
      startSection: start,
      endSection: end,
      weeks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
    );
  }

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

  /// 给真实异步多轮窗口（写库、provider reload 都是真实 Future）
  Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  /// 打开编辑页：挂在 HOME 之上，保存成功后 pop 回 HOME（不黑屏）
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
    final a = course(
      name: '药理学',
      day: 2,
      start: 1,
      end: 2,
      teacher: '张老师',
      classroom: '302',
    );
    final b = course(
      name: '药理学',
      day: 4,
      start: 3,
      end: 4,
      teacher: '张老师',
      classroom: '105',
    );
    ids = [
      await Dao.instance.insertCourse(a),
      await Dao.instance.insertCourse(b),
    ];
  }

  testWidgets('多时段课：出现「其他时段」区，条数与文案正确', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    expect(find.text('其他时段（同一门课）'), findsOneWidget);
    expect(find.text('周四 第3-4节 · 1-16 周'), findsOneWidget);
  });

  testWidgets('单时段课：不出现「其他时段」区', (tester) async {
    final id = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '单时段课', day: 1, start: 1, end: 2),
      ),
    );
    await openEditor(tester, id!);

    expect(find.text('其他时段（同一门课）'), findsNothing);
  });

  testWidgets('改老师保存：兄弟时段同步老师，时间/周次/教室不动（异构保护）', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    // 只改老师，教室输入框一个字都没碰
    await tester.enterText(find.byType(TextFormField).at(1), '李老师');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    final a = byId(list, ids[0]);
    final b = byId(list, ids[1]);
    expect(a.teacher, '李老师');
    expect(b.teacher, '李老师', reason: '共享字段要同步到兄弟时段');
    expect(b.dayOfWeek, 4);
    expect(b.startSection, 3);
    expect(b.endSection, 4);
    expect(b.weeks, a.weeks, reason: '周次不属于共享字段');
    expect(b.classroom, '105', reason: '没碰教室输入框时保留兄弟时段自己的教室');
    expect(a.classroom, '302');
    // 保存成功提示要说明同步到了几个时段
    expect(find.text('已同步到本课共 2 个时段'), findsOneWidget);
    // 收尾：把 SnackBar 的定时器与保存后的联动异步都走完，
    // 否则结束时会报「A Timer is still pending」
    await drain(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester, rounds: 2);
  });

  testWidgets('亲手改教室保存：兄弟时段教室跟着变', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(2), '16-222');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).classroom, '16-222');
    expect(byId(list, ids[1]).classroom, '16-222');
  });

  testWidgets('切换时段：没改动直接切，表单换成目标时段的值', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    expect(find.text('302'), findsOneWidget);
    await tester.tap(find.text('周四 第3-4节 · 1-16 周'));
    await drain(tester);

    // 没改动时不弹三选框，直接切到周四那一条
    expect(find.text('当前时段有未保存的改动'), findsNothing);
    expect(find.text('105'), findsOneWidget);
  });

  testWidgets('切换时段：有改动 → 三选框「取消」留在原时段', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(1), '王老师');
    await tester.pump();
    await tester.tap(find.text('周四 第3-4节 · 1-16 周'));
    await drain(tester);

    expect(find.text('当前时段有未保存的改动'), findsOneWidget);
    expect(find.text('保存'), findsWidgets);
    expect(find.text('放弃'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await drain(tester);

    // 留在原时段：教室里还是 302，老师输入框还是刚填的
    expect(find.text('302'), findsOneWidget);
    expect(find.text('王老师'), findsOneWidget);
  });

  testWidgets('切换时段：选「放弃」→ 丢弃改动并换成目标时段库里的值', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(1), '王老师');
    await tester.pump();
    await tester.tap(find.text('周四 第3-4节 · 1-16 周'));
    await drain(tester);
    await tester.tap(find.text('放弃'));
    await drain(tester);

    expect(find.text('105'), findsOneWidget, reason: '表单重置为目标时段的值');
    expect(find.text('王老师'), findsNothing, reason: '丢弃的改动不能留在表单里');
    // 库里原值没被改
    final list = await allCourses(tester);
    expect(byId(list, ids[0]).teacher, '张老师');
  });

  testWidgets('切换时段：选「保存」→ 先同步保存再切过去', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(1), '王老师');
    await tester.pump();
    await tester.tap(find.text('周四 第3-4节 · 1-16 周'));
    await drain(tester);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await drain(tester);

    expect(find.text('105'), findsOneWidget, reason: '保存成功后切到目标时段');
    final list = await allCourses(tester);
    expect(byId(list, ids[0]).teacher, '王老师');
    expect(byId(list, ids[1]).teacher, '王老师');
  });

  testWidgets('改名撞车已有课程：保存前弹合并确认框，取消则不改', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '临床药理学', day: 6, start: 5, end: 6),
      ),
    );
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(0), '临床药理学');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await drain(tester);

    expect(find.text('合并同名课程？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).name, '药理学');
    expect(byId(list, ids[1]).name, '药理学');
  });

  testWidgets('改名（不撞车）：兄弟时段一起改名，没有时段被拆出去', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(0), '临床药理学');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).name, '临床药理学');
    expect(byId(list, ids[1]).name, '临床药理学');
  });

  testWidgets('写库失败：整批回滚，兄弟时段保持原值', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    // 写兄弟时段时抛错 → 事务整体回滚（当前时段也不该落库）
    Dao.debugBeforeUpdateCourse = (c) async {
      if (c.id == ids[1]) throw StateError('模拟写库失败');
    };
    await tester.enterText(find.byType(TextFormField).at(1), '李老师');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await drain(tester);

    expect(find.text('保存失败，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    final list = await allCourses(tester);
    expect(byId(list, ids[0]).teacher, '张老师', reason: '整批回滚，当前时段也不能被写进去');
    expect(byId(list, ids[1]).teacher, '张老师');
  });
}
