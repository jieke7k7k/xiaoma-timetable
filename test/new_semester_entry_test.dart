import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/widgets/semester_form_dialog.dart';

/// WB_SPEC_224：新建课表（＋ 菜单入口）
///
/// 覆盖规格书第 5 节要求的全部断言：
/// 1. 纯函数：新建总周数默认值（跟当前课表 / 读不到回落 20）；
///    下学期开学月推测（1–6 月→当年 9 月、7–12 月→次年 3 月，无当前学期按今天推，
///    超出生效区间回落今天）；
/// 2. 表单：新建默认周数 = 当前学期周数、无当前学期回落 20、编辑模式仍取
///    initial.totalWeeks；日历打开停在推测月份 1 号（秋→次年 3 月、春→当年 9 月）；
///    表单不预填日期；对齐小提示存在；
/// 3. ＋ 菜单：三行齐全；点「新建课表」弹新建表单；建好后切到新课表（空学期、第 1 周）。
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
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.1.7',
      buildNumber: '32',
      buildSignature: '',
    );
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    String two(int v) => v.toString().padLeft(2, '0');
    final start = '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    sundayDialogNow = () => monday;
    // createSchema 自带一个默认学期，先清掉再按用例播种
    await db.delete('semesters');
    await Dao.instance.insertSemester(
      Semester(
        name: '大三上学期',
        startDate: start,
        totalWeeks: 16,
        isCurrent: true,
      ),
    );
  });

  tearDown(() async {
    sundayDialogNow = DateTime.now;
    // 直接 await 可能在测试假时钟里挂起：用真实异步关库
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
      () => db.close(),
    );
  });

  // ---------------------------------------------------------------------------
  // 1. 纯函数
  // ---------------------------------------------------------------------------
  group('新建总周数默认值（3.2）', () {
    test('能读到就用当前课表的周数', () {
      expect(defaultWeeksForNewSemester(16), 16);
      expect(defaultWeeksForNewSemester(20), 20);
      // 边界：1 与 30 都是合法值，不能被当成脏数据
      expect(defaultWeeksForNewSemester(1), 1);
      expect(defaultWeeksForNewSemester(30), 30);
    });

    test('读不到 / 越界回落 20', () {
      expect(defaultWeeksForNewSemester(null), 20);
      expect(defaultWeeksForNewSemester(0), 20);
      expect(defaultWeeksForNewSemester(-5), 20);
      expect(defaultWeeksForNewSemester(31), 20);
      expect(defaultWeeksForNewSemester(9999), 20);
    });
  });

  group('下学期开学月推测（3.3 / 8.4）', () {
    test('秋季开学（7–12 月）→ 次年 3 月 1 日', () {
      expect(
        guessNextSemesterStartMonth(DateTime(2026, 9, 7)),
        DateTime(2027, 3, 1),
      );
      // 月份分界：7 月已算秋季
      expect(
        guessNextSemesterStartMonth(DateTime(2026, 7, 1)),
        DateTime(2027, 3, 1),
      );
      expect(
        guessNextSemesterStartMonth(DateTime(2026, 12, 28)),
        DateTime(2027, 3, 1),
      );
    });

    test('春季开学（1–6 月）→ 当年 9 月 1 日', () {
      expect(
        guessNextSemesterStartMonth(DateTime(2026, 3, 2)),
        DateTime(2026, 9, 1),
      );
      // 月份分界：6 月仍算春季
      expect(
        guessNextSemesterStartMonth(DateTime(2026, 6, 29)),
        DateTime(2026, 9, 1),
      );
      expect(
        guessNextSemesterStartMonth(DateTime(2026, 1, 5)),
        DateTime(2026, 9, 1),
      );
    });

    test('读不到当前学期：按今天推（1 月→当年 3 月、2–7 月→当年 9 月、8–12 月→次年 3 月）',
        () {
      // now 必须显式传：这组断言不能依赖跑测试当天的真实日期
      expect(
        guessNextSemesterStartMonth(null, now: DateTime(2026, 1, 15)),
        DateTime(2026, 3, 1),
      );
      expect(
        guessNextSemesterStartMonth(null, now: DateTime(2026, 2, 1)),
        DateTime(2026, 9, 1),
      );
      expect(
        guessNextSemesterStartMonth(null, now: DateTime(2026, 7, 31)),
        DateTime(2026, 9, 1),
      );
      expect(
        guessNextSemesterStartMonth(null, now: DateTime(2026, 8, 1)),
        DateTime(2027, 3, 1),
      );
      expect(
        guessNextSemesterStartMonth(null, now: DateTime(2026, 11, 8)),
        DateTime(2027, 3, 1),
      );
    });

    test('推测结果超出生效区间（2020-01-01 ~ 2035-12-31）回落今天', () {
      // 2035 年秋季开学 → 推测 2036-03-01，超出 lastDate
      expect(
        guessNextSemesterStartMonth(
          DateTime(2035, 9, 3),
          now: DateTime(2035, 9, 3),
        ),
        DateTime(2035, 9, 3),
      );
    });

    test('推测结果超界且今天本身也超界：回落值夹到区间里（复审 Bug 2）', () {
      // 今天已在 2036 年：推测 2036-03-01 超界，回落今天仍超界 → 夹到 2035-12-31
      expect(
        guessNextSemesterStartMonth(
          DateTime(2035, 9, 3),
          now: DateTime(2036, 6, 1),
        ),
        DateTime(2035, 12, 31),
      );
      // 今天在 2020 年之前：无当前学期，推测 2019-09-01 超界 → 夹到 2020-01-01
      expect(
        guessNextSemesterStartMonth(null, now: DateTime(2019, 6, 1)),
        DateTime(2020, 1, 1),
      );
    });

    test('推测月份恒为 1 号（只到月份，不猜具体哪天）', () {
      for (final start in [
        DateTime(2026, 9, 7),
        DateTime(2026, 3, 2),
        DateTime(2026, 11, 30),
      ]) {
        expect(guessNextSemesterStartMonth(start).day, 1);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 2. 表单（widget）
  // ---------------------------------------------------------------------------
  group('学期表单：新建默认值', () {
    const current = Semester(
      id: 1,
      name: '大三上学期',
      startDate: '2026-09-07',
      totalWeeks: 16,
      isCurrent: true,
    );

    testWidgets('新建：总周数默认 = 当前学期总周数，日期不预填', (tester) async {
      await pumpForm(tester, current: current);

      expect(find.text('新建学期'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.first.controller!.text, isEmpty, reason: '名称不预填');
      expect(fields.last.controller!.text, '16', reason: '总周数跟当前课表走');
      // 表单里没有假日期
      expect(find.text('默认从本周开始'), findsOneWidget);
    });

    testWidgets('新建：读不到当前学期时总周数回落 20', (tester) async {
      await pumpForm(tester, current: null);

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.last.controller!.text, '20');
      expect(find.text('默认从本周开始'), findsOneWidget);
    });

    testWidgets('编辑：仍取该学期自己的总周数（不读当前学期）', (tester) async {
      // 当前学期是 16 周，被编辑的学期是 18 周——必须显示 18
      await pumpForm(
        tester,
        current: current,
        initial: const Semester(
          id: 9,
          name: '大二下学期',
          startDate: '2026-02-23',
          totalWeeks: 18,
        ),
      );

      expect(find.text('编辑学期'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.last.controller!.text, '18');
      expect(find.text('2026-02-23（周一）'), findsOneWidget);
    });
  });

  group('学期表单：日历停在推测月份，但不预填日期', () {
    testWidgets('秋季开学（2026-09-07）→ 日历停在 2027 年 3 月', (tester) async {
      await pumpForm(
        tester,
        current: const Semester(
          id: 1,
          name: '大三上学期',
          startDate: '2026-09-07',
          totalWeeks: 20,
          isCurrent: true,
        ),
      );

      await tester.tap(find.text('开学日期'));
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.initialDate, DateTime(2027, 3, 1));

      // 取消后表单仍是「未选日期」——推测月份只翻页，不写进表单
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text('默认从本周开始'), findsOneWidget);
      expect(find.textContaining('2027-03-01'), findsNothing);
    });

    testWidgets('春季开学（2026-03-02）→ 日历停在 2026 年 9 月', (tester) async {
      await pumpForm(
        tester,
        current: const Semester(
          id: 1,
          name: '大二下学期',
          startDate: '2026-03-02',
          totalWeeks: 20,
          isCurrent: true,
        ),
      );

      await tester.tap(find.text('开学日期'));
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.initialDate, DateTime(2026, 9, 1));
    });

    testWidgets('编辑模式：日历停在原开学日期那月', (tester) async {
      await pumpForm(
        tester,
        current: const Semester(
          id: 1,
          name: '大三上学期',
          startDate: '2026-09-07',
          totalWeeks: 20,
          isCurrent: true,
        ),
        initial: const Semester(
          id: 9,
          name: '大二下学期',
          startDate: '2026-02-23',
          totalWeeks: 18,
        ),
      );

      await tester.tap(find.text('开学日期'));
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.initialDate, DateTime(2026, 2, 23));
    });

    testWidgets('编辑脏数据：开学日超出可选区间时日历 initialDate 夹到区间里（复审 Bug 4）',
        (tester) async {
      await pumpForm(
        tester,
        current: const Semester(
          id: 1,
          name: '大三上学期',
          startDate: '2026-09-07',
          totalWeeks: 20,
          isCurrent: true,
        ),
        initial: const Semester(
          id: 9,
          name: '大二下学期',
          startDate: '2036-03-02',
          totalWeeks: 18,
        ),
      );

      await tester.tap(find.text('开学日期'));
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(picker.initialDate, DateTime(2035, 12, 31));
    });
  });

  group('学期表单：对齐小提示（3.4）', () {
    testWidgets('新建与编辑都能看到对齐提示，且提示在开学日期行下方', (tester) async {
      await pumpForm(
        tester,
        current: const Semester(
          id: 1,
          name: '大三上学期',
          startDate: '2026-09-07',
          totalWeeks: 20,
          isCurrent: true,
        ),
      );

      const hint = '提示：点选任意日期，将自动对齐至当周周一';
      expect(find.text(hint), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(hint)).dy,
        greaterThan(tester.getTopLeft(find.text('开学日期')).dy),
        reason: '提示应在开学日期行正下方',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 3. ＋ 菜单入口（整页）
  // ---------------------------------------------------------------------------
  group('＋ 菜单入口', () {
    testWidgets('菜单三行齐全：手动新建课程 / 导入课表 / 新建课表', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.add_outlined));
      await tester.pumpAndSettle();

      expect(find.text('手动新建课程'), findsOneWidget);
      expect(find.text('导入课表'), findsOneWidget);
      expect(find.text('新建课表'), findsOneWidget);
      expect(find.text('新建一个学期，建好直接切换'), findsOneWidget);
      await settlePendingDbTimers(tester);
    });

    testWidgets('点「新建课表」弹新建学期表单，默认周数跟着当前课表', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.add_outlined));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('新建课表'), waitFor: find.text('新建学期'));

      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.last.controller!.text, '16', reason: '当前学期 16 周');
      expect(find.text('提示：点选任意日期，将自动对齐至当周周一'), findsOneWidget);
      await settlePendingDbTimers(tester);
    });

    testWidgets('建好直接切到新课表：空学期、第 1 周、提示已切换', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.byIcon(Icons.add_outlined));
      await tester.pumpAndSettle();
      await tapAndSettle(tester, find.text('新建课表'), waitFor: find.text('新建学期'));

      await tester.enterText(find.byType(TextField).first, '大四上学期');
      await tapAndSettle(tester, find.text('创建'), waitFor: find.text('确认开学日期'));
      // 保存前的开学日期确认弹窗不动，照常确认
      await tapAndSettle(
        tester,
        find.text('确认无误'),
        waitFor: find.text('已新建并切换到「大四上学期」'),
      );

      // 真的切过去了（不只是提示）
      final current = await tester.runAsync(
        () => Dao.instance.getCurrentSemester(),
      );
      expect(current?.name, '大四上学期');
      expect(current?.totalWeeks, 16);

      // 新课表是空学期、回到第 1 周
      expect(find.textContaining('第 1 周'), findsWidgets);
      expect(find.text('本周没有课程'), findsOneWidget);
      await settlePendingDbTimers(tester);
    });
  });
}

