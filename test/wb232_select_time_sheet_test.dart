import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/widgets/select_time_sheet.dart';

/// 固定浏览周次（测试里不依赖真实时钟算出来的「本周」）
class _FixedWeek extends DisplayWeekNotifier {
  @override
  int build() => 1;
}

/// WB_SPEC_232 第 6 节：「在课表上选」弹层
///
/// 覆盖规格第 9 节第 3 组验收：点两格定一段、反序自动正序、跨天重置、
/// 同格两下保持单节、连成一段后第三下重置、跨午休可连、
/// 点有课格子出软提示且可确认、取消不写回、确认写回三个变量、翻周只改占用显示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  ({int dayOfWeek, int startSection, int endSection})? result;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    result = null;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> drain(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(
    WidgetTester tester, {
    int day = 1,
    int start = 1,
    int end = 1,
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [displayWeekProvider.overrideWith(_FixedWeek.new)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showSelectTimeSheet(
                      context: context,
                      dayOfWeek: day,
                      startSection: start,
                      endSection: end,
                    );
                  },
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
    });
    await drain(tester, rounds: 3);
    await tester.runAsync(() async {
      await tester.tap(find.text('OPEN'));
    });
    // 弹层里 watch 的 timeSlotsProvider / coursesProvider 是在弹层建出来之后
    // 才开始加载的：必须再抽一轮真实时间，否则网格按空作息画出 12 节、
    // 底部时间也取不到（这是测试写法问题，不是产品 bug）
    await drain(tester, rounds: 4);
    await tester.pumpAndSettle();
  }

  /// 收尾：把真实异步（写库 / provider 刷新）抽干再销毁树，
  /// 否则 sqflite 的 10 秒锁警告定时器会在 teardown 报「Timer is still pending」
  Future<void> endTest(WidgetTester tester) async {
    await drain(tester, rounds: 3);
    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester, rounds: 2);
  }

  /// 点「确认选定」并等真实异步续体跑完（onPressed 的 await 是在 runAsync 的
  /// 真实 zone 里发起的，普通 pump 拿不到它的返回值）
  Future<void> tapConfirm(WidgetTester tester) async {
    await tester.tap(find.text('确认选定'));
    await tester.pumpAndSettle();
    // 关闭动效结束后再给真实异步一个窗口：sheet 的 Future 是在 runAsync 的
    // 真实 zone 里被 await 的，续体要等真实时间推进才会写进 result
    await drain(tester, rounds: 2);
  }

  Future<void> tapCell(WidgetTester tester, int day, int section) async {
    await tester.tap(find.byKey(ValueKey('mini-cell-$day-$section')));
    await tester.pump();
  }

  testWidgets('点两格定一段，确认写回三个值', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 3, 3);
    await tapCell(tester, 3, 5);
    expect(find.textContaining('第 3–5 节'), findsOneWidget);
    // 时间取 timeSlots（第 3 节 09:40 上课、第 5 节 12:00 下课）
    expect(find.textContaining('09:40-12:00'), findsOneWidget);

    await tapConfirm(tester);
    expect(result, (dayOfWeek: 3, startSection: 3, endSection: 5));
    await endTest(tester);
  });

  testWidgets('反序点（先 5 后 3）自动正序合成 3–5', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 3, 5);
    await tapCell(tester, 3, 3);
    expect(find.textContaining('第 3–5 节'), findsOneWidget);
    await tapConfirm(tester);
    expect(result, (dayOfWeek: 3, startSection: 3, endSection: 5));
    await endTest(tester);
  });

  testWidgets('点到另一天：直接以新格为新起点（重置为单节）', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 3, 3);
    await tapCell(tester, 4, 2);
    expect(find.textContaining('周四 · 第 2 节'), findsOneWidget);
    await tapConfirm(tester);
    expect(result, (dayOfWeek: 4, startSection: 2, endSection: 2));
    await endTest(tester);
  });

  testWidgets('同一格点两下：保持单节', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 2, 4);
    await tapCell(tester, 2, 4);
    expect(find.textContaining('第 4 节'), findsOneWidget);
    expect(find.textContaining('–'), findsNothing);
    await tapConfirm(tester);
    expect(result, (dayOfWeek: 2, startSection: 4, endSection: 4));
    await endTest(tester);
  });

  testWidgets('连成一段后再点第 3 下：以最新格为新起点', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 3, 3);
    await tapCell(tester, 3, 5);
    await tapCell(tester, 3, 8);
    expect(find.textContaining('第 8 节'), findsOneWidget);
    await tapConfirm(tester);
    expect(result, (dayOfWeek: 3, startSection: 8, endSection: 8));
    await endTest(tester);
  });

  testWidgets('可以跨过午休带连成 5–6 节', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 1, 5);
    await tapCell(tester, 1, 6);
    expect(find.textContaining('第 5–6 节'), findsOneWidget);
    await tapConfirm(tester);
    expect(result, (dayOfWeek: 1, startSection: 5, endSection: 6));
    await endTest(tester);
  });

  testWidgets('打开时高亮编辑页当前选区（反向同步）', (tester) async {
    await openSheet(tester, day: 3, start: 5, end: 6);
    expect(find.textContaining('周三 · 第 5–6 节'), findsOneWidget);
    await endTest(tester);
  });

  testWidgets('点有课格子给软提示，不阻断确认', (tester) async {
    await tester.runAsync(() => Dao.instance.insertCourse(Course(
          semesterId: 1,
          name: '药理学',
          colorValue: 0xFF8FA3B0,
          dayOfWeek: 3,
          startSection: 3,
          endSection: 4,
          weeks: const [1, 2, 3],
        )));
    await openSheet(tester);
    // 该格子压暗显示课程名（占位参考）
    expect(find.text('药理学'), findsWidgets);
    await tapCell(tester, 3, 3);
    // 温和提示，不弹窗
    expect(find.textContaining('该时段在部分周次已有『药理学』'), findsOneWidget);
    await tapConfirm(tester);
    // 照常回填
    expect(result, (dayOfWeek: 3, startSection: 3, endSection: 3));
    await endTest(tester);
  });

  testWidgets('翻周只改占用显示，不改回填内容', (tester) async {
    await tester.runAsync(() => Dao.instance.insertCourse(Course(
          semesterId: 1,
          name: '药理学',
          colorValue: 0xFF8FA3B0,
          dayOfWeek: 3,
          startSection: 3,
          endSection: 4,
          weeks: const [1], // 只有第 1 周有课
        )));
    await openSheet(tester);
    expect(find.text('药理学'), findsWidgets);

    await tapCell(tester, 3, 3);
    expect(find.textContaining('第 3 节'), findsOneWidget);

    // 翻到第 2 周：占用消失，但选区与底部结果不变
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('第 2 周'), findsOneWidget);
    expect(find.text('药理学'), findsNothing);
    expect(find.textContaining('周三 · 第 3 节'), findsOneWidget);

    await tapConfirm(tester);
    expect(result, (dayOfWeek: 3, startSection: 3, endSection: 3));
    await endTest(tester);
  });

  testWidgets('下划/scrim 关闭＝取消，不写回', (tester) async {
    await openSheet(tester);
    await tapCell(tester, 3, 3);
    // 点 scrim（弹层之外的区域）关闭
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('确认选定'), findsNothing);
    expect(result, isNull);
    await endTest(tester);
  });

  testWidgets('迷你网格用 timeSlotsProvider 的实际节次（13 节），不是写死 13 以外',
      (tester) async {
    await openSheet(tester);
    // DB 种子是 13 节：第 13 节的格子存在，第 14 节不存在
    expect(find.byKey(const ValueKey('mini-cell-7-13')), findsOneWidget);
    expect(find.byKey(const ValueKey('mini-cell-7-14')), findsNothing);
    await endTest(tester);
  });

  testWidgets('360dp 窄屏下迷你网格不溢出（三处窄屏验证之一）', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await openSheet(tester);
    expect(tester.takeException(), isNull);
    // 7 列都在，最右一列（周日）仍可点
    expect(find.byKey(const ValueKey('mini-cell-7-1')), findsOneWidget);
    await tapCell(tester, 7, 3);
    expect(find.textContaining('周日 · 第 3 节'), findsOneWidget);
    await endTest(tester);
  });
}
