import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/pages/import_page.dart';

/// WB_SPEC_220 测试
///
/// 覆盖：
/// 1. 目标选择弹层：新建卡片置顶默认勾选＋「推荐」徽标；当前学期行只标
///    「当前使用中」、不再打勾；
/// 2. 点旧学期行：直接选中并关弹层，目标卡随之改变；
/// 3. 点新建行：表单叠在弹层上方，表单取消后弹层仍在、可改选旧学期；
/// 4. 表单建好：写入并切换为当前学期、设为本次目标、关弹层；
/// 5. 日历中文：配中文 delegates 的 MaterialApp 下 showDatePicker
///    显示「取消 / 确定」与中文星期。
void main() {
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
    // createSchema 自带一个 isCurrent=1 的默认学期，先清掉再按用例需要播种，
    // 否则默认学期会抢走「当前学期」，目标卡显示的就不是大三上学期。
    await db.delete('semesters');
    final currentId = await Dao.instance.insertSemester(
      const Semester(
        name: '大三上学期',
        startDate: '2026-09-07',
        totalWeeks: 20,
      ),
    );
    await Dao.instance.insertSemester(
      const Semester(
        name: '大二下学期',
        startDate: '2026-02-23',
        totalWeeks: 20,
      ),
    );
    await Dao.instance.setCurrentSemester(currentId);
  });

  tearDown(() async {
    // 直接 await 可能在测试区挂起：用真实异步关库
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
      () => db.close(),
    );
  });

  Future<void> pumpImportPage(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: ImportPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 点一个会触发真实异步数据库读写的控件：FFI 完成要靠 pump 投递，
  /// 链上每一步（弹层动画→表单→插入→重载→切换事务→读回）都要一轮
  /// pump + 一段真实时间才能往下走；单次 pumpAndSettle 与单次 runAsync
  /// 延时都推不动整条链。带 [waitFor] 时一旦目标出现就停，不空转。
  Future<void> tapAndSettle(
    WidgetTester tester,
    Finder finder, {
    Finder? waitFor,
  }) async {
    await tester.tap(finder);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (waitFor != null && waitFor.evaluate().isNotEmpty) break;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openTargetSheet(WidgetTester tester) async {
    await tapAndSettle(
      tester,
      find.text('更改'),
      waitFor: find.text('这次导入到哪个学期？'),
    );
    expect(find.text('这次导入到哪个学期？'), findsOneWidget);
  }

  double y(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  group('WB_SPEC_220：导入默认新建学期', () {
    testWidgets('弹层形态：新建卡片置顶默认勾选＋推荐，旧学期无打勾', (tester) async {
      await pumpImportPage(tester);
      expect(find.text('导入到：大三上学期'), findsOneWidget);

      await openTargetSheet(tester);

      // 新建卡片在已有学期之前，且带「推荐」徽标与勾选图标
      expect(find.text('新建学期（新学期的课表选这个）'), findsOneWidget);
      expect(find.text('推荐'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        y(tester, '新建学期（新学期的课表选这个）'),
        lessThan(y(tester, '大三上学期')),
        reason: '新建卡片应置顶，在已有学期之前',
      );
      expect(
        y(tester, '新建学期（新学期的课表选这个）'),
        lessThan(y(tester, '大二下学期')),
        reason: '新建卡片应置顶，在已有学期之前',
      );

      // 当前学期只标「当前使用中」，不再打勾
      expect(find.textContaining('当前使用中'), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));

      // 底部主按钮
      expect(find.text('继续（新建学期）'), findsOneWidget);
    });

    testWidgets('点旧学期行：直接选中并关弹层', (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      await tapAndSettle(
        tester,
        find.text('大二下学期'),
        waitFor: find.text('导入到：大二下学期'),
      );

      expect(find.text('这次导入到哪个学期？'), findsNothing);
      expect(find.text('导入到：大二下学期'), findsOneWidget);
    });

    testWidgets('点新建行进表单，取消后弹层仍在、可改选旧学期', (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      await tapAndSettle(
        tester,
        find.text('新建学期（新学期的课表选这个）'),
        waitFor: find.text('新建学期'),
      );
      expect(find.text('新建学期'), findsOneWidget);

      // 取消后弹层仍在：不用 waitFor——弹层行在表单后面一直都在树里，
      // waitFor 会立刻命中、循环提前退出，表单关闭动画还没跑完。
      await tapAndSettle(tester, find.text('取消'));

      // 表单关了，弹层还在：标题与旧学期行都在
      expect(find.text('新建学期'), findsNothing);
      expect(find.text('这次导入到哪个学期？'), findsOneWidget);
      expect(find.text('大二下学期'), findsOneWidget);

      // 改选旧学期仍能走通
      await tapAndSettle(
        tester,
        find.text('大二下学期'),
        waitFor: find.text('导入到：大二下学期'),
      );
      expect(find.text('导入到：大二下学期'), findsOneWidget);
    });

    testWidgets('底部「继续（新建学期）」按钮同样进新建表单（复审 L5）',
        (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      await tapAndSettle(
        tester,
        find.text('继续（新建学期）'),
        waitFor: find.text('新建学期'),
      );
      expect(find.text('新建学期'), findsOneWidget);

      // 取消后弹层仍在
      await tapAndSettle(tester, find.text('取消'));
      expect(find.text('新建学期'), findsNothing);
      expect(find.text('这次导入到哪个学期？'), findsOneWidget);
    });

    testWidgets('表单建好：写入并切换当前学期、设为目标、关弹层', (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      await tapAndSettle(
        tester,
        find.text('新建学期（新学期的课表选这个）'),
        waitFor: find.text('新建学期'),
      );
      expect(find.text('新建学期'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '大三下学期');
      await tapAndSettle(
        tester,
        find.text('创建'),
        waitFor: find.text('确认开学日期'),
      );

      // 落库前过目确认开学日期
      expect(find.text('确认开学日期'), findsOneWidget);
      await tapAndSettle(
        tester,
        find.text('确认无误'),
        waitFor: find.text('导入到：大三下学期'),
      );

      expect(find.text('这次导入到哪个学期？'), findsNothing);
      expect(find.text('导入到：大三下学期'), findsOneWidget);
      expect(find.textContaining('已新建并切换到「大三下学期」'), findsOneWidget);

      // 新学期已写入库并成为当前学期
      final rows = await tester.runAsync(
        () => db.query(
          'semesters',
          where: 'name = ?',
          whereArgs: ['大三下学期'],
        ),
      );
      expect(rows, hasLength(1));
      expect(rows!.first['isCurrent'], 1);

      // 成功 SnackBar（默认 4 秒）还挂着定时器：走完它再结束用例，
      // 否则框架在 tearDown 时报 "A Timer is still pending"。
      await tester.pump(const Duration(seconds: 60));
    });
  });

  group('WB_SPEC_220：开学日期日历中文', () {
    testWidgets('配中文 delegates 的 showDatePicker 显示中文按钮与星期',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDatePicker(
                  context: context,
                  initialDate: DateTime(2026, 9, 7),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                  helpText: '选择开学日期',
                ),
                child: const Text('打开日历'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开日历'));
      await tester.pumpAndSettle();

      expect(find.text('选择开学日期'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      // 中文星期表头（日 一 二 三 四 五 六）
      expect(find.text('一'), findsOneWidget);
      expect(find.text('六'), findsOneWidget);
      // 无英文残留
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('OK'), findsNothing);
    });
  });
}
