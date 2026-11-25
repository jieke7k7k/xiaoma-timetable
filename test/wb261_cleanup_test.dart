import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/pages/course_search_page.dart';
import 'package:xiaoma_timetable/pages/course_tools_page.dart';
import 'package:xiaoma_timetable/pages/permission_page.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/services/permission_service.dart';
import 'package:xiaoma_timetable/ui/app_styles.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';

import 'helpers/pump_helpers.dart';

/// WB_SPEC_261 大扫除回归测试。
///
/// 覆盖 §4 权限直达、§6 导出同步、§8 搜索框移出 AppBar、§5 回到本周圆角。
/// 手动泵法（不用 pumpAndSettle，本 App 上会 hang）；真实 IO 包 runAsync。
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
    // 权限页用测试替身，不走平台通道。
    PermissionService.debugStatusOverride = () async =>
        const PermissionSnapshot(
          notification: true,
          exactAlarm: true,
          battery: true,
        );
  });

  tearDown(() async {
    PermissionService.debugStatusOverride = null;
    sundayDialogNow = DateTime.now;
    await db.close();
  });

  group('§4 权限自检直达 /permissions', () {
    testWidgets('点「权限自检」直接打开权限页，不经过中间页', (tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: const SettingsPage(),
              routes: {
                '/permissions': (_) => const PermissionPage(),
              },
            ),
          ),
        );
      });
      // L7（DeepSeek 264 复审 B 段）：600ms 死等改走 pumpUntil——等到「权限自检」
      // 瓦片出现即停，不空转；pumpUntil 放在 runAsync 外（它内部自己管真实异步窗口）
      await pumpUntil(tester, find.text('权限自检'));
      await drainAsync(tester);

      expect(find.text('权限自检'), findsOneWidget);
      await tester.tap(find.text('权限自检'));
      await drainAsync(tester);

      // 权限页 AppBar 标题为「权限」，三项权限平铺。
      expect(find.text('权限'), findsOneWidget);
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('精确闹钟'), findsOneWidget);
      expect(find.text('电池优化白名单'), findsOneWidget);
      // WB_SPEC_261 复审（DeepSeek A4）：用真实路由表断言——入口必须指向
      // 现存的 /permissions，且已删的 /settings-permissions 不可复活。
      expect(appRoutes.containsKey('/settings-permissions'), isFalse);
      expect(appRoutes.containsKey('/permissions'), isTrue);
    });
  });

  group('§6 课表工具导出与主页同步', () {
    testWidgets('点「导出课表图片」弹出与主页同款 BottomSheet（含整学期与当前周）',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: CourseToolsPage())),
      );
      await drainAsync(tester);

      await tester.tap(find.text('导出课表图片'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('导出课表'), findsOneWidget);
      expect(find.text('导出整学期课表（图片）'), findsOneWidget);
      expect(find.textContaining('导出当前第'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });
  });

  group('§8 搜索框在 body 内', () {
    testWidgets('搜索框不在 AppBar：标题为纯文字，框在 body 顶部，输入出结果、清空全清',
        (tester) async {
      // 先入库一门课，供搜索命中。
      await tester.runAsync(() async {
        await Dao.instance.insertCourse(
          const Course(
            semesterId: 1,
            name: '药物化学',
            teacher: '张老师',
            classroom: '教3-201',
            colorValue: 0xFF8C6246,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
          ),
        );
      });

      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: CourseSearchPage())),
      );
      await drainAsync(tester);

      // AppBar 标题是纯文字「课程搜索」，搜索框不在 AppBar 里。
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.title, isA<Text>());
      expect((appBar.title as Text).data, '课程搜索');
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(
        find.ancestor(of: field, matching: find.byType(AppBar)),
        findsNothing,
        reason: '搜索框应在 body 内，不在 AppBar 里',
      );
      final decoration =
          tester.widget<TextField>(field).decoration!;
      expect(decoration.prefixIcon, isA<Icon>());
      expect(
        (decoration.prefixIcon as Icon).icon,
        Icons.search,
        reason: '搜索框应有搜索 prefixIcon',
      );
      expect(decoration.hintText, '搜索课名、老师或教室');
      expect(decoration.isDense, isTrue);

      // 输入后出结果。
      await tester.enterText(field, '药物');
      await tester.pump();
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // 点清空：框内文字与结果同时清空，回到空查询提示。
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller?.text,
        isEmpty,
        reason: '清空后框内文字应为空（§8 修掉的 latent bug）',
      );
      expect(find.text('药物化学'), findsNothing);
      expect(find.text('搜索当前学期的课程'), findsOneWidget);
    });
  });

  group('§5 回到本周竖条圆角', () {
    testWidgets('InkWell borderRadius 与父级 Material 左侧圆角一致', (tester) async {
      // 照 wb257 做法：PackageInfo 打桩 + 周日时钟锁到本周一（防周日弹窗
      // 遮挡）+ 阻断网络（公告检查不走真网）。
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

      final container = ProviderContainer();
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpHomeShell(
        tester,
        container: container,
        readyFinder: find.byIcon(Icons.more_vert),
      );

      // 切到非本周，竖条出现（竖排文字逐字渲染，找首字「回」）。
      final today = container.read(todayWeekProvider);
      container.read(displayWeekProvider.notifier).setWeek(today == 1 ? 2 : 1);
      await drainAsync(tester);
      final railText = find.text('回');
      expect(railText, findsOneWidget, reason: '非本周视图应显示「回到本周」竖条');

      final inkWell = tester.widget<InkWell>(
        find.ancestor(of: railText, matching: find.byType(InkWell)),
      );
      const expected = BorderRadius.only(
        topLeft: Radius.circular(AppRadii.card),
        bottomLeft: Radius.circular(AppRadii.card),
      );
      expect(
        inkWell.borderRadius,
        expected,
        reason: 'InkWell 应与 Material 同款左侧圆角，按压高亮才按竖条形状裁剪',
      );
      // 最近的祖先 Material（竖条本体）圆角与 InkWell 一致。
      BorderRadius? materialRadius;
      tester.element(railText).visitAncestorElements((e) {
        if (e.widget is Material) {
          materialRadius = (e.widget as Material).borderRadius as BorderRadius?;
          return false;
        }
        return true;
      });
      expect(materialRadius, expected);
      expect(materialRadius, inkWell.borderRadius);
      await finishHomeShell(tester);
    });
  });
}
