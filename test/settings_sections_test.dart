import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/widgets/app_dialog.dart';

/// 设置分类子页测试（2.0.5，WB_SPEC_205 第 1 / 6 / 9 节；2.0.7，WB_SPEC_208 第 3 节加分隔线断言）
///
/// 1. 外观子页：断言实时预览与主要外观项（行高自适应 / 格子圆角 / 今天整列边框高亮）存在；
/// 2. 实时预览今天列高亮（第 6 节）：`highlightTodayColumn` 开/关时，
///    预览里「今天整列边框」覆盖层随之出现/消失（结构断言）；
/// 3. 说明按钮（第 9 节）：说明性副标题收进标题旁 ⓘ，抽查外观/提醒子页点开能看到对应弹窗；
/// 4. 2.0.7：子页某一节内连续行之间有分隔线（以学期与数据子页 6 行 → 5 条分隔线为例）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    // 与其它 FFI widget 测试同款：内存库 + 共享 schema，外观页读库直接用
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

  testWidgets('外观子页：实时预览与主要外观项存在', (tester) async {
    // 首帧读 FFI 内存库（真实异步）：整段放进 runAsync 启动，否则 provider 永远等不到结果
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AppearanceSettingsPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('实时预览'), findsOneWidget);
    expect(find.text('行高自适应一屏'), findsOneWidget);
    expect(find.text('格子圆角半径'), findsOneWidget);
    expect(find.text('今天整列边框高亮'), findsOneWidget);

    // 第 9 节：说明性副标题收进标题旁 ⓘ，抽查「行高自适应一屏」点开看到对应弹窗
    expect(find.byType(AppInfoIconButton), findsWidgets);
    final fitTile = find.widgetWithText(SwitchListTile, '行高自适应一屏');
    expect(fitTile, findsOneWidget);
    final fitInfo = find.descendant(
      of: fitTile,
      matching: find.byType(AppInfoIconButton),
    );
    expect(fitInfo, findsOneWidget);
    await tester.tap(fitInfo);
    await tester.pumpAndSettle();
    expect(find.text('按屏幕高度均分行高，整张课表不用上下滚'), findsOneWidget);
  });

  testWidgets('外观子页：底部栏显示开关存在、默认开、点击即时切换（WB_SPEC_213 第 1 节）', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AppearanceSettingsPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final tile = find.widgetWithText(SwitchListTile, '底部栏显示');
    expect(tile, findsOneWidget);
    // 默认开
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    // 说明文字作为常驻副标题显示（不再用 ⓘ）
    expect(
      find.text('开启后主页底部显示悬浮胶囊，可一键切换课表与设置；关闭后设置改从右上角菜单进入'),
      findsOneWidget,
    );

    // 点击切换 → 即时生效（无需重启）；apply 走真实 FFI 异步落库，放 runAsync 里等它写完
    await tester.tap(tile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('提醒子页：ⓘ 说明按钮存在且点开能看到对应弹窗', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: RemindersSettingsPage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 第 9 节：至少一个 ⓘ 按钮；抽查「上课提醒」点开看到原说明弹窗
    expect(find.byType(AppInfoIconButton), findsWidgets);
    final reminderTile = find.widgetWithText(SwitchListTile, '上课提醒');
    expect(reminderTile, findsOneWidget);
    final reminderInfo = find.descendant(
      of: reminderTile,
      matching: find.byType(AppInfoIconButton),
    );
    expect(reminderInfo, findsOneWidget);
    await tester.tap(reminderInfo);
    await tester.pumpAndSettle();
    expect(find.text('每节课提前提醒，App 被杀后也能准时响铃'), findsOneWidget);
  });

  testWidgets('实时预览：今天列边框随 highlightTodayColumn 开关', (tester) async {
    Future<void> pumpPreview(bool highlight) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                Preview(
                  ui: UiSettings(highlightTodayColumn: highlight),
                  columnCount: 5,
                  slots: const [],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 开：今天列边框覆盖层出现
    await pumpPreview(true);
    expect(find.byKey(kPreviewTodayHighlightKey), findsOneWidget);

    // 关：覆盖层消失（预览重建且不再画今天列边框）
    await pumpPreview(false);
    expect(find.byKey(kPreviewTodayHighlightKey), findsNothing);
  });

  testWidgets('学期与数据子页：同一节内连续行之间有分隔线', (tester) async {
    // 6 行入口 → 5 条 1px 分隔线；本页 build 不 watch 任何 provider，无需读库
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DataSettingsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('导入课表'), findsOneWidget);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(5));
  });
}
