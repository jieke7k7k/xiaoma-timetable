import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/pages/import_page.dart';

/// WB_SPEC_256 §7 测试（原 WB_SPEC_220 的底部弹层已废弃）
///
/// 覆盖：
/// 1. 目标选择弹层改走 showAppSelectSheet：学期行只列校名，当前学期行标
///    「当前使用中」并打勾；无新建卡片、无「推荐」徽标；底部 footer 是
///    48dp 的「继续（新建学期）」按钮；
/// 2. 点旧学期行：直接选中并关弹层，目标卡随之改变；
/// 3. 点 footer「继续（新建学期）」：先关弹层再开新建表单，取消后回到
///    导入页、目标不变；
/// 4. 表单建好：写入并切换为当前学期、设为本次目标；
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

  /// WB_SPEC_256 §10 手动泵法（严禁使用 pumpAndSettle）：
  /// 与 wb256 文件的 _drain 同口径——每轮先 runAsync 再 pump。
  Future<void> _drain(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openTargetSheet(WidgetTester tester) async {
    await tapAndSettle(
      tester,
      find.text('更改'),
      waitFor: find.text('导入至哪个学期'),
    );
    expect(find.text('导入至哪个学期'), findsOneWidget);
  }

  group('WB_SPEC_256 §7：导入目标学期选择', () {
    testWidgets('弹层形态：学期行 + 首次打开无默认勾选，无新建卡片/推荐；footer 按钮 48dp',
        (tester) async {
      await pumpImportPage(tester);
      expect(find.text('导入到：大三上学期'), findsOneWidget);

      await openTargetSheet(tester);

      // 220 的新建卡片（置顶默认勾选＋推荐）已随 256 §7 废弃
      expect(find.text('新建学期（新学期的课表选这个）'), findsNothing);
      expect(find.text('推荐'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

      // 学期行：当前学期标「当前使用中」；首次打开无默认勾选
      // （复审 #53，恢复 220「引导新建」语义；选过之后 _target 保持上次选择）
      expect(find.text('大三上学期 · 当前使用中'), findsOneWidget);
      expect(find.text('大二下学期'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);

      // 底部 footer「继续（新建学期）」是 48dp 底部操作栏按钮
      expect(find.text('继续（新建学期）'), findsOneWidget);
      expect(
        tester
            .getSize(find.widgetWithText(FilledButton, '继续（新建学期）'))
            .height,
        48.0,
      );
    });

    testWidgets('点旧学期行：直接选中并关弹层', (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      await tapAndSettle(
        tester,
        find.text('大二下学期'),
        waitFor: find.text('导入到：大二下学期'),
      );

      expect(find.text('导入至哪个学期'), findsNothing);
      expect(find.text('导入到：大二下学期'), findsOneWidget);
    });

    testWidgets('点 footer「继续（新建学期）」进表单，取消后回到导入页、目标不变',
        (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      // footer 点一下先关弹层再开表单：表单在，弹层标题已不在
      await tapAndSettle(
        tester,
        find.text('继续（新建学期）'),
        waitFor: find.text('新建学期'),
      );
      expect(find.text('新建学期'), findsOneWidget);
      expect(find.text('导入至哪个学期'), findsNothing);

      await tapAndSettle(tester, find.text('取消'));

      // 表单关了，回到导入页，目标仍是原来的大三上学期
      expect(find.text('新建学期'), findsNothing);
      expect(find.text('导入至哪个学期'), findsNothing);
      expect(find.text('导入到：大三上学期'), findsOneWidget);
    });

    testWidgets('表单建好：写入并切换当前学期、设为目标', (tester) async {
      await pumpImportPage(tester);
      await openTargetSheet(tester);

      await tapAndSettle(
        tester,
        find.text('继续（新建学期）'),
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

      expect(find.text('导入至哪个学期'), findsNothing);
      expect(find.text('导入到：大三下学期'), findsOneWidget);
      expect(find.textContaining('已新建并切换至「大三下学期」'), findsOneWidget);

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
      await _drain(tester);

      await tester.tap(find.text('打开日历'));
      await _drain(tester);

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
