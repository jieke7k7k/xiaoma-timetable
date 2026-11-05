import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/services/sunday_dialog_service.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 周日收尾弹窗「一天一次」（WB_SPEC_215 第 1/3 节）。
///
/// 用户原话：「这个弹窗就算读过了，从设置界面切回主页还是有弹窗，不要这样。」
/// 根因：2.1.3 只靠 `_WeekViewPageState._sundayDialogShown` 布尔值防重复，
/// 主页与设置之间切换时壳内视图被换掉、State 重建，标记丢失。
/// 2.1.4 改为把「已读日期」落到 app_settings（键 sunday_dialog_shown_date）。
///
/// 覆盖：
/// 1. 纯判定：周日 + 本周 + 今天没记过才弹；
/// 2. 持久化：标记后同一天（含新实例＝杀进程重进/页面重建）不再弹，下个周日重新弹；
/// 3. 页面行为：首次进入弹、点「知道了」后切设置 Tab 再切回不弹、
///    页面重建不弹、「看下周」仍跳周、库里只留最近一次已读日期。
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
      version: '2.1.4',
      buildNumber: '29',
      buildSignature: '',
    );
  });

  tearDown(() async {
    // 时钟必须复原，否则会影响其它测试文件（同进程内共享顶层变量）
    sundayDialogNow = DateTime.now;
    await db.close();
  });

  // 2026-11-01 是周日（用户反馈当天）；2026-11-08 是下一个周日
  final sunday = DateTime(2026, 11, 1, 10, 30);
  final nextSunday = DateTime(2026, 11, 8, 9, 0);

  group('isSundayDialogDue：纯判定（周日 + 本周 + 今天没记过）', () {
    test('周日 + 看本周 + 从未弹过 → 弹', () {
      expect(
        isSundayDialogDue(now: sunday, displayWeek: 3, todayWeek: 3),
        isTrue,
      );
    });

    test('非周日一律不弹（即使从未弹过）', () {
      final monday = DateTime(2026, 11, 2, 10);
      expect(
        isSundayDialogDue(now: monday, displayWeek: 3, todayWeek: 3),
        isFalse,
      );
      final saturday = DateTime(2026, 10, 31, 10);
      expect(
        isSundayDialogDue(now: saturday, displayWeek: 3, todayWeek: 3),
        isFalse,
      );
    });

    test('周日但翻到了别的周（非本周）→ 不弹', () {
      expect(
        isSundayDialogDue(now: sunday, displayWeek: 4, todayWeek: 3),
        isFalse,
      );
    });

    test('同一个周日已记过已读 → 不弹', () {
      expect(
        isSundayDialogDue(
          now: sunday,
          displayWeek: 3,
          todayWeek: 3,
          shownDate: '2026-11-01',
        ),
        isFalse,
      );
    });

    test('同一天的不同时刻算同一天（凌晨与深夜都不重弹）', () {
      final earlyMorning = DateTime(2026, 11, 1, 0, 5);
      final lateNight = DateTime(2026, 11, 1, 23, 55);
      expect(sundayDialogDateStamp(earlyMorning), '2026-11-01');
      expect(sundayDialogDateStamp(lateNight), '2026-11-01');
      expect(
        isSundayDialogDue(
          now: lateNight,
          displayWeek: 3,
          todayWeek: 3,
          shownDate: '2026-11-01',
        ),
        isFalse,
      );
    });

    test('到了下个周日（日期变了）→ 重新弹一次', () {
      expect(
        isSundayDialogDue(
          now: nextSunday,
          displayWeek: 4,
          todayWeek: 4,
          shownDate: '2026-11-01',
        ),
        isTrue,
      );
    });

    test('日期戳补零：2026-01-04（周日）不会被写成 2026-1-4', () {
      expect(sundayDialogDateStamp(DateTime(2026, 1, 4)), '2026-01-04');
    });
  });

  group('SundayDialogGate：已读日期落库（app_settings）', () {
    test('未读 → 弹；标记已读后同一天不再弹（新实例＝杀进程重进）', () async {
      final gate = SundayDialogGate(clock: () => sunday);
      expect(await gate.shouldShow(displayWeek: 3, todayWeek: 3), isTrue);

      await gate.markShown();
      expect(
        await Dao.instance.getSetting(kSundayDialogShownDateKey),
        '2026-11-01',
        reason: '已读日期必须落到 app_settings，而不是只放内存',
      );

      // 新实例：模拟页面重建 / 杀进程重进——读的是库里的日期，仍然不弹
      final rebuilt = SundayDialogGate(clock: () => sunday);
      expect(await rebuilt.shouldShow(displayWeek: 3, todayWeek: 3), isFalse);

      // 同一天更晚的时刻（例如从设置页切回来）也不弹
      final later = SundayDialogGate(
        clock: () => DateTime(2026, 11, 1, 22, 40),
      );
      expect(await later.shouldShow(displayWeek: 3, todayWeek: 3), isFalse);
    });

    test('下个周日重新弹：日期戳对不上历史已读日期', () async {
      final gate = SundayDialogGate(clock: () => sunday);
      await gate.markShown();

      final nextWeek = SundayDialogGate(clock: () => nextSunday);
      expect(await nextWeek.shouldShow(displayWeek: 4, todayWeek: 4), isTrue);
      // 再标记后覆盖为新的日期，库里只留最近一次
      await nextWeek.markShown();
      expect(
        await Dao.instance.getSetting(kSundayDialogShownDateKey),
        '2026-11-08',
      );
    });

    test('非周日 / 非本周不弹，且不写库', () async {
      final monday = DateTime(2026, 11, 2, 10);
      final gate = SundayDialogGate(clock: () => monday);
      expect(await gate.shouldShow(displayWeek: 3, todayWeek: 3), isFalse);
      expect(await Dao.instance.getSetting(kSundayDialogShownDateKey), isNull);

      final offWeek = SundayDialogGate(clock: () => sunday);
      expect(await offWeek.shouldShow(displayWeek: 5, todayWeek: 3), isFalse);
      expect(await Dao.instance.getSetting(kSundayDialogShownDateKey), isNull);
    });
  });

  // ---------- 页面行为（真实 HomeShell + FFI 内存库） ----------

  /// 造一个「本周就是第 1 周」的当前学期：开学日期取真实今天的周一，
  /// 这样无论哪天跑测试，displayWeek 都等于 todayWeek，弹窗条件只受注入时钟影响。
  Future<void> seedCurrentSemester(WidgetTester tester) async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    String two(int v) => v.toString().padLeft(2, '0');
    final start =
        '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    // 真实 FFI 写库必须放在 runAsync 里跑：testWidgets 的假时钟不推进真实 IO。
    // 注意改的是已有的当前学期：建库时 createSchema 已经写入一条 isCurrent=1 的
    // 默认学期，再插一条新的会让 current 留在默认那条上，周次算不对。
    await tester.runAsync(() async {
      final existing = await Dao.instance.getCurrentSemester();
      if (existing == null) {
        await Dao.instance.insertSemester(
          Semester(
            name: '测试学期',
            startDate: start,
            totalWeeks: 20,
            isCurrent: true,
          ),
        );
      } else {
        await Dao.instance.updateSemester(
          existing.copyWith(startDate: start, totalWeeks: 20),
        );
      }
    });
  }

  /// 反复「真实等待 + 推进假时钟」直到目标出现（异步读库 + postFrame 弹窗）
  Future<bool> waitFor(
    WidgetTester tester,
    Finder finder, {
    int rounds = 25,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) return true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    return finder.evaluate().isNotEmpty;
  }

  Future<void> pumpHome(WidgetTester tester) async {
    // 手机尺寸视口（逻辑 390×844）：默认 800×600 的测试窗口比真机扁，
    // 自适应一屏行高被压得很小，节次栏文字会挤出几点溢出的假报错。
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
          // 让启动联动里的真实 FFI 数据库操作跑完并释放锁定时器
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    await tester.pump();
  }

  final dialogTitle = find.text('今天是周日');

  testWidgets('今天周日且正看本周：首次进入弹一次', (tester) async {
    sundayDialogNow = () => sunday;
    await seedCurrentSemester(tester);
    await pumpHome(tester);

    expect(await waitFor(tester, dialogTitle), isTrue, reason: '周日首次进入应弹出');
    expect(find.text('今天是周日，本周已结束'), findsOneWidget);
    // 未到最后一周（默认 20 周）→ 有「看下周」
    expect(find.text('看下周'), findsOneWidget);
    expect(find.text('知道了'), findsOneWidget);
    // 弹出即记已读
    expect(
      await tester.runAsync(
        () => Dao.instance.getSetting(kSundayDialogShownDateKey),
      ),
      '2026-11-01',
    );

    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点「知道了」后切设置 Tab 再切回主页：不再弹（本轮修的 bug）', (tester) async {
    sundayDialogNow = () => sunday;
    await seedCurrentSemester(tester);
    await pumpHome(tester);

    expect(await waitFor(tester, dialogTitle), isTrue);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(dialogTitle, findsNothing);

    // 切到设置（底部栏「设置」键 → 壳内设置根页；2026-11-05 起默认动效是
    // 双页常驻，WeekViewPage 不再被换掉销毁、而是常驻在树里——弹窗仍不该重弹）
    // 按栏键点：设置页 AppBar 标题「设置」也在树里，按文字点会命中两个
    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 切回课表（常驻页重新显现，State 是同一实例）
    await tester.tap(find.byKey(kHomeTabBarScheduleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 给足机会让它「重新弹」——现在不该再弹
    expect(
      await waitFor(tester, dialogTitle, rounds: 10),
      isFalse,
      reason: '同一个周日已经读过，切 Tab 回来不得再弹',
    );

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同周日内页面整体重建（等价杀进程重进课表）：不再弹', (tester) async {
    sundayDialogNow = () => sunday;
    await seedCurrentSemester(tester);
    await pumpHome(tester);

    expect(await waitFor(tester, dialogTitle), isTrue);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 卸载整个壳，再重新挂一次（新 State + 新 ProviderScope 读取同一份库）
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
    await pumpHome(tester);

    expect(
      await waitFor(tester, dialogTitle, rounds: 10),
      isFalse,
      reason: '已读日期在库里，重建页面（等同重进 App）不得再弹',
    );

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('到了下个周日：重新弹一次', (tester) async {
    sundayDialogNow = () => sunday;
    await seedCurrentSemester(tester);
    await pumpHome(tester);
    expect(await waitFor(tester, dialogTitle), isTrue);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 把时钟拨到下一个周日，重新挂壳（库里还留着上个周日的日期）
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
    sundayDialogNow = () => nextSunday;
    await pumpHome(tester);

    expect(
      await waitFor(tester, dialogTitle),
      isTrue,
      reason: '新的周日应重新弹一次',
    );

    await tester.tap(find.text('知道了'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('「看下周」仍跳周：关闭弹窗并翻到下一周', (tester) async {
    sundayDialogNow = () => sunday;
    await seedCurrentSemester(tester);
    await pumpHome(tester);

    expect(await waitFor(tester, dialogTitle), isTrue);
    await tester.tap(find.text('看下周'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(dialogTitle, findsNothing, reason: '看下周也要关掉弹窗');
    expect(
      find.text('第 2 周'),
      findsOneWidget,
      reason: '「看下周」仍要跳到下一周（行为不变）',
    );

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });
}