// -----------------------------------------------------------------------------
// 测试脚手架
// -----------------------------------------------------------------------------

/// 固定当前学期（不读库）
class _FixedCurrent extends CurrentSemesterNotifier {
  _FixedCurrent(this.semester);

  final Semester semester;

  @override
  Future<Semester> build() async => semester;
}

/// 没有当前学期（build 抛错 → provider 进 AsyncError，读不到 value）
class _MissingCurrent extends CurrentSemesterNotifier {
  @override
  Future<Semester> build() async => throw StateError('未找到当前学期');
}

/// 只负责把表单弹出来、结果交回测试的壳
class _FormHarness extends ConsumerWidget {
  const _FormHarness({required this.onResult, this.initial});

  final void Function(Semester?) onResult;
  final Semester? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 先 watch 一次：让 currentSemesterProvider 在表单打开之前就完成首次 async
    // build（表单 initState 里是 read，届时必须已经拿到值，与真实 App 一致——
    // 主页一直在 watch 它，点 ＋ 时早已就绪）
    if (ref.watch(currentSemesterProvider).isLoading) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            onResult(await showSemesterFormDialog(context, initial: initial));
          },
          child: const Text('打开表单'),
        ),
      ),
    );
  }
}

/// 打开表单。[current] 为 null 表示「读不到当前学期」。
Future<void> pumpForm(
  WidgetTester tester, {
  required Semester? current,
  Semester? initial,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSemesterProvider.overrideWith(
          () => current == null ? _MissingCurrent() : _FixedCurrent(current),
        ),
      ],
      child: MaterialApp(
        // 日历用中文文案（取消 / 确定），与 App 内实际表现一致
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: _FormHarness(initial: initial, onResult: (_) {}),
      ),
    ),
  );
  // 两帧：第一帧 provider 起 async build，第二帧结果落到 state 上
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('打开表单'));
  await tester.pumpAndSettle();
}

