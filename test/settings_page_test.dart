import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';

/// 设置首页测试（2.1.7，WB_SPEC_218 第 ④ 节重组为三大分组）。
///
/// 2.1.7 起设置首页按 Argon 方案从「9 个分类行 + 更多工具平铺」收拢为
/// 「3 大分组 + AppBar ⋮ 更多菜单」，断言：
/// 1. 三个分组标题齐全（课表与学期 / 展示与桌面 / 数据与安全）；
/// 2. 六个入口行齐全（当前学期与周次、课表工具箱、外观与底栏、桌面小组件、
///    上课提醒、数据备份与换机）；
/// 3. 首页**不存在** Switch / Slider（开关只在子页，首页不放开关）；
/// 4. 入口集合固定：6 行入口，不再有「菜单管理」「权限」「关于」独立入口行，
///    也没有「更多工具」平铺——它们分别并入课表工具箱 / ⋮ 更多菜单。
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

  testWidgets('设置首页：三大分组 + 六入口齐全 + 无 Switch/Slider', (tester) async {
    await pumpPage(tester);

    // 三个分组标题（2.1.7 定版）
    const groups = ['课表与学期', '展示与桌面', '数据与安全'];
    for (final g in groups) {
      expect(find.text(g), findsOneWidget, reason: '分组「$g」应出现在设置首页');
    }

    // 六个入口行标题
    const entries = [
      '当前学期与周次',
      '课表工具箱',
      '外观与底栏',
      '桌面小组件',
      '上课提醒',
      '数据备份与换机',
    ];
    for (final e in entries) {
      expect(find.text(e), findsOneWidget, reason: '入口「$e」应出现在设置首页');
    }

    // 2.1.7：入口集合固定——6 行入口（权限自检条在测试环境权限查询失败时隐藏，
    // 不额外占一行；「菜单管理」「权限」「关于」独立入口行已移除）
    expect(find.byType(ListTile), findsNWidgets(6));

    // 首页不出现任何开关 / 滑杆（开关只在子页）
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(Slider), findsNothing);

    // 各入口行的固定副标题（证明入口行存在）
    expect(find.text('搜索、空闲时段、考试倒计时'), findsOneWidget);
    expect(find.text('今日课程小组件的添加说明'), findsOneWidget);
    expect(find.text('本地导出、恢复与换机迁移（纯本地存储）'), findsOneWidget);
  });

  testWidgets('设置首页：权限自检与关于移入 AppBar ⋮ 菜单（不再占列表行）', (tester) async {
    await pumpPage(tester);

    // ⋮ 更多菜单存在，且未展开时列表里没有「权限自检」「关于小马课表」行
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text('权限自检'), findsNothing);
    expect(find.text('关于小马课表'), findsNothing);

    // 展开 ⋮ 菜单后，两项出现在 PopupMenu 里（路由不变，仅入口位置变化）
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('权限自检'), findsOneWidget);
    expect(find.text('关于小马课表'), findsOneWidget);
  });
}
