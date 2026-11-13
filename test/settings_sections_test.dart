import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/ui/app_choice_chip.dart';
import 'package:xiaoma_timetable/ui/settings_entry_row.dart';
import 'package:xiaoma_timetable/ui/settings_line_frame.dart';
import 'package:xiaoma_timetable/widgets/app_dialog.dart';

/// 设置分类子页测试。
///
/// WB_SPEC_228 起外观父页只剩「1 实时预览 + 8 行入口」，本文件里所有依赖
/// 旧平铺布局的断言同步改成新结构；控件行为（开关持久化、ⓘ 说明、预览
/// 高亮、抽屉/弹层）继续逐项锁住。
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

  /// 拉高画布（分组 y 坐标可比较）+ 等首帧异步 provider 就绪
  Future<void> pumpAppearance(WidgetTester tester) async {
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

  group('WB_SPEC_228 §3：外观父页只剩 1 预览 + 8 行', () {
    testWidgets('3 个线框组、6 个入口行 + 1 深浅模式行 + 1 开关行',
        (tester) async {
      await pumpAppearance(tester);
      expect(find.byType(SettingsLineFrame), findsNWidgets(3));
      expect(find.byType(SettingsEntryRow), findsNWidgets(6));
      expect(find.byType(SettingsSwitchRow), findsOneWidget);
      expect(find.byType(Preview), findsOneWidget);
      expect(find.text('深浅模式'), findsOneWidget);
      expect(find.text('底部栏显示'), findsOneWidget);
    });

    testWidgets('8 行标题齐全（色彩与字体 4 / 排版 2 / 导航 2）',
        (tester) async {
      await pumpAppearance(tester);
      for (final title in [
        '深浅模式',
        '界面主题色',
        '课程配色',
        '显示字体',
        '课表网格与表头',
        '课程卡片样式',
        '底部栏显示',
        '切换动效',
      ]) {
        expect(find.text(title), findsOneWidget,
            reason: '入口「$title」应出现在外观父页');
      }
    });

    testWidgets('细节控件已搬进子页：父页不再有滑杆 / 宫格 / 竖排三按钮',
        (tester) async {
      await pumpAppearance(tester);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(AppChoiceChip), findsNothing);
      for (final moved in [
        '行高自适应一屏',
        '课程格子高度',
        '格子圆角半径',
        '卡片文字大小',
        '显示教室',
        '显示网格线',
        '格子边框粗细',
        '周末无课时自动收起周六日',
        '今天整列边框高亮',
        '灵动',
        '疾速',
      ]) {
        expect(find.text(moved), findsNothing,
            reason: '「$moved」应已搬进专项子页');
      }
    });

    testWidgets('3 组顺序：色彩与字体 → 课表排版与细节 → 导航与底栏',
        (tester) async {
      await pumpAppearance(tester);
      const groups = ['色彩与字体', '课表排版与细节', '导航与底栏'];
      for (final g in groups) {
        expect(find.text(g), findsOneWidget, reason: '分组「$g」应在外观父页');
      }
      expect(y(tester, groups[1]), greaterThan(y(tester, groups[0])));
      expect(y(tester, groups[2]), greaterThan(y(tester, groups[1])));
      // 旧分组标题已被 228 的三组取代
      // 注：「课表网格与表头」现在是入口行标题（仍会出现），不在此列
      for (final old in [
        '色彩与主题',
        '课程卡片样式与字体',
        '导航与交互动效',
      ]) {
        expect(find.text(old), findsNothing, reason: '旧分组「$old」应不再作标题');
      }
    });

    testWidgets('实时预览位于页首（页面第 1 项，不吸顶退化）', (tester) async {
      await pumpAppearance(tester);
      expect(find.byType(Preview), findsOneWidget);
      expect(find.text('实时预览'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(Preview)).dy,
        lessThan(y(tester, '色彩与字体')),
        reason: '预览应在第 1 组标题之前（页首）',
      );
    });

    testWidgets('节次时间设置 / 立即刷新桌面小部件 / 部件状态 已移出外观页',
        (tester) async {
      await pumpAppearance(tester);
      expect(find.text('节次时间设置'), findsNothing);
      expect(find.text('立即刷新桌面小部件'), findsNothing);
      expect(find.text('部件状态'), findsNothing);
      expect(find.byIcon(Icons.schedule_outlined), findsNothing);
    });
  });

  group('WB_SPEC_228 §3.1–3.3：三处收成行', () {
    testWidgets('界面主题色点开是底部弹层宫格（父页不展开宫格）',
        (tester) async {
      await pumpAppearance(tester);
      expect(find.text('自定义'), findsNothing);
      await tester.tap(find.text('界面主题色'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('自定义'), findsWidgets);
      expect(find.text('可可棕'), findsWidgets);
    });

    testWidgets('同步链收进课程配色面板底部（父页不单独占行）',
        (tester) async {
      await pumpAppearance(tester);
      expect(find.text('同步应用推荐界面主题色'), findsNothing);
      await tester.tap(find.text('课程配色'));
      await tester.pumpAndSettle();
      expect(find.text('同步应用推荐界面主题色'), findsOneWidget);
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('切换动效收成单行：底部弹层 SegmentedButton 三选一且持久化',
        (tester) async {
      await pumpAppearance(tester);
      expect(find.text('切换动效'), findsOneWidget);
      expect(find.byType(AppChoiceChip), findsNothing);

      await tester.tap(find.text('切换动效'));
      await tester.pumpAndSettle();
      expect(find.byType(SegmentedButton<ShellTransitionStyle>),
          findsOneWidget);
      for (final label in ['灵动', '柔和', '疾速']) {
        expect(find.text(label), findsWidgets,
            reason: '弹层应含动效「$label」');
      }
      const expectedLabels = {
        'fade-parallax': '灵动',
        'fade-through': '柔和',
        'quick-fade': '疾速',
      };
      for (final entry in expectedLabels.entries) {
        expect(ShellTransitionStyle.fromId(entry.key).label, entry.value);
      }

      await tester.tap(find.text('疾速'));
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(
        () => Dao.instance.getSetting('ui_settings'),
      );
      expect(
        UiSettings.fromEncoded(saved).shellTransitionStyle,
        ShellTransitionStyle.quickFade,
      );
    });
  });

  testWidgets('外观父页：底部栏显示开关默认开、点击即时切换', (tester) async {
    await pumpAppearance(tester);
    final tile = find.widgetWithText(SwitchListTile, '底部栏显示');
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(
      find.text('关闭后可从主页右上角菜单进入设置'),
      findsOneWidget,
    );

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
    // 联动 ①：底部栏关时切换动效行整体消失
    expect(find.text('切换动效'), findsNothing);
  });

  testWidgets('外观父页：没有「底部栏样式」选项（只有新标签栏一种形态）',
      (tester) async {
    await pumpAppearance(tester);
    expect(find.text('底部栏样式'), findsNothing);
    expect(find.text('新标签栏'), findsNothing);
    expect(find.text('胶囊贴底'), findsNothing);
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

    await pumpPreview(true);
    expect(find.byKey(kPreviewTodayHighlightKey), findsOneWidget);
    await pumpPreview(false);
    expect(find.byKey(kPreviewTodayHighlightKey), findsNothing);
  });

  testWidgets('数据备份与换机子页：标题 + 纯本地提示条 + 连续行分隔线',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DataSettingsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('数据备份与换机'), findsOneWidget);
    expect(find.textContaining('纯本地隐私存储'), findsOneWidget);
    expect(find.textContaining('不包含云端同步'), findsOneWidget);
    expect(find.text('导入课表'), findsOneWidget);
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(5));
  });

  group('WB_SPEC_219：桌面小组件页承接移入的两项', () {
    testWidgets('立即刷新桌面小部件、部件状态出现在 WidgetSettingsPage 且用 Divider 隔开',
        (tester) async {
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
