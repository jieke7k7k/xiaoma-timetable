import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/services/permission_service.dart';
import 'package:xiaoma_timetable/utils/route_observer.dart';

/// 设置首页测试（2.1.7，WB_SPEC_218 第 ④ 节重组为三大分组）。
///
/// 2.1.7 起设置首页按 Argon 方案从「9 个分类行 + 更多工具平铺」收拢为
/// 「3 大分组」，WB_SPEC_256 §3.2 起顶栏单项 ⋮ 菜单移除，
/// 「关于小马课表」下沉为「数据与安全」组最底部的标准入口行，断言：
/// 1. 三个分组标题齐全（课表与学期 / 展示与桌面 / 数据与安全）；
/// 2. 九个入口行齐全（当前学期与周次、课表工具箱、节次时间设置、外观与底栏、
///    桌面小组件、上课提醒、数据备份与换机、权限自检、关于小马课表）；
/// 3. 首页**不存在** Switch / Slider（开关只在子页，首页不放开关）；
/// 4. 入口集合：WB_SPEC_219 前为 6 行，现于「课表与学期」组追加节次时间设置
///    共 7 行；WB_SPEC_228 §8 再把权限自检移入，共 8 行；
///    WB_SPEC_256 §3.2 再把关于下沉为底部入口行，共 9 行。
///    不再有「菜单管理」独立入口行，也没有「更多工具」平铺——它们分别并入
///    课表工具箱；顶栏不再有 ⋮ 更多菜单。
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
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // 拉高测试画布，让懒加载的 ListView 把全部入口都建出来再断言
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsPage())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('设置首页：三大分组 + 九入口齐全 + 无 Switch/Slider', (tester) async {
    await pumpPage(tester);

    // 三个分组标题（2.1.7 定版）
    const groups = ['课表与学期', '展示与桌面', '数据与安全'];
    for (final g in groups) {
      expect(find.text(g), findsOneWidget, reason: '分组「$g」应出现在设置首页');
    }

    // 九个入口行标题（WB_SPEC_228 §8 追加权限自检；
    // WB_SPEC_256 §3.2 再把关于下沉为「数据与安全」组底部入口行）
    const entries = [
      '当前学期与周次',
      '课表工具箱',
      '节次时间设置',
      '外观与底栏',
      '桌面小组件',
      '上课提醒',
      '数据备份与换机',
      '权限自检',
      '关于小马课表',
    ];
    for (final e in entries) {
      expect(find.text(e), findsOneWidget, reason: '入口「$e」应出现在设置首页');
    }

    // 2.1.7 三大分组与入口行不动；WB_SPEC_219 在「课表与学期」组追加
    // 「节次时间设置」一行；WB_SPEC_228 §8 再把权限自检移入，共 8 行；
    // WB_SPEC_256 §3.2 再把关于下沉为底部入口行，共 9 行。
    expect(find.byType(ListTile), findsNWidgets(9));

    // 首页不出现任何开关 / 滑杆（开关只在子页）
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(Slider), findsNothing);

    // 各入口行的固定副标题（证明入口行存在）
    expect(find.text('课程搜索、空闲时段、考试倒计时'), findsOneWidget);
    expect(find.text('今日课程小组件添加说明'), findsOneWidget);
    expect(find.text('本地导出、恢复与换机迁移'), findsOneWidget);
    expect(find.text('版本信息、检查更新、公告与使用帮助'), findsOneWidget);
  });

  testWidgets('节次时间设置入口从外观页移入设置首页「课表与学期」组（WB_SPEC_219）', (tester) async {
    await pumpPage(tester);

    expect(find.text('节次时间设置'), findsOneWidget);
    expect(find.text('自定义每节课上下课时间'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);

    // 位置：落在「课表与学期」标题之后、「展示与桌面」标题之前 → 第 1 组
    final yGroup = tester.getTopLeft(find.text('课表与学期')).dy;
    final yNext = tester.getTopLeft(find.text('展示与桌面')).dy;
    final yEntry = tester.getTopLeft(find.text('节次时间设置')).dy;
    expect(yEntry, greaterThan(yGroup), reason: '入口应在「课表与学期」标题下方');
    expect(yEntry, lessThan(yNext), reason: '入口应在「展示与桌面」标题上方');

    // 三大分组与其余入口保持不动
    expect(find.text('展示与桌面'), findsOneWidget);
    expect(find.text('数据与安全'), findsOneWidget);
    expect(find.text('外观与底栏'), findsOneWidget);
    expect(find.text('课表工具箱'), findsOneWidget);
  });

  testWidgets('设置首页：权限自检移入「数据与安全」组，关于下沉为底部入口行（WB_SPEC_256 §3.2）',
      (tester) async {
    await pumpPage(tester);

    // 权限自检仍是首页入口行；「关于小马课表」不再藏在 ⋮ 菜单里，
    // 而是「数据与安全」组最底部的标准入口行
    expect(find.text('权限自检'), findsOneWidget);
    expect(find.text('关于小马课表'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing,
        reason: '顶栏单项 ⋮ 菜单已移除，不应再有 more_vert');

    // 位置：关于在权限自检下方，是本组最后一行
    final yPerm = tester.getTopLeft(find.text('权限自检')).dy;
    final yAbout = tester.getTopLeft(find.text('关于小马课表')).dy;
    expect(yAbout, greaterThan(yPerm), reason: '关于应在权限自检下方');
    expect(find.text('版本信息、检查更新、公告与使用帮助'), findsOneWidget);
  });

  // WB_SPEC_256 §3.2：设置页顶栏单项 ⋮ 菜单已移除，「⋮ 菜单：打开后不盖住顶栏
  // （复查 Bug 2）」测试随之删除——菜单不存在了，定位约束无从谈起。
  // popupMenuTheme 全局外壳约束仍由主页与学期行菜单的测试覆盖。

  group('上课提醒徽标三态（复查 Bug 3/7）', () {
    late _FakeReminderNotifier fake;

    Future<void> pumpBadgePage(WidgetTester tester) async {
      fake = _FakeReminderNotifier();
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() => PermissionService.debugStatusOverride = null);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reminderSettingsProvider.overrideWith(() => fake),
            ],
            child: MaterialApp(
              navigatorObservers: [appRouteObserver],
              home: const SettingsPage(),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    const missing = PermissionSnapshot(
      notification: false,
      exactAlarm: true,
      battery: true,
    );
    const granted = PermissionSnapshot(
      notification: true,
      exactAlarm: true,
      battery: true,
    );

    testWidgets('提醒没开不显示；开了且缺权限出现；补授权后回来消失', (tester) async {
      PermissionService.debugStatusOverride = () async => missing;
      await pumpBadgePage(tester);

      // 提醒没开：不检查、不显示
      expect(find.text('待完善'), findsNothing);

      // 开提醒 → 重查 → 缺权限 → 徽标出现
      fake.setEnabledForTest(true);
      await tester.pumpAndSettle();
      expect(find.text('待完善'), findsOneWidget);

      // 补授权后应用恢复前台 → 重查 → 徽标消失
      PermissionService.debugStatusOverride = () async => granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('待完善'), findsNothing);
    });

    testWidgets('查询失败不锁死：失败后不显示，恢复后重查出现', (tester) async {
      PermissionService.debugStatusOverride = () async =>
          throw Exception('通道异常');
      await pumpBadgePage(tester);

      fake.setEnabledForTest(true);
      await tester.pumpAndSettle();
      // 查询失败按无异常处理，不闪退也不显示
      expect(find.text('待完善'), findsNothing);

      // 通道恢复后重查：徽标出现（没被失败锁死）
      PermissionService.debugStatusOverride = () async => missing;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('待完善'), findsOneWidget);
    });

    testWidgets('从提醒设置子页回来重查（didPopNext）', (tester) async {
      PermissionService.debugStatusOverride = () async => missing;
      await pumpBadgePage(tester);

      fake.setEnabledForTest(true);
      await tester.pumpAndSettle();
      expect(find.text('待完善'), findsOneWidget);

      // 进提醒设置子页（模拟），期间补了授权，再回来
      final element = tester.element(find.byType(SettingsPage));
      Navigator.of(element).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('提醒设置子页'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('提醒设置子页'), findsOneWidget);
      PermissionService.debugStatusOverride = () async => granted;
      Navigator.of(element).pop();
      await tester.pumpAndSettle();

      expect(find.text('提醒设置子页'), findsNothing);
      expect(find.text('待完善'), findsNothing,
          reason: '从子页回来应重查，补授权后徽标消失');
    });
  });
}

/// 提醒设置替身：测试里直接改开关状态，绕开真实落库与重排
class _FakeReminderNotifier extends ReminderSettingsNotifier {
  ReminderSettings value =
      const ReminderSettings(enabled: false, advanceMinutes: 15);

  @override
  Future<ReminderSettings> build() async => value;

  void setEnabledForTest(bool v) {
    value = value.copyWith(enabled: v);
    state = AsyncData(value);
  }
}
