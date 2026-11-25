import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/widgets/draft_edit_dialog.dart';
import 'package:xiaoma_timetable/widgets/marquee_text.dart';
import 'package:xiaoma_timetable/widgets/semester_form_dialog.dart';

/// WB_SPEC_264 第 4 段（§4 性能与资源 + §5 体验与文案）回归测试
void main() {
  group('C20/C24 Dao', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late Database db;

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
      try {
        await db.close();
      } catch (_) {
        // C24 用例会先关库，这里容错
      }
    });

    test('C20 删除学期：调课记录随课程一起批量删除，不留悬空数据', () async {
      final semesterId = await Dao.instance.insertSemester(
        const Semester(name: '大三上', startDate: '2026-09-07', totalWeeks: 20),
      );
      final courseId = await Dao.instance.insertCourse(
        Course(
          semesterId: semesterId,
          name: '高数',
          colorValue: 0xFF6B8E7B,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 1,
          weeks: const [1, 2],
        ),
      );
      await Dao.instance.upsertOverride(
        CourseOverride(
          courseId: courseId,
          originalWeek: 2,
          targetWeek: CourseOverride.cancelFlag,
        ),
      );
      expect((await Dao.instance.getOverridesBySemester(semesterId)).length, 1);

      await Dao.instance.deleteSemester(semesterId);

      expect(await Dao.instance.getCoursesBySemester(semesterId), isEmpty);
      expect(await Dao.instance.getOverridesBySemester(semesterId), isEmpty);
      // createSchema 会播种一个默认学期，删掉的学期不应再出现
      expect(
        (await Dao.instance.getAllSemesters()).map((s) => s.id),
        isNot(contains(semesterId)),
      );
    });

    test('C24 业务校验异常原样抛出，不被包成中文异常', () async {
      await expectLater(
        Dao.instance.updateSemester(
          const Semester(name: 'x', startDate: '2026-09-07', totalWeeks: 20),
        ),
        throwsArgumentError,
      );
      await expectLater(
        Dao.instance.updateCourse(
          Course(
            semesterId: 1,
            name: '高数',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 1,
            weeks: const [1],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('C24 底层数据库异常转为中文 DaoException，原始异常不直达 UI', () async {
      await db.close();
      await expectLater(
        Dao.instance.getAllSemesters(),
        throwsA(
          isA<DaoException>().having(
            (e) => e.toString(),
            'message',
            '读取学期列表失败，请稍后重试',
          ),
        ),
      );
    });
  });

  group('S4-3 学期表单内联校验', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final testDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(testDb);
      addTearDown(() async {
        try {
          await testDb.close();
        } catch (_) {}
      });
    });

    testWidgets('空名提交：内联红字出现，弹窗不关闭、不弹 SnackBar', (tester) async {
      Semester? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _FormHarness(onResult: (r) => result = r),
          ),
        ),
      );
      await tester.tap(find.text('打开表单'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('创建'));
      await tester.pump();

      expect(find.text('请填写学期名称'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(result, isNull);
      expect(find.text('新建学期'), findsOneWidget);
    });

    testWidgets('周数清空提交：周数内联红字出现', (tester) async {
      Semester? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _FormHarness(onResult: (r) => result = r),
          ),
        ),
      );
      await tester.tap(find.text('打开表单'));
      await tester.pumpAndSettle();

      // L4（DeepSeek 264 复审 B 段）：不用 first/last 抓 TextField——
      // 学期名称在前、总周数在后，按 labelText 定位才咬得住字段本身
      await tester.enterText(
        find.widgetWithText(TextField, '学期名称'),
        '大三下学期',
      );
      await tester.enterText(find.widgetWithText(TextField, '总周数'), '');
      await tester.tap(find.text('创建'));
      await tester.pump();

      expect(find.text('请输入 1~30 之间的周数'), findsOneWidget);
      expect(result, isNull);
    });
  });

  group('S4-1 草稿弹窗空名内联校验', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final testDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(testDb);
      addTearDown(() async {
        try {
          await testDb.close();
        } catch (_) {}
      });
    });

    testWidgets('空名点确定：内联红字出现，弹窗不关闭', (tester) async {
      // M9（DeepSeek 264 复审 B 段）：S4-1 的修复是空名错误拆出独立 _nameError
      // 挂在课程名输入框上；只断「不返回结果」咬不住，必须断言红字文案逐字出现
      // 且弹窗仍在（未关闭、未弹 SnackBar）。
      Course? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _DraftHarness(onResult: (r) => result = r),
          ),
        ),
      );
      await tester.tap(find.text('打开草稿弹窗'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '课程名 *'),
        '',
      );
      await tester.tap(find.text('确定'));
      await tester.pump();

      expect(find.text('课程名不能为空'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(result, isNull);
      expect(find.text('编辑导入课程'), findsOneWidget);
      // 收尾：失焦停掉输入框光标闪烁定时器，否则 teardown 报 Timer pending。
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      // sqflite 锁警告定时器（10 秒）：草稿弹窗挂载时 timeSlots/segment 两个
      // provider 并发读库，txnSynchronized 会挂一个 10 秒超时 Timer；测试在
      // 10 个假秒内结束就会在 teardown 报 Timer pending，泵过 11 秒让它跑完。
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('改名后点确定：返回编辑后的课程', (tester) async {
      Course? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _DraftHarness(onResult: (r) => result = r),
          ),
        ),
      );
      await tester.tap(find.text('打开草稿弹窗'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, '课程名 *'),
        '线代',
      );
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.name, '线代');
      expect(result!.dayOfWeek, 1);
      expect(result!.weeks, [1, 2]);
      expect(find.text('编辑导入课程'), findsNothing);
      // 收尾：失焦停掉输入框光标闪烁定时器，否则 teardown 报 Timer pending。
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      // sqflite 锁警告定时器（10 秒）：同上，泵过 11 秒让它跑完。
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('S4-5 跑马灯无障碍', () {
    testWidgets('开启「移除动画」时超长文本静态渲染，不滚动', (tester) async {
      const longText = '正在上课 · 实验室 14:00 - 17:10 ｜ 下一节 药物化学 明天 08:00';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: SizedBox(
                  width: 300,
                  child: MarqueeText(
                    longText,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ClipRect), findsNothing);
      expect(find.byType(OverflowBox), findsNothing);
      expect(find.text(longText), findsOneWidget);
    });
  });
}

/// 只负责把学期表单弹出来并把结果交回测试的壳
class _FormHarness extends StatelessWidget {
  const _FormHarness({required this.onResult});

  final void Function(Semester?) onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            onResult(await showSemesterFormDialog(context));
          },
          child: const Text('打开表单'),
        ),
      ),
    );
  }
}

/// S4-1 草稿弹窗测试支架：点按钮打开 showDraftEditDialog（草稿「高数」），
/// 把返回值交给 [onResult]。
class _DraftHarness extends StatelessWidget {
  const _DraftHarness({required this.onResult});

  final void Function(Course?) onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            onResult(
              await showDraftEditDialog(
                context,
                const Course(
                  semesterId: 1,
                  name: '高数',
                  colorValue: 0xFF6B8E7B,
                  dayOfWeek: 1,
                  startSection: 1,
                  endSection: 2,
                  weeks: [1, 2],
                ),
              ),
            );
          },
          child: const Text('打开草稿弹窗'),
        ),
      ),
    );
  }
}