/// 整页 pump 主页外壳（沿用 week_jumper_outside_tap_test 的模式：
/// FFI 内存库 + PackageInfo 打桩 + 锁时钟到周一 + 阻断网络）。
Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.runAsync(() async {
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: HomeShell())),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      },
      createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
    );
  });
  await tester.pump();
  await pumpUntil(tester, find.byIcon(Icons.add_outlined));
}

/// 反复「真实等待 + 推进假时钟」直到目标出现（学期 provider 首帧是真实异步读库）
Future<void> pumpUntil(WidgetTester tester, Finder finder, {int rounds = 25}) async {
  for (var i = 0; i < rounds; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// 收尾：让 sqflite 的锁等待定时器（10s）在假时钟上跑完，否则测试结束时
/// 会报「A Timer is still pending even after the widget tree was disposed」
Future<void> settlePendingDbTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 60));
}

/// 点一个可能触发真实异步读写的控件：每轮 pump + 一段真实时间，
/// 带 [waitFor] 时目标一出现就停。
Future<void> tapAndSettle(
  WidgetTester tester,
  Finder finder, {
  Finder? waitFor,
}) async {
  await tester.tap(finder);
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (waitFor != null && waitFor.evaluate().isNotEmpty) break;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  }
  await tester.pump(const Duration(milliseconds: 500));
}
