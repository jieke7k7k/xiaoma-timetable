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
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 进主页整页课表能显示完全（WB_SPEC_216 第 2 节）。
///
/// 判定标准不是目测，而是几何断言：把主页渲染出来、滚到最底，然后比较
/// 「网格内容底边」与「底部栏顶边」——
/// - 内容底边必须 **恰好等于栏顶**（留白 == 栏高 + 安全区，既不被压住也不空一大截）；
/// - 最后一节（最晚一节）的节次文字必须完整落在栏顶之上、且在视口内。
///
/// 两种栏状态各跑一遍：标签栏（默认）/ 关栏；底部有 34 安全区时再跑
/// 一遍标签栏，验证安全区只加一次、口径仍是「栏高 + 安全区」。
///
/// 另有一组「自适应一屏」断言：开启 autoFitHeight 时整周恰好一屏，
/// 纵向滚动体的 maxScrollExtent 必须为 0（2.1.7 同版本修复：以前按整高均分
/// 再加 64 留白，最后一行总要滚一下才看得到）。
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
      version: '2.1.5',
      buildNumber: '30',
      buildSignature: '',
    );
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    // 锁周日时钟，避免周日弹窗 barrier 干扰滚动与点击
    sundayDialogNow = () => monday;
    String two(int v) => v.toString().padLeft(2, '0');
    final start = '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    final existing = await Dao.instance.getCurrentSemester();
    if (existing == null) {
      await Dao.instance.insertSemester(
        Semester(name: '测试学期', startDate: start, isCurrent: true),
      );
    } else {
      await Dao.instance.updateSemester(existing.copyWith(startDate: start));
    }
  });

  tearDown(() async {
    sundayDialogNow = DateTime.now;
    await db.close();
  });

  /// 手机尺寸视口（逻辑 390×844）
  Future<void> pumpHome(
    WidgetTester tester, {
    required bool showBottomBar,
    bool autoFitHeight = false,
    double cellHeight = 96,
    double safeAreaBottom = 0,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (safeAreaBottom > 0) {
      // view.padding 是**物理像素**，而断言用的是逻辑像素：乘上设备像素比 3，
      // MediaQuery.padding.bottom 才是逻辑的 34
      tester.view.padding = FakeViewPadding(bottom: safeAreaBottom * 3.0);
      addTearDown(tester.view.resetPadding);
    }

    // 预置界面设置：滚动组关掉「行高自适应一屏」并把格高拉到上限，
    // 保证网格可滚（13 节 × 96 + 两条带子 ≈ 1296，远超一屏）；
    // 一屏组反过来开自适应，断言整周恰好一屏
    await tester.runAsync(
      () => Dao.instance.setSetting(
        'ui_settings',
        UiSettings(
          autoFitHeight: autoFitHeight,
          cellHeight: cellHeight,
          showBottomBar: showBottomBar,
        ).encode(),
      ),
    );

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
    // 等学期就绪、周视图渲出右上角菜单（加载态只有转圈）
    for (var i = 0; i < 25; i++) {
      if (find.byIcon(Icons.more_vert).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    // 再等网格滚动体渲出：右上角菜单出现只代表学期就绪，课程读库可能
    // 还在排队（多文件并行跑时数据库会被隔壁文件占住），网格体没出来
    // 就量留白/滚到底会取到空。2026-11-05 常驻双页后启动读库更多，
    // 这个等待尤其必要。
    for (var i = 0; i < 25; i++) {
      final grid = find.descendant(
        of: find.byType(WeekViewPage),
        matching: find.byType(SingleChildScrollView),
      );
      if (grid.evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// 把纵向滚动体滚到最底（横向 PageView 的 Scrollable 不算）
  ///
  /// 2026-11-05：默认动效是双页常驻，设置页的 ListView 也在树里（同样是
  /// 纵向 Scrollable），须把查找限定在 WeekViewPage 内，否则会误取到
  /// 设置页的列表（其 maxScrollExtent 可能为 0）。
  Future<void> scrollToBottom(WidgetTester tester) async {
    final vertical = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byType(WeekViewPage),
            matching: find.byType(Scrollable),
          ),
        )
        .firstWhere((s) => s.axisDirection == AxisDirection.down);
    expect(vertical.position.maxScrollExtent, greaterThan(0), reason: '网格必须可滚动');
    vertical.position.jumpTo(vertical.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// 网格滚动视图（视口）在屏幕上的矩形与它的底部留白
  ({Rect viewport, double inset, Rect? bar}) gridMetrics(WidgetTester tester) {
    final viewportFinder = find.byType(SingleChildScrollView).first;
    final viewport = tester.getRect(viewportFinder);
    final sv = tester.widget<SingleChildScrollView>(viewportFinder);
    final padding = sv.padding! as EdgeInsets;
    final tabBar = find.byType(HomeTabBar);
    Rect? bar;
    if (tabBar.evaluate().isNotEmpty) bar = tester.getRect(tabBar);
    return (viewport: viewport, inset: padding.bottom, bar: bar);
  }

  /// 最后一节的节次号（时间轴上最晚一节的编号，如 13）。
  ///
  /// 真实 FFI 读库必须放进 runAsync：testWidgets 的假时钟不会推进真实 IO，
  /// 直接 await 会把用例挂死。
  Future<int> lastSection(WidgetTester tester) async {
    final last = await tester.runAsync<int>(() async {
      final slots = await Dao.instance.getTimeSlots();
      return slots.map((s) => s.section).reduce((a, b) => a > b ? a : b);
    });
    return last ?? 0;
  }

  testWidgets('标签栏（默认）：滚动到底最后一节完整露出，留白 == 栏高 + 安全区', (
    tester,
  ) async {
    await pumpHome(tester, showBottomBar: true);
    expect(find.byType(HomeTabBar), findsOneWidget);

    final lastNo = await lastSection(tester);
    await scrollToBottom(tester);
    final m = gridMetrics(tester);
    expect(m.bar, isNotNull);
    // 留白口径：64（栏高） + 0（无安全区）
    expect(m.inset, kBottomBarTabHeight);
    expect(m.inset, bottomBarGridBottomPadding(0, showBottomBar: true));
    // 内容底边恰好落在栏顶：不遮半行、也不空一截
    final contentBottom = m.viewport.bottom - m.inset;
    expect(contentBottom, closeTo(m.bar!.top, 1.0));
    expect(contentBottom, lessThan(m.viewport.bottom));

    // 最后一节的节次文字完整可见（在栏上方、在视口内）
    final last = tester.getRect(find.text('$lastNo').first);
    expect(last.top, greaterThanOrEqualTo(0));
    expect(last.bottom, lessThanOrEqualTo(m.bar!.top + 0.5));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关栏：滚动到底最后一节完整露出，留白 16（不被任何栏遮挡）', (tester) async {
    await pumpHome(tester, showBottomBar: false);
    expect(find.byType(HomeTabBar), findsNothing);

    final lastNo = await lastSection(tester);
    await scrollToBottom(tester);
    final m = gridMetrics(tester);
    expect(m.bar, isNull);
    expect(m.inset, kBottomBarHiddenInset);
    expect(m.inset, 16);
    final contentBottom = m.viewport.bottom - m.inset;
    expect(contentBottom, closeTo(m.viewport.bottom - 16, 1.0));
    final last = tester.getRect(find.text('$lastNo').first);
    expect(last.top, greaterThanOrEqualTo(0));
    expect(last.bottom, lessThanOrEqualTo(m.viewport.bottom - 16 + 0.5));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('带底部安全区 34：标签栏留白 == 64 + 34，安全区只加一次', (tester) async {
    await pumpHome(tester, showBottomBar: true, safeAreaBottom: 34);
    final barRect = tester.getRect(find.byType(HomeTabBar));
    expect(barRect.height, kBottomBarTabHeight + 34, reason: '栏体自己吃掉安全区');

    final lastNo = await lastSection(tester);
    await scrollToBottom(tester);
    final m = gridMetrics(tester);
    expect(m.inset, barRect.height, reason: '留白 == 栏高（含安全区）');
    expect(m.inset, bottomBarGridBottomPadding(34, showBottomBar: true));
    final contentBottom = m.viewport.bottom - m.inset;
    expect(contentBottom, closeTo(m.bar!.top, 1.0));
    final last = tester.getRect(find.text('$lastNo').first);
    expect(last.bottom, lessThanOrEqualTo(m.bar!.top + 0.5));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('自适应一屏：开栏时整周恰好一屏，纵向不用滚动', (tester) async {
    await pumpHome(tester, showBottomBar: true, autoFitHeight: true);
    expect(find.byType(HomeTabBar), findsOneWidget);

    // 2.1.7 同版本修复：行高先扣底栏留白再均分，整周总高 + 留白 == 视口高，
    // 纵向滚动体不可滚动；最后一节的节次文字完整在视口内、栏顶之上
    final vertical = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .firstWhere((s) => s.axisDirection == AxisDirection.down);
    expect(
      vertical.position.maxScrollExtent,
      0,
      reason: '整周恰好一屏：最后一行不用滚动就看得到',
    );
    final m = gridMetrics(tester);
    expect(m.inset, kBottomBarTabHeight);
    final lastNo = await lastSection(tester);
    final last = tester.getRect(find.text('$lastNo').first);
    expect(last.top, greaterThanOrEqualTo(0));
    expect(last.bottom, lessThanOrEqualTo(m.bar!.top + 0.5));

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });
}
