import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';

/// 设置首页测试（2.0.5，WB_SPEC_205 第 1 节；2.0.6 第 1 节去重复小标题；
/// 2.0.7 第 3 节分隔线；2.0.8 第 3 节删聊天入口；
/// 2.1.0 WB_SPEC_212 第 3/4 节调整入口集合；2.1.3 WB_SPEC_214 第 1 节删除
/// 页面底部那个「解锁后才出现」的入口行）
///
/// 首页只留入口行（图标 + 名称 + 一行副标题 + ›），断言：
/// 1. 入口行齐全（含「菜单管理」+「更多工具」分组）；
/// 2. 首页**不存在** Switch / Slider（开关只在菜单管理子页，首页不放开关）；
/// 3. 入口集合固定：行数、图标都与 2.1.3 定版一致，底部不会因任何开关多出一行；
/// 4. 「更多工具」分组全量平铺六项，右侧灰字标注菜单显隐（与配置实时一致）。
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

  testWidgets('设置首页：入口行齐全 + 入口集合固定 + 无 Switch/Slider', (tester) async {
    await pumpPage(tester);

    // 入口行标题（2.1.3 定版：9 个分类行 + 「更多工具」分组标题 + 6 个工具行）
    const entries = [
      '学期设置',
      '外观',
      '提醒',
      '课表工具',
      '菜单管理',
      '更多工具',
      '学期与数据',
      '权限',
      '关于小马课表',
      '桌面小组件',
    ];
    for (final e in entries) {
      expect(find.text(e), findsOneWidget, reason: '入口「$e」应出现在设置首页');
    }

    // 2.1.3：入口集合固定——9 个分类行 + 云同步行 + 6 个工具行 = 16 行，
    // 底部不会再多出第 17 行（此前那一行是解锁后才渲染的）
    expect(find.byType(ListTile), findsNWidgets(16));
    // 那一行专属的图标也不该出现（比找文案更抗改文案）
    expect(find.byIcon(Icons.build_outlined), findsNothing);

    // 各分类入口行的一行副标题（证明入口行存在）
    expect(find.text('学期名称、开学日期、总周数'), findsOneWidget);
    expect(find.text('主题、实时预览、格子外观、课程配色与显示字体'), findsOneWidget);
    expect(find.text('导入课表、学期管理、备份恢复、导出 ICS、数据管理'), findsOneWidget);
    expect(find.text('通知、精确闹钟、电池优化'), findsOneWidget);
    expect(find.text('今日课程小组件的添加说明'), findsOneWidget);

    // 首页不出现任何开关 / 滑杆（开关只在菜单管理子页）
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('更多工具：全量平铺六项，默认全部「已在菜单显示」', (tester) async {
    await pumpPage(tester);

    const tools = [
      '课程搜索',
      '空闲时段',
      '导出课表图片',
      '学期管理',
      '考试倒计时',
      '导入课表',
    ];
    for (final t in tools) {
      expect(find.text(t), findsOneWidget, reason: '更多工具应平铺「$t」');
    }
    // 默认六项全显示
    expect(find.text('已在菜单显示'), findsNWidgets(6));
    expect(find.text('已在菜单隐藏'), findsNothing);
  });

  testWidgets('更多工具：某项在菜单隐藏后，兜底行标注「已在菜单隐藏」', (tester) async {
    // 先种入「课程搜索」已隐藏的菜单配置，再渲染设置页
    await tester.runAsync(() async {
      await Dao.instance.setSetting(
        'home_menu_config',
        '[{"id":"course-search","visible":false,"order":0}]',
      );
    });
    await pumpPage(tester);

    expect(find.text('已在菜单隐藏'), findsOneWidget);
    expect(find.text('已在菜单显示'), findsNWidgets(5));
    // 课程搜索这一行仍在（兜底入口不因隐藏而消失）
    expect(find.text('课程搜索'), findsOneWidget);
  });
}
