import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/pages/course_tools_page.dart';
import 'package:xiaoma_timetable/pages/import_page.dart';
import 'package:xiaoma_timetable/pages/semester_manage_page.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';

import 'helpers/pump_helpers.dart';

/// WB_SPEC_257：弹出菜单按钮顺序统一（Widget 测试）
///
/// 覆盖：
/// 1. 学期管理页非当前学期行 ⋮ 菜单顺序：切换到该学期 < 编辑学期 < 删除该学期；
/// 2. 主页顶栏 ⋮ 菜单渲染顺序：导出课表图片 < 考试倒计时 < 空闲时段 < 课程搜索 < 学期管理，
///    且「导入课表」findsNothing、「设置」findsNothing。
/// 3. （§8 追问跟进）导入页 4 张卡片顺序：从教务官网导入 < 拍照 / 相册识别课表
///    < 导入 ICS 日历文件 < 导入 PDF 课表文件；
/// 4. （§8 追问跟进）课表工具页 6 个入口顺序：导出课表图片 < 考试倒计时 < 空闲时段
///    < 课程搜索 < 日期备注 < 菜单管理。
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
    // WeekViewPage 的公告检查会调 PackageInfo.fromPlatform（无 try/catch），
    // 测试里须打桩，否则 MissingPluginException 会以未处理异步错误挂测试
    //（照 home_shell_test 做法）；周日时钟锁到本周一，防周日弹窗遮挡顶栏。
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.1.6',
      buildNumber: '31',
      buildSignature: '',
    );
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    sundayDialogNow = () => monday;
  });

  tearDown(() async {
    sundayDialogNow = DateTime.now;
    await db.close();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpHomeShell(tester, readyFinder: find.byIcon(Icons.more_vert));
  }

  /// 断言一组 Finder 自上而下 y 坐标严格递增（菜单/列表顺序回归通用断言）
  void expectVerticalOrder(
    WidgetTester tester,
    List<Finder> items,
    List<String> labels,
  ) {
    for (var i = 0; i < items.length - 1; i++) {
      final upperY = tester.getTopLeft(items[i]).dy;
      final lowerY = tester.getTopLeft(items[i + 1]).dy;
      expect(
        upperY,
        lessThan(lowerY),
        reason: '「${labels[i]}」应排在「${labels[i + 1]}」之上',
      );
    }
  }

  testWidgets('学期管理页：非当前学期行 ⋮ 菜单顺序为 切换 < 编辑 < 删除', (tester) async {
    // 高视口，保证两学期行一次全部布局出来
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // createSchema 已播种当前学期（id 1），这里再插入一个非当前学期
    await tester.runAsync(() async {
      await Dao.instance.insertSemester(
        const Semester(
          name: '大三下学期',
          startDate: '2027-03-01',
          totalWeeks: 20,
          isCurrent: false,
        ),
      );
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SemesterManagePage()),
      ),
    );
    await pumpUntil(tester, find.text('大三下学期'));

    // ⋮ 限定到「大三下学期」行内：当前学期行是直接编辑按钮、没有 ⋮，
    // 但全页查找会在页面结构变化时误点别处（DeepSeek 257 复审 Bug 1）
    final moreBtn = find.descendant(
      of: find.ancestor(
        of: find.text('大三下学期'),
        matching: find.byType(ListTile),
      ),
      matching: find.byTooltip('更多'),
    );
    expect(moreBtn, findsOneWidget);

    await tester.tap(moreBtn);
    await drainAsync(tester);

    final switchFinder = find.text('切换到该学期');
    final editFinder = find.text('编辑学期');
    final deleteFinder = find.text('删除该学期');

    expect(switchFinder, findsOneWidget);
    expect(editFinder, findsOneWidget);
    expect(deleteFinder, findsOneWidget);

    expectVerticalOrder(tester, [switchFinder, editFinder, deleteFinder],
        ['切换到该学期', '编辑学期', '删除该学期']);
  });

  testWidgets('主页顶栏 ⋮ 菜单：5 项默认顺序递增，且不含导入课表与设置', (tester) async {
    await pumpHome(tester);

    // 顶栏只有一个 ⋮（周跳转条收起态；跳转条展开时是同图标收起按钮，
    // 默认收起所以不会同时出现）——直接断言，不靠坐标兜底
    //（DeepSeek 257 复审 Bug 2）
    final appBarMore = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.more_vert),
    );
    expect(appBarMore, findsOneWidget, reason: '顶栏应只有一个 ⋮ 菜单按钮');

    await tester.tap(appBarMore);
    await drainAsync(tester);

    const expectedOrder = [
      '导出课表图片',
      '考试倒计时',
      '空闲时段',
      '课程搜索',
      '学期管理',
    ];

    // 菜单内文本：本周无课时空态占位也有「导入课表」按钮，全页查找会误判，
    // 所以标题与排除项一律限定在 PopupMenuItem 子树内断言。
    Finder menuText(String title) => find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text(title),
    );

    for (final title in expectedOrder) {
      expect(menuText(title), findsOneWidget, reason: '主页 ⋮ 菜单应显示「$title」');
    }
    expect(menuText('导入课表'), findsNothing, reason: '主页 ⋮ 菜单不应含「导入课表」');
    expect(menuText('设置'), findsNothing, reason: '主页 ⋮ 菜单不应含「设置」');

    expectVerticalOrder(
      tester,
      [for (final title in expectedOrder) menuText(title)],
      expectedOrder,
    );
    await finishHomeShell(tester);
  });

  testWidgets('导入页：4 张导入卡片顺序为 教务官网 < 拍照 < ICS < PDF', (tester) async {
    // createSchema 已播种当前学期（id 1），直接当目标学期，不用另插+切换
    //（DeepSeek 257 复审 Bug 3：另插再切当前学期是多余耦合）

    // 高视口（照 wb235 做法），保证 4 张卡片一次全部布局出来
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ImportPage()),
      ),
    );
    await pumpUntil(tester, find.text('从教务官网导入'));

    const expectedOrder = [
      '从教务官网导入',
      '拍照 / 相册识别课表',
      '导入 ICS 日历文件',
      '导入 PDF 课表文件',
    ];
    for (final title in expectedOrder) {
      expect(find.text(title), findsOneWidget, reason: '导入页应显示「$title」');
    }
    expectVerticalOrder(
      tester,
      [for (final title in expectedOrder) find.text(title)],
      expectedOrder,
    );
  });

  testWidgets('课表工具页：6 个入口顺序为 导出 < 考试 < 空闲 < 搜索 < 备注 < 菜单管理', (tester) async {
    // 高视口，保证 6 行一次全部布局出来（DeepSeek 257 复审 Bug 4）
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // T1（防御性）：补包 ProviderScope，避免后续点击导出等 Consumer 交互时抛错
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CourseToolsPage()),
      ),
    );
    await tester.pump();

    const expectedOrder = [
      '导出课表图片',
      '考试倒计时',
      '空闲时段',
      '课程搜索',
      '日期备注',
      '菜单管理',
    ];
    for (final title in expectedOrder) {
      expect(find.text(title), findsOneWidget, reason: '课表工具应显示「$title」');
    }
    expectVerticalOrder(
      tester,
      [for (final title in expectedOrder) find.text(title)],
      expectedOrder,
    );
  });
}
