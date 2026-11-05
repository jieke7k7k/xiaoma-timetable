import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
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
    // 2.1.4 起「底部栏样式」选择行插在「底部栏显示」下方，外观组整体下移，
    // 这里先把目标行滚进视口再点，避免「点在屏幕外」导致 tap 命中失败
    await tester.ensureVisible(fitInfo);
    await tester.pumpAndSettle();
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
      find.text('开启后主页底部显示底部栏，可一键切换课表与设置；关闭后设置改从右上角菜单进入'),
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

  testWidgets('外观子页：底部栏样式二选一，默认新标签栏，点胶囊即时切换并落库（WB_SPEC_216 第 1 节）', (
    tester,
  ) async {
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

    expect(find.text('底部栏样式'), findsOneWidget);
    final tabChip = find.byKey(bottomBarStyleChipKey(BottomBarStyle.tab));
    final capsuleChip = find.byKey(
      bottomBarStyleChipKey(BottomBarStyle.capsule),
    );
    expect(tabChip, findsOneWidget);
    expect(capsuleChip, findsOneWidget);
    // 两项文案就是规格里的「新标签栏」「胶囊贴底」；2.1.4 的「通栏贴底」已删除
    expect(find.text('新标签栏'), findsOneWidget);
    expect(find.text('胶囊贴底'), findsOneWidget);
    expect(find.text('通栏贴底'), findsNothing);
    // 默认选中新标签栏
    expect(tester.widget<ChoiceChip>(tabChip).selected, isTrue);
    expect(tester.widget<ChoiceChip>(capsuleChip).selected, isFalse);

    // 点「胶囊贴底」→ 即时切换（走 apply，真实 FFI 异步落库，放进 runAsync 等它写完）
    await tester.ensureVisible(capsuleChip);
    await tester.pumpAndSettle();
    await tester.tap(capsuleChip);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<ChoiceChip>(capsuleChip).selected, isTrue);
    expect(tester.widget<ChoiceChip>(tabChip).selected, isFalse);

    // 落库：ui_settings 里存的是 capsule（杀进程重进保持）
    final raw = await tester.runAsync(
      () => Dao.instance.getSetting('ui_settings'),
    );
    expect(UiSettings.fromEncoded(raw).bottomBarStyle, BottomBarStyle.capsule);

    // 再点回「新标签栏」→ 同样即时生效并落库 tab
    await tester.ensureVisible(tabChip);
    await tester.pumpAndSettle();
    await tester.tap(tabChip);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<ChoiceChip>(tabChip).selected, isTrue);
    final raw2 = await tester.runAsync(
      () => Dao.instance.getSetting('ui_settings'),
    );
    expect(UiSettings.fromEncoded(raw2).bottomBarStyle, BottomBarStyle.tab);
  });

  testWidgets('外观子页：样式行列出的是新标签栏/胶囊贴底两项，旧项 bar 已不存在', (
    tester,
  ) async {
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

    // 选项数量 = BottomBarStyle.values.length = 2，key 也只对应这两项
    final chips = tester.widgetList<ChoiceChip>(
      find.descendant(
        of: find.byType(Wrap),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chips.length, BottomBarStyle.values.length);
    expect(chips.length, 2);
    expect(
      find.byKey(bottomBarStyleChipKey(BottomBarStyle.tab)),
      findsOneWidget,
    );
    expect(
      find.byKey(bottomBarStyleChipKey(BottomBarStyle.capsule)),
      findsOneWidget,
    );
  });

  testWidgets('外观子页：底部栏开关关闭时，样式选项置灰不可点（WB_SPEC_216 第 1 节）', (
    tester,
  ) async {
    // 预置「底部栏关闭 + 已选胶囊」，样式行应整行置灰、两个选项 onSelected 为 null，
    // 且样式字段不被清掉（重开栏要恢复胶囊）。
    // 真实 FFI 写库必须放进 runAsync：testWidgets 的假时钟不会推进真实 IO。
    await tester.runAsync(
      () => Dao.instance.setSetting(
        'ui_settings',
        const UiSettings(
          showBottomBar: false,
          bottomBarStyle: BottomBarStyle.capsule,
        ).encode(),
      ),
    );
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

    final tabChip = find.byKey(bottomBarStyleChipKey(BottomBarStyle.tab));
    final capsuleChip = find.byKey(
      bottomBarStyleChipKey(BottomBarStyle.capsule),
    );
    expect(tester.widget<ChoiceChip>(tabChip).onSelected, isNull);
    expect(tester.widget<ChoiceChip>(capsuleChip).onSelected, isNull);
    // 整行置灰：ListTile.enabled == false
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, '底部栏样式'),
          )
          .enabled,
      isFalse,
    );
    // 开关本身是关的
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, '底部栏显示'),
          )
          .value,
      isFalse,
    );
    // 置灰时点了也不改设置（仍是关闭，样式仍是关栏前的胶囊）
    await tester.tap(capsuleChip, warnIfMissed: false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    final raw = await tester.runAsync(
      () => Dao.instance.getSetting('ui_settings'),
    );
    final ui = UiSettings.fromEncoded(raw);
    expect(ui.showBottomBar, isFalse);
    expect(ui.bottomBarStyle, BottomBarStyle.capsule);

    // 重新打开开关 → 恢复上次形态（胶囊），样式选项重新可点
    await tester.tap(find.widgetWithText(SwitchListTile, '底部栏显示'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, '底部栏显示'),
          )
          .value,
      isTrue,
    );
    expect(tester.widget<ChoiceChip>(capsuleChip).selected, isTrue);
    expect(tester.widget<ChoiceChip>(tabChip).onSelected, isNotNull);
    final raw2 = await tester.runAsync(
      () => Dao.instance.getSetting('ui_settings'),
    );
    final ui2 = UiSettings.fromEncoded(raw2);
    expect(ui2.showBottomBar, isTrue);
    expect(ui2.bottomBarStyle, BottomBarStyle.capsule, reason: '开栏恢复上次形态');
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

  testWidgets('数据备份与换机子页：标题 + 纯本地提示条 + 连续行分隔线', (tester) async {
    // 6 行入口 → 5 条 1px 分隔线；本页 build 不 watch 任何 provider，无需读库
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DataSettingsPage()),
      ),
    );
    await tester.pump();

    // 2.1.7（WB_SPEC_218 第 ③/④ 节）：页标题改为「数据备份与换机」，
    // 顶部常驻纯本地存储提示条（删云同步后，换机靠手动备份恢复）
    expect(find.text('数据备份与换机'), findsOneWidget);
    expect(find.textContaining('纯本地隐私存储'), findsOneWidget);
    expect(find.textContaining('不包含云端同步'), findsOneWidget);

    expect(find.text('导入课表'), findsOneWidget);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(5));
  });
}
