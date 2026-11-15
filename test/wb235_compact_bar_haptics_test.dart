import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/app_choice_chip.dart';
import 'package:xiaoma_timetable/ui/app_select_field.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/ui/liquid_glass.dart';
import 'package:xiaoma_timetable/ui/settings_entry_row.dart';
import 'package:xiaoma_timetable/utils/app_haptics.dart';
import 'package:xiaoma_timetable/widgets/app_dialog.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// WB_SPEC_235 同版本重发验收：底栏压到 48dp + 全 App 按键震动反馈 + 开关。
///
/// 分五组锁住规格：
/// 1. **栏高组**（§2）：五个数字（栏高 48 / 图标 20 / 字号 10.5 / 间距 2 /
///    短条 16×2.5 距底 3）+ 删掉图标外 1.08x 放大层后 iconKey 落在 LiquidIcon 上；
/// 2. **门控组**（§3/§4）：`UiSettings.enableHaptics` 默认开、编解码往返、
///    老库缺键回默认开（无迁移）；
/// 3. **开关组**（§5）：外观页「导航」组第 2 行是开关，关掉后落库 + 门控同步关，
///    且开关那一下只震一次（不双震）；
/// 4. **收口组**（§6）：8 类共用组件的档位与「只震一次」；
/// 5. **存量组**（§7）：全库除 `app_haptics.dart` 外不再直调 `HapticFeedback.`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 平台震动调用的捕获口：所有 HapticFeedback 都会打到这里
  final calls = <String>[];
  var fakeNow = DateTime(2026, 11, 15, 8);

  /// 每次点击前把假时钟推过 45ms 节流窗口，避免测试之间互相节流
  void advance() => fakeNow = fakeNow.add(const Duration(milliseconds: 100));

  setUp(() {
    calls.clear();
    fakeNow = DateTime(2026, 11, 15, 8);
    AppHaptics.resetForTest();
    AppHaptics.clock = () => fakeNow;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppHaptics.resetForTest();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // -------------------------------------------------------------------------
  // 1. 栏高组
  // -------------------------------------------------------------------------
  group('栏高组（§2 五个数字 + 结构）', () {
    test('几何常量：栏高 48 / 图标 20 / 短条 16×2.5 距底 3', () {
      expect(kBottomBarTabHeight, 48);
      expect(kLiquidTabIconSize, 20);
      expect(kSelectionPillWidth, 16);
      expect(kSelectionPillHeight, 2.5);
      expect(kSelectionPillBottomGap, 3);
      // 留白口径随栏高一起变：只剩一种档，不再有「关栏 16」
      expect(bottomBarGridBottomInset(), 48);
      expect(bottomBarGridBottomPadding(34), 34 + 48);
    });

    testWidgets('实测栏高 48，标签 10.5 号字配 1.1 行高、图标文字间距 2',
        (tester) async {
      await tester.pumpWidget(wrap(
        HomeTabBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ));

      expect(tester.getSize(find.byType(HomeTabBar)).height, 48);

      final label = tester.widget<LiquidLabel>(
        find.byKey(kHomeTabBarScheduleLabelKey),
      );
      expect(label.style.fontSize, 10.5);
      expect(label.style.height, 1.1);

      final icon = tester.widget<LiquidIcon>(
        find.byKey(kHomeTabBarScheduleIconKey),
      );
      expect(icon.size, 20);

      // 图标与文字之间的固定间距：2dp（Column 里那个 SizedBox）
      final spacers = tester
          .widgetList<SizedBox>(find.descendant(
            of: find.byKey(kHomeTabBarScheduleKey),
            matching: find.byType(SizedBox),
          ))
          .where((s) => s.height == 2)
          .toList();
      expect(spacers, isNotEmpty, reason: '图标与文字间距应为 2dp');
    });

    testWidgets('选中短条实测 16×2.5、距栏底 3dp', (tester) async {
      await tester.pumpWidget(wrap(
        HomeTabBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ));

      final boxRect = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(boxRect.height, 48);
      final pill = tester.getRect(
        find
            .descendant(
              of: find.byKey(kHomeTabBarIndicatorBoxKey),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(pill.width, closeTo(16, 0.5));
      expect(pill.height, closeTo(2.5, 0.5));
      expect(boxRect.bottom - pill.bottom, closeTo(3, 0.5));
    });

    testWidgets('1.08x 放大层已删：iconKey 命中 LiquidIcon，选中只上浮不放大',
        (tester) async {
      await tester.pumpWidget(wrap(
        HomeTabBar(
          activeTab: HomeShellTab.settings,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ));

      expect(
        tester.widget(find.byKey(kHomeTabBarSettingsIconKey)).runtimeType,
        LiquidIcon,
      );
      final lift = tester.widget<AnimatedSlide>(
        find.byKey(kHomeTabBarSettingsLiftKey),
      );
      expect(lift.offset.dy * kLiquidTabIconSize, closeTo(-1.5, 1e-9));

      // 按压 0.92 保留（AnimatedScale 仍在，只是不再包图标做放大）
      final press = tester.widget<AnimatedScale>(
        find.byKey(kHomeTabBarSettingsPressKey),
      );
      expect(press.scale, 1.0);
    });
  });

  // -------------------------------------------------------------------------
  // 2. 门控组（UiSettings 字段）
  // -------------------------------------------------------------------------
  group('门控组（§4 enableHaptics 持久化）', () {
    test('默认开', () {
      expect(const UiSettings().enableHaptics, isTrue);
    });

    test('toJson 写出字段，fromEncoded 往返一致', () {
      final off = const UiSettings().copyWith(enableHaptics: false);
      expect(off.toJson()['enableHaptics'], isFalse);
      expect(UiSettings.fromEncoded(off.encode()).enableHaptics, isFalse);

      final on = off.copyWith(enableHaptics: true);
      expect(UiSettings.fromEncoded(on.encode()).enableHaptics, isTrue);
    });

    test('老库没有这个键 → 按默认开（不需要迁移）', () {
      // 模拟 2.5.0+39 之前写下的 ui_settings：没有 enableHaptics 键
      const legacy = '{"cellHeight":46,"showClassBroadcast":true}';
      expect(UiSettings.fromEncoded(legacy).enableHaptics, isTrue);
    });

    test('坏值（非 bool）回默认开，不抛', () {
      const broken = '{"enableHaptics":"yes"}';
      expect(UiSettings.fromEncoded(broken).enableHaptics, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 3. 开关组（§5 外观页导航组第 2 行）
  // -------------------------------------------------------------------------
  group('开关组（§5 外观页「导航」组第 2 行）', () {
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

    Future<void> pumpAppearance(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // 与 settings_sections_test 同款：建页与首帧异步都放进 runAsync，
      // 否则 testWidgets 的假时钟会让 delayed 永久挂起
      await tester.runAsync(() async {
        await Dao.instance.setSetting(
          'ui_settings',
          const UiSettings().encode(),
        );
        await Dao.instance.setSetting(
          UiSettingsNotifier.kDefaultsMigratedKey,
          '1',
        );
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

    testWidgets('导航组第 2 行是「触感震动反馈」，默认开、副标题文案固定',
        (tester) async {
      await pumpAppearance(tester);

      expect(find.byType(SettingsSwitchRow), findsOneWidget);
      expect(find.text('触感震动反馈'), findsOneWidget);
      expect(
        find.text('点击按钮、切换开关与操作课表时提供轻微震动'),
        findsOneWidget,
      );

      final row = tester.widget<SettingsSwitchRow>(
        find.byType(SettingsSwitchRow),
      );
      expect(row.value, isTrue, reason: '默认开');
    });

    testWidgets('关掉开关：落库 false + 门控同步关 + 只震一次', (tester) async {
      await pumpAppearance(tester);
      advance();

      await tester.tap(find.byType(SettingsSwitchRow));
      await settle(tester);
      // 再等一小会儿让 apply() 的落库完成
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
      await settle(tester);

      // 开关这一下只允许一次 selectionClick（§6：select 由组件内部包，
      // §5 那行只写 apply，不双写 → 不能出现第二下）
      expect(calls, ['HapticFeedbackType.selectionClick']);
      expect(AppHaptics.enabled, isFalse, reason: 'apply() 必须同步门控');

      final stored = await tester.runAsync(
        () => Dao.instance.getSetting('ui_settings'),
      );
      expect(UiSettings.fromEncoded(stored).enableHaptics, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // 4. 收口组（§6 八类共用组件）
  // -------------------------------------------------------------------------
  group('收口组（§6 八类共用组件各震一次、档位正确）', () {
    testWidgets('SettingsEntryRow → tap；InkWell 自带反馈已关', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        SettingsEntryRow(title: '入口行', onTap: () => taps++),
      ));
      advance();
      await tester.tap(find.byType(SettingsEntryRow));
      await settle(tester);

      expect(taps, 1);
      expect(calls, ['HapticFeedbackType.lightImpact']);
      expect(tester.widget<InkWell>(find.byType(InkWell)).enableFeedback,
          isFalse);
    });

    testWidgets('SettingsSwitchRow → select，且 onChanged 只被调一次',
        (tester) async {
      var changes = 0;
      await tester.pumpWidget(wrap(
        SettingsSwitchRow(
          title: '开关行',
          value: false,
          onChanged: (_) => changes++,
        ),
      ));
      advance();
      await tester.tap(find.byType(SettingsSwitchRow));
      await settle(tester);

      expect(changes, 1);
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('SettingsSliderRow → 档位真的变了才 select', (tester) async {
      final values = <double>[];
      await tester.pumpWidget(wrap(
        SettingsSliderRow(
          label: '滑杆',
          valueText: '12',
          value: 12,
          min: 0,
          max: 20,
          divisions: 20,
          onChanged: values.add,
        ),
      ));
      advance();
      // 拖到最右：档位必然变化
      await tester.drag(find.byType(Slider), const Offset(500, 0));
      await settle(tester);
      expect(values, isNotEmpty);
      expect(calls, isNotEmpty, reason: '档位变化应有震动');
      expect(calls.every((c) => c == 'HapticFeedbackType.selectionClick'), isTrue);
    });

    testWidgets('AppChoiceChip → select', (tester) async {
      var selected = 0;
      await tester.pumpWidget(wrap(
        AppChoiceChip(
          label: '芯片',
          selected: false,
          onSelected: () => selected++,
        ),
      ));
      advance();
      await tester.tap(find.byType(AppChoiceChip));
      await settle(tester);

      expect(selected, 1);
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('AppDialog：取消 / 确认 → tap', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppConfirmDialog(
              context,
              title: '确认',
              message: '内容',
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      advance();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(calls, ['HapticFeedbackType.lightImpact']);

      calls.clear();
      advance();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      advance();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });

    testWidgets('AppDialog：destructive 确认 → medium', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppConfirmDialog(
              context,
              title: '删除',
              message: '确定删除？',
              confirmLabel: '删除',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      advance();
      // 标题也是「删除」，这里必须点按钮本身
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(calls, ['HapticFeedbackType.mediumImpact']);
    });

    testWidgets('AppSelectField：点开 tap、选定 select', (tester) async {
      String? picked;
      await tester.pumpWidget(wrap(
        AppSelectField<String>(
          labelText: '选择',
          value: 'a',
          options: const [
            AppSelectOption(value: 'a', shortLabel: 'A'),
            AppSelectOption(value: 'b', shortLabel: 'B'),
          ],
          onChanged: (v) => picked = v,
        ),
      ));
      advance();
      await tester.tap(find.byType(AppSelectField<String>));
      await tester.pumpAndSettle();
      expect(calls, ['HapticFeedbackType.lightImpact'], reason: '点开 = tap');

      advance();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
      expect(calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
      ], reason: '选定 = select');
    });

    testWidgets('HomeTabBar：切 Tab → tap', (tester) async {
      HomeShellTab? switched;
      await tester.pumpWidget(wrap(
        HomeTabBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (t) => switched = t,
          onTapSchedule: () {},
        ),
      ));
      advance();
      await tester.tap(find.text('设置'));
      await settle(tester);

      expect(switched, HomeShellTab.settings);
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });
  });

  // -------------------------------------------------------------------------
  // 5. 存量组（§7 全库收口）
  // -------------------------------------------------------------------------
  group('存量组（§7 全库只剩一个震动入口）', () {
    test('lib 下除 app_haptics.dart 外不再出现 HapticFeedback.', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('utils/app_haptics.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('HapticFeedback.')) offenders.add(entity.path);
      }
      expect(offenders, isEmpty,
          reason: '所有震动必须走 AppHaptics（门控 + 节流）');
    });

    test('AppHaptics 自身只用三档，不出现 heavyImpact 调用', () {
      final src = File('lib/utils/app_haptics.dart').readAsStringSync();
      expect(src.contains('lightImpact'), isTrue);
      expect(src.contains('selectionClick'), isTrue);
      expect(src.contains('mediumImpact'), isTrue);
      // 注释里说明「heavyImpact 禁用」是允许的，这里锁的是**平台调用**
      expect(src.contains('HapticFeedback.heavyImpact'), isFalse,
          reason: '§8 红线：heavy 档禁用');
    });
  });
}
