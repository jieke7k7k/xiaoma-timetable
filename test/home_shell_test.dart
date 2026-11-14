import 'dart:io';

import 'package:animations/animations.dart';
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
import 'package:xiaoma_timetable/ui/shell_transition.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 底部栏（只有新标签栏一种形态）的壳层测试（WB_SPEC_215 第 2/3 节；WB_SPEC_216 第 1 节）。
///
/// 2.1.7 同版本修复：胶囊形态整体删除，底部栏只有「图标+文字标签栏」
/// [HomeTabBar]；旧库里的 `bottomBarStyle` 字段整体忽略：
/// 1. 默认渲染：WeekViewPage + 标签栏（HomeTabBar），恒两键［课表｜设置］；
/// 2. 点「设置」键切到壳内设置根页，且无左上角返回箭头；
/// 3. 关栏→再开栏恢复标签栏；
/// 4. 旧库里残留的 `bottomBarStyle`（`capsule` / `bar`）读取后直接忽略，
///    仍出标签栏，不会无栏、不会崩；
/// 5. 关栏（showBottomBar=false）时不出栏，右上角菜单仍能进设置（带返回箭头）。
///
/// HomeShell 的启动联动 / WeekViewPage 的公告检查会走平台通道与网络，这里用
/// PackageInfo 打桩 + HttpOverrides 阻断网络，并把首帧放进 runAsync 里让真实
/// 的 FFI 数据库操作跑完（否则 sqflite 的锁警告定时器会挂在假时钟上导致
/// 「Timer is still pending」）。断言只针对「主页结构」，不依赖这些侧效结果。
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
      version: '2.1.6',
      buildNumber: '31',
      buildSignature: '',
    );
    // 把当前学期改成本周开学：开学日期取真实今天的周一，保证「本周 = 第 1 周」，
    // 周视图能正常渲染出课表（否则停在加载态）。建库时 createSchema 已写入一条
    // isCurrent=1 的默认学期，这里改它而不是再插一条，避免 current 指错。
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    // 复审 P2-1：把周日时钟锁到本周一，避免周日跑测试时真实周日弹窗遮挡底部栏
    // 导致点设置键等用例命中弹窗 barrier（日期依赖 flaky）。
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

  /// 反复「真实等待 + 推进假时钟」直到目标出现：学期/课程等 provider 首帧是
  /// 真实异步读库，单次 pump 拿不到数据（周视图会停在加载态，AppBar 还没出来）。
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int rounds = 25,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpHome(WidgetTester tester) async {
    // 手机尺寸视口（逻辑 390×844）：默认 800×600 的测试窗口比真机扁，
    // 自适应一屏会把行高压得很小，节次栏文字会挤出几点溢出的假报错。
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                home: const HomeShell(),
                routes: {'/settings': _settingsRoute},
              ),
            ),
          );
          await tester.pump();
          // 让启动联动里的真实 FFI 数据库操作在这里跑完并释放锁定时器
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    await tester.pump();
    // 等学期就绪、周视图真正渲染出顶部栏（加载态只有转圈，没有 AppBar 动作）
    await pumpUntil(tester, find.byIcon(Icons.more_vert));
  }

  /// 2.5.0（WB_SPEC_233 §6）起底部栏默认关：验证壳/标签栏的用例必须把开关
  /// 显式写进库；同时立一次性迁移标志，免得启动时被迁移覆盖回新默认。
  Future<void> seedUi(WidgetTester tester, UiSettings settings) async {
    await tester.runAsync(() async {
      await Dao.instance.setSetting('ui_settings', settings.encode());
      await Dao.instance.setSetting(UiSettingsNotifier.kDefaultsMigratedKey, '1');
    });
  }

  testWidgets('默认形态＝标签栏：WeekViewPage + HomeTabBar 恒两键，无 IndexedStack/NavigationBar', (
    tester,
  ) async {
    await seedUi(tester, const UiSettings(showBottomBar: true));
    await pumpHome(tester);

    // 课表一级视图 + 标签栏都存在
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(HomeTabBar), findsOneWidget);
    // 三页签结构已删除（栏是自绘组件，不是系统底栏）
    expect(find.byType(IndexedStack), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // 栏里恰两键，无「主页」键，也没有 AI 键及其图标
    // （2026-11-05：默认动效是双页常驻，设置页 AppBar 标题「设置」也在树里，
    // 须把文字断言限定在栏内，否则会多命中常驻页的标题）
    expect(
      find.descendant(
        of: find.byType(HomeTabBar),
        matching: find.text('课表'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(HomeTabBar),
        matching: find.text('设置'),
      ),
      findsOneWidget,
    );
    expect(find.text('我的'), findsNothing);
    expect(find.text('主页'), findsNothing);
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
    expect(
      tester
          .widgetList<InkWell>(
            find.descendant(
              of: find.byType(HomeTabBar),
              matching: find.byType(InkWell),
            ),
          )
          .length,
      2,
      reason: '底部栏恒为［课表｜设置］两键',
    );
    // 标签栏：宽度撑满整宽、贴底
    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    expect(screenWidth, 390);
    expect(tester.getSize(find.byType(HomeTabBar)).width, screenWidth);
    final barRect = tester.getRect(find.byType(HomeTabBar));
    expect(barRect.bottom, 844, reason: '标签栏贴住屏幕底边');
    expect(barRect.height, 64);

    // 卸载主页，取消 WeekViewPage 的分钟级刷新定时器；
    // 先把假时钟拨过 10 秒，让读库时的锁警告定时器触发释放（否则报 Timer pending）
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点设置键切到壳内设置根页，且无返回箭头', (tester) async {
    await seedUi(tester, const UiSettings(showBottomBar: true));
    await pumpHome(tester);

    // 此刻栏上的「设置」键是切换入口（2026-11-05：默认动效双页常驻，
    // 设置页 AppBar 标题「设置」也在树里，须按栏键点，不能按文字点）
    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SettingsPage), findsOneWidget);
    // 壳内一级视图：设置根页不显示左上角返回箭头
    expect(find.byType(BackButton), findsNothing);
    // 设置在「设置」视图时，栏上设置格为选中态：主题 primary
    // （2026-11-05 按 Argon Q1/Q2 方案改为无框选中态：选中色跟主题走）
    final scheme = Theme.of(
      tester.element(find.byType(HomeTabBar)),
    ).colorScheme;
    final settingsIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(kHomeTabBarSettingsKey),
        matching: find.byType(Icon),
      ),
    );
    expect(settingsIcon.color, scheme.primary);

    // 设置页挂载触发的两次数据库查询各带一个 10 秒锁警告定时器（假时钟），
    // 测完前把假时钟拨过 10 秒让它们触发释放，否则 teardown 报 Timer pending。
    // 注意：runAsync 的真实延时拨不动假时钟，这里必须用 pump 推进假时间。
    await tester.pump(const Duration(seconds: 11));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关栏→再开栏：恢复标签栏', (tester) async {
    // 先关栏（模拟用户在外观页关掉底部栏）
    await seedUi(tester, const UiSettings(showBottomBar: false));
    await pumpHome(tester);
    expect(find.byType(HomeTabBar), findsNothing, reason: '关栏时不出任何栏');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    // 只把开关打开：应恢复标签栏
    await tester.runAsync(
      () => container
          .read(uiSettingsProvider.notifier)
          .updateWith((s) => s.copyWith(showBottomBar: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(HomeTabBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('旧 bottomBarStyle 字段整体忽略：有栏且是标签栏（升级残留不无栏、不崩）', (tester) async {
    // 模拟老用户升级：库里存着已删除的旧样式 id "capsule" / "bar"
    await tester.runAsync(() async {
      await Dao.instance.setSetting(
        'ui_settings',
        '{"showBottomBar": true, "bottomBarStyle": "capsule"}',
      );
      await Dao.instance.setSetting(UiSettingsNotifier.kDefaultsMigratedKey, '1');
    });
    final raw = await tester.runAsync(
      () => Dao.instance.getSetting('ui_settings'),
    );
    expect(
      UiSettings.fromEncoded(raw).showBottomBar,
      isTrue,
      reason: '旧样式字段忽略后，其它字段仍照常解码',
    );

    await pumpHome(tester);
    // 有栏，且是标签栏（不是「未知样式 → 无栏」）
    expect(find.byType(HomeTabBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('关栏：不出底部栏；右上角菜单仍能进设置（逻辑不变）', (tester) async {
    // 预置「底部栏关闭」，壳直接渲染单页课表（真实写库放 runAsync，假时钟不会推进真实 IO）
    await seedUi(tester, const UiSettings(showBottomBar: false));
    await pumpHome(tester);

    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(HomeTabBar), findsNothing);

    // 右上角「更多」菜单里的「设置」项（关栏时恢复显示）→ Push 设置页，有返回箭头
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('设置').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切换动效默认＝柔和（官方 FadeThrough），点设置切页、点课表切回', (tester) async {
    await seedUi(tester, const UiSettings(showBottomBar: true));
    await pumpHome(tester);

    // 默认动效是 B：PageTransitionSwitcher 挂载（旧页会卸载、不常驻保活）
    expect(find.byType(PageTransitionSwitcher), findsOneWidget);
    expect(find.byType(ParallaxShellBody), findsNothing);
    expect(find.byType(QuickFadeShellBody), findsNothing);
    expect(find.byType(WeekViewPage), findsOneWidget);

    // 课表 → 设置：220ms 内完成
    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsPage), findsOneWidget);
    // 设置 → 课表：反向同样 220ms（泵 300ms 必然已完成）
    await tester.tap(find.byKey(kHomeTabBarScheduleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WeekViewPage), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切换动效 A：灵动，双页常驻、切页正常', (tester) async {
    await seedUi(
      tester,
      const UiSettings(
        showBottomBar: true,
        shellTransitionStyle: ShellTransitionStyle.fadeThroughParallax,
      ),
    );
    await pumpHome(tester);

    // 动效 A：ParallaxShellBody 挂载，且两页都在树里（常驻保活，
    // 透明度 0 的那页也在，只是不显示——切页时 0 重建）
    expect(find.byType(ParallaxShellBody), findsOneWidget);
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(PageTransitionSwitcher), findsNothing);
    expect(find.byType(QuickFadeShellBody), findsNothing);

    // 课表 → 设置：240ms 内完成
    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsPage), findsOneWidget);
    // 设置 → 课表：反向同样 240ms（泵 300ms 必然已完成）
    await tester.tap(find.byKey(kHomeTabBarScheduleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WeekViewPage), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切换动效 B：柔和（官方 FadeThrough），切页正常', (tester) async {
    await seedUi(
      tester,
      const UiSettings(
        showBottomBar: true,
        shellTransitionStyle: ShellTransitionStyle.fadeThroughOfficial,
      ),
    );
    await pumpHome(tester);

    expect(find.byType(PageTransitionSwitcher), findsOneWidget);
    expect(find.byType(ParallaxShellBody), findsNothing);
    expect(find.byType(WeekViewPage), findsOneWidget);

    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切换动效 C：疾速，双页常驻、切页正常', (tester) async {
    await seedUi(
      tester,
      const UiSettings(
        showBottomBar: true,
        shellTransitionStyle: ShellTransitionStyle.quickFade,
      ),
    );
    await pumpHome(tester);

    expect(find.byType(QuickFadeShellBody), findsOneWidget);
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.byKey(kHomeTabBarScheduleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(WeekViewPage), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
  });
}

/// 测试用路由表里的设置页（关栏时从菜单 Push 进入：独立页面、有返回箭头）
Widget _settingsRoute(BuildContext context) => const SettingsPage();
