import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/ui/app_choice_chip.dart';
import 'package:xiaoma_timetable/utils/color_schemes.dart';
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
    // WB_SPEC_219：开关已移到第 4 组（页底），先滚进视口再点，避免命中失败
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('外观子页：切换动效三选项存在、默认柔和、点击切换即时生效（2026-11-05）', (tester) async {
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

    // 三种动效都做，做成开关让用户自己选；默认柔和（官方淡入）
    expect(find.text('切换动效'), findsOneWidget);
    expect(find.byType(AppChoiceChip), findsNWidgets(3));
    // 复查 Bug 6：断言字面量「灵动/柔和/疾速」与三个 id 的映射，不与实现
    // 共用同一枚举 label（否则改名写错仍全绿）。
    const expectedLabels = {
      'fade-parallax': '灵动',
      'fade-through': '柔和',
      'quick-fade': '疾速',
    };
    for (final entry in expectedLabels.entries) {
      final style = ShellTransitionStyle.fromId(entry.key);
      expect(style.label, entry.value, reason: 'id ${entry.key} 的中文名应为 ${entry.value}');
      expect(find.byKey(shellTransitionChipKey(style)), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
    }
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(
              shellTransitionChipKey(ShellTransitionStyle.fadeThroughOfficial),
            ),
          )
          .selected,
      isTrue,
    );

    // 点「疾速」→ 即时切换并持久化（apply 走真实 FFI 异步落库）
    // WB_SPEC_219：三选一已移到第 4 组（页底），先滚进视口再点
    final quickChip =
        find.byKey(shellTransitionChipKey(ShellTransitionStyle.quickFade));
    await tester.ensureVisible(quickChip);
    await tester.pumpAndSettle();
    await tester.tap(quickChip);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(
              shellTransitionChipKey(ShellTransitionStyle.quickFade),
            ),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<AppChoiceChip>(
            find.byKey(
              shellTransitionChipKey(ShellTransitionStyle.fadeThroughOfficial),
            ),
          )
          .selected,
      isFalse,
    );
    final saved = await tester.runAsync(
      () => Dao.instance.getSetting('ui_settings'),
    );
    expect(
      UiSettings.fromEncoded(saved).shellTransitionStyle,
      ShellTransitionStyle.quickFade,
    );
  });

  testWidgets('外观子页：没有「底部栏样式」选项（只有新标签栏一种形态）', (
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

    // 2.1.7 同版本修复：胶囊形态删除，底部栏只有新标签栏一种，
    // 外观页不再有「底部栏样式」二选一；底部栏开关本身仍在。
    // 注意：页面上仍有单选芯片——那是 2026-11-05 新增的「切换动效」
    // 三选项（灵动/柔和/疾速），不是底部栏样式。
    expect(find.text('底部栏样式'), findsNothing);
    expect(find.text('新标签栏'), findsNothing);
    expect(find.text('胶囊贴底'), findsNothing);
    expect(find.byType(AppChoiceChip), findsNWidgets(3));
    expect(
      find.widgetWithText(SwitchListTile, '底部栏显示'),
      findsOneWidget,
    );
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

  group('WB_SPEC_219：外观二级页重组', () {
    Future<void> pumpAppearance(WidgetTester tester) async {
      // 拉高画布：4 组条目全部在树里且坐标可比较（y 坐标用于归组断言）
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
    }

    double y(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    testWidgets('4 个新分组标题齐全，且顺序为色彩→网格→卡片→导航', (tester) async {
      await pumpAppearance(tester);
      const groups = [
        '色彩与主题',
        '课表网格与表头',
        '课程卡片样式与字体',
        '导航与交互动效',
      ];
      for (final g in groups) {
        expect(find.text(g), findsOneWidget, reason: '分组「$g」应出现在外观页');
      }
      final ys = groups.map((g) => y(tester, g)).toList();
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]),
            reason: '分组须按规格书 2.2 顺序自上而下');
      }
      // 旧分组标题（格子外观 / 卡片显示 / 主题颜色）已被标准分组取代；
      // 「课程配色」字样仍在，为课程配色下拉的 label（非分组标题），不断言消失。
      for (final old in ['格子外观', '卡片显示', '主题颜色']) {
        expect(find.text(old), findsNothing);
      }
    });

    testWidgets('关键条目在正确组内（底部栏/圆角/周末收起/显示非本周）', (tester) async {
      await pumpAppearance(tester);
      final g2 = y(tester, '课表网格与表头');
      final g3 = y(tester, '课程卡片样式与字体');
      final g4 = y(tester, '导航与交互动效');

      // 规格书称「显示底部导航栏」＝原「底部栏显示」开关（2.2 明确文案不变），
      // 与「切换动效」一起沉到第 4 组。
      expect(y(tester, '底部栏显示'), greaterThan(g4));
      expect(y(tester, '切换动效'), greaterThan(g4));
      expect(find.byType(AppChoiceChip), findsNWidgets(3));

      // 规格书称「卡片圆角大小」＝原「格子圆角半径」滑杆（控件本身不动），
      // 从第 2 组移入第 3 组；卡片文字大小 / 显示教室 / 显示老师 / 显示备注同组。
      expect(y(tester, '格子圆角半径'), greaterThan(g3));
      expect(y(tester, '格子圆角半径'), lessThan(g4));
      for (final t in [
        '卡片文字大小',
        '显示教室',
        '显示老师',
        '显示备注',
      ]) {
        expect(y(tester, t), greaterThan(g3), reason: '$t 应在第 3 组');
        expect(y(tester, t), lessThan(g4), reason: '$t 应在第 3 组');
      }

      // 第 2 组：周末收起（页底移入）、行高自适应、显示非本周课程（页底移入）等 9 项
      for (final t in [
        '周末无课时自动收起周六日',
        '行高自适应一屏',
        '课程格子高度',
        '显示网格线',
        '格子边框粗细',
        '今天整列边框高亮',
        '节数栏显示时间',
        '标题显示单双周',
        '显示非本周课程',
      ]) {
        expect(y(tester, t), greaterThan(g2), reason: '$t 应在第 2 组');
        expect(y(tester, t), lessThan(g3), reason: '$t 应在第 2 组');
      }

      // 第 1 组：三段深浅模式 + 界面主题色 + 课程卡片配色下拉与同步按钮
      expect(find.text('跟随系统'), findsOneWidget);
      expect(find.text('同步应用推荐界面主题色'), findsOneWidget);
      expect(find.textContaining('顺带应用推荐主题色'), findsNothing);
      expect(y(tester, '同步应用推荐界面主题色'), lessThan(g2));
      // 课程配色下拉此时共 10 套（方案集合本身在 color_schemes_test 逐字校验）；
      // 外观页仍能找到课程配色下拉与显示字体下拉两个 DropdownButtonFormField。
      expect(kCourseColorSchemes.length, 10);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    });

    testWidgets('节次时间设置 / 立即刷新桌面小部件 / 部件状态 已移出外观页', (tester) async {
      await pumpAppearance(tester);
      expect(find.text('节次时间设置'), findsNothing);
      expect(find.text('立即刷新桌面小部件'), findsNothing);
      expect(find.text('部件状态'), findsNothing);
      expect(find.byIcon(Icons.schedule_outlined), findsNothing);
    });

    testWidgets('实时预览位于页首（页面第 1 项，不吸顶退化）', (tester) async {
      await pumpAppearance(tester);
      expect(find.byType(Preview), findsOneWidget);
      expect(find.text('实时预览'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(Preview)).dy,
        lessThan(y(tester, '色彩与主题')),
        reason: '预览应在第 1 组标题之前（页首）',
      );
    });
  });

  group('WB_SPEC_219：桌面小组件页承接移入的两项', () {
    testWidgets('立即刷新桌面小部件、部件状态出现在 WidgetSettingsPage 且用 Divider 隔开', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: WidgetSettingsPage()),
        ),
      );
      await tester.pump();

      expect(find.text('今日课程小组件'), findsOneWidget);
      expect(find.text('立即刷新桌面小部件'), findsOneWidget);
      expect(find.text('部件状态'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));

      final yGuide = tester.getTopLeft(find.text('今日课程小组件')).dy;
      final yRefresh = tester.getTopLeft(find.text('立即刷新桌面小部件')).dy;
      final yStatus = tester.getTopLeft(find.text('部件状态')).dy;
      expect(yRefresh, greaterThan(yGuide),
          reason: '两项应追加在「今日课程小组件」说明行之后');
      expect(yStatus, greaterThan(yRefresh));
    });
  });

}
