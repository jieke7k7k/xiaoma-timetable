import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart' show appRoutes;
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/appearance_grid_settings_page.dart';
import 'package:xiaoma_timetable/pages/card_style_page.dart';
import 'package:xiaoma_timetable/pages/font_settings_page.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/pages/time_settings_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/app_styles.dart';
import 'package:xiaoma_timetable/ui/settings_entry_row.dart';
import 'package:xiaoma_timetable/ui/settings_line_frame.dart';
import 'package:xiaoma_timetable/widgets/app_dialog.dart';

/// WB_SPEC_228 §11 新增测试：
/// 1. 三条新增联动的条件渲染（含「不留空位 / 不留分隔线」）；
/// 2. 作息三段默认展开逻辑；
/// 3. 4 个专项子页的路由跳转；
/// 4. 线框形态 A 的定值（浅色 #E5E7EB / 深色白 9% / 圆角 14 / 分隔线 0.5）。
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

  /// 拉高画布并等首帧异步 provider 就绪（与其它 FFI widget 测试同款）
  Future<void> pumpPage(
    WidgetTester tester, {
    required Widget home,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(home: home),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('切换动效行永远显示（WB_SPEC_234 删掉底栏开关后）', () {
    testWidgets('任意界面设置下切换动效行都在，不随设置变化消失', (tester) async {
      final fake = _FakeUiNotifier(const UiSettings());
      final overrides = [
        uiSettingsProvider.overrideWith(() => fake),
      ];
      await pumpPage(
        tester,
        home: const AppearanceSettingsPage(),
        overrides: overrides,
      );

      expect(find.text('切换动效'), findsOneWidget);
      expect(find.byType(SettingsEntryRow), findsNWidgets(6));
      final dividersBefore = tester
          .widgetList<Divider>(find.byType(Divider))
          .length;

      // 改任意一项界面设置（与底栏无关的主题色）→ 切换动效行仍在、行数与
      // 分隔线数都不变（此前「关栏→整行消失」的联动已随开关一并删除）
      fake.set(const UiSettings(colorSchemeId: 'grape'));
      await tester.pumpAndSettle();

      expect(find.text('切换动效'), findsOneWidget);
      expect(find.byType(SettingsEntryRow), findsNWidgets(6));
      expect(
        tester.widgetList<Divider>(find.byType(Divider)).length,
        dividersBefore,
      );
    });
  });

  group('联动 ②③：网格子页失效滑杆动态隐藏', () {
    testWidgets('自适应开→藏格子高度；网格线关→藏边框粗细（都不留空位）',
        (tester) async {
      final fake = _FakeUiNotifier(const UiSettings(
        autoFitHeight: true,
        showGridLines: false,
      ));
      await pumpPage(
        tester,
        home: const AppearanceGridSettingsPage(),
        overrides: [uiSettingsProvider.overrideWith(() => fake)],
      );

      expect(find.text('行高自适应一屏'), findsOneWidget);
      expect(find.text('显示网格线'), findsOneWidget);
      expect(find.text('课程格子高度'), findsNothing);
      expect(find.text('格子边框粗细'), findsNothing);
      expect(find.byType(SettingsSliderRow), findsNothing);
      expect(find.byType(Slider), findsNothing);
      final dividersWhenHidden =
          tester.widgetList<Divider>(find.byType(Divider)).length;

      // 两条联动同时放开 → 两个滑杆行都出现，分隔线各多一条
      fake.set(const UiSettings(
        autoFitHeight: false,
        showGridLines: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('课程格子高度'), findsOneWidget);
      expect(find.text('格子边框粗细'), findsOneWidget);
      expect(find.byType(SettingsSliderRow), findsNWidgets(2));
      expect(
        tester.widgetList<Divider>(find.byType(Divider)).length,
        dividersWhenHidden + 2,
        reason: '条件渲染不能留空位，也不能留多余分隔线',
      );
    });

    testWidgets('自适应关但网格线仍关 → 只出现格子高度滑杆', (tester) async {
      final fake = _FakeUiNotifier(const UiSettings(
        autoFitHeight: false,
        showGridLines: false,
      ));
      await pumpPage(
        tester,
        home: const AppearanceGridSettingsPage(),
        overrides: [uiSettingsProvider.overrideWith(() => fake)],
      );
      expect(find.text('课程格子高度'), findsOneWidget);
      expect(find.text('格子边框粗细'), findsNothing);
      expect(find.byType(SettingsSliderRow), findsOneWidget);
    });

    testWidgets('ⓘ 移除后原 message 一字不改改为副标题（228 §3.4）',
        (tester) async {
      final fake = _FakeUiNotifier(const UiSettings());
      await pumpPage(
        tester,
        home: const AppearanceGridSettingsPage(),
        overrides: [uiSettingsProvider.overrideWith(() => fake)],
      );
      expect(find.text('开启后，周末无课时周视图仅显示周一至周五'),
          findsOneWidget);
      expect(find.text('为当日整列添加主题色边框，默认关闭'), findsOneWidget);
      expect(find.text('关闭后左侧仅显示节次数字'), findsOneWidget);
      expect(find.text('开启时左上角显示「第 X 周 · 单周/双周」，关闭时仅显示「第 X 周」，默认关闭'),
          findsOneWidget);
      // §3.4 只留 2 处 ⓘ（显示非本周课程、行高自适应一屏），其余 4 处已改为副标题
      expect(find.byType(AppInfoIconButton), findsNWidgets(2));
    });
  });

  group('作息三段默认展开逻辑（§5）', () {
    test('currentTimeBand：06–12 上午 / 12–18 下午 / 18–次日 06 晚上', () {
      expect(currentTimeBand(DateTime(2026, 1, 1, 5, 59)),
          TimeBand.evening);
      expect(currentTimeBand(DateTime(2026, 1, 1, 6, 0)),
          TimeBand.morning);
      expect(currentTimeBand(DateTime(2026, 1, 1, 11, 59)),
          TimeBand.morning);
      expect(currentTimeBand(DateTime(2026, 1, 1, 12, 0)),
          TimeBand.afternoon);
      expect(currentTimeBand(DateTime(2026, 1, 1, 17, 59)),
          TimeBand.afternoon);
      expect(currentTimeBand(DateTime(2026, 1, 1, 18, 0)),
          TimeBand.evening);
      expect(currentTimeBand(DateTime(2026, 1, 1, 23, 30)),
          TimeBand.evening);
    });

    testWidgets('三段各成独立框（233 §5.1 去套娃），且默认只展开当前时段', (tester) async {
      await pumpPage(tester, home: const TimeSettingsPage());
      final expected = currentTimeBand(DateTime.now());
      // 全局规则框 1 个 + 三段各一个框 = 4 个（233 前是「三段共用一个大框」= 2 个）
      expect(find.byType(SettingsLineFrame), findsNWidgets(4));
      // _BandTile 是私有类，按 key 找段；默认展开只看子项在不在树里
      // （收起时 _BandTile 子项区是 0 高 SizedBox，子项不出树）。
      const firstSections = {
        TimeBand.morning: 1,
        TimeBand.afternoon: 6,
        TimeBand.evening: 10,
      };
      for (final band in TimeBand.values) {
        expect(find.byKey(Key('time_band_${band.name}')), findsOneWidget);
        expect(
          find.text('第 ${firstSections[band]} 节'),
          band == expected ? findsOneWidget : findsNothing,
          reason: '只有当前时段 $expected 默认展开，$band 应收起',
        );
      }
    });

    testWidgets('段头左右分栏：左「上午（第 1–5 节）」右「08:00 – 12:00」', (tester) async {
      await pumpPage(tester, home: const TimeSettingsPage());
      // 组标题留在框外（不再当框标题）
      expect(find.text('上下课时间（点击时间可修改）'), findsOneWidget);
      // 节次范围按实际分段点算：上午 1–5、下午 6–9、晚上 10–13（默认 13 节）
      expect(find.text('（第 1–5 节）'), findsOneWidget);
      expect(find.text('（第 6–9 节）'), findsOneWidget);
      expect(find.text('（第 10–13 节）'), findsOneWidget);
      expect(find.text('08:00 – 12:00'), findsOneWidget);
      expect(find.text('14:00 – 17:10'), findsOneWidget);
      expect(find.text('18:00 – 21:10'), findsOneWidget);
      // 左侧名称在右侧时间左边（左右分栏，不是上下堆叠）
      final name = tester.getTopLeft(find.text('上午'));
      final time = tester.getTopLeft(find.text('08:00 – 12:00'));
      expect(time.dx, greaterThan(name.dx));
      expect(time.dy, closeTo(name.dy, 8));
    });
  });

  group('子页路由跳转（§9 / §11）', () {
    Future<void> pumpRoutes(WidgetTester tester, String initialRoute) async {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // 2.5.0（WB_SPEC_233 §6）播报默认开：预置一次性迁移标志，避免被启动
      // 迁移覆盖；WB_SPEC_234 起底栏开关已删，不再需要预置它。
      await tester.runAsync(() async {
        await Dao.instance.setSetting(
          'ui_settings',
          const UiSettings().encode(),
        );
        await Dao.instance.setSetting(UiSettingsNotifier.kDefaultsMigratedKey, '1');
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              initialRoute: initialRoute,
              routes: appRoutes,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('外观父页 8 行 + 3 个线框组（WB_SPEC_235 加震动开关后）', (tester) async {
      await pumpRoutes(tester, '/settings-appearance');
      expect(find.byType(SettingsLineFrame), findsNWidgets(3));
      expect(find.byType(SettingsEntryRow), findsNWidgets(6));
      // WB_SPEC_235 §5：导航组第 2 行「触感震动反馈」是父页唯一的开关行
      expect(find.byType(SettingsSwitchRow), findsOneWidget);
      expect(find.text('触感震动反馈'), findsOneWidget);
      expect(find.byType(Preview), findsOneWidget);
      // 父页不得再直接出现滑杆 / 竖排三按钮
      expect(find.byType(Slider), findsNothing);
      expect(find.text('灵动'), findsNothing);
    });

    testWidgets('4 个专项子页均可由入口行跳入', (tester) async {
      await pumpRoutes(tester, '/settings-appearance');

      await tester.tap(find.text('课表网格与表头'));
      await tester.pumpAndSettle();
      expect(find.byType(AppearanceGridSettingsPage), findsOneWidget);
      expect(find.text('网格与表头设置'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AppearanceGridSettingsPage)))
          .pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('课程卡片样式'));
      await tester.pumpAndSettle();
      expect(find.byType(CardStylePage), findsOneWidget);
      Navigator.of(tester.element(find.byType(CardStylePage))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('显示字体'));
      await tester.pumpAndSettle();
      expect(find.byType(FontSettingsPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(FontSettingsPage))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('作息页入口行指向已注册的第 4 个子页路由', (tester) async {
      await pumpRoutes(tester, '/time-settings');
      final rows = tester.widgetList<SettingsEntryRow>(
        find.byType(SettingsEntryRow),
      ).toList();
      expect(rows.length, 2, reason: '作息父页只剩 2 行入口');
      expect(rows.first.title, '每日节数与分段');
      expect(rows.first.route, '/settings-section-rules');
      expect(appRoutes.containsKey('/settings-section-rules'), isTrue);
      expect(
        appRoutes['/settings-section-rules'],
        isNotNull,
        reason: '第 4 个专项子页须注册在真实路由表里',
      );
    });
  });

  group('线框形态 A（§7 定值）', () {
    testWidgets('浅色 #E5E7EB / 深色白 9% / 圆角 14 / 分隔线 0.5 缩进 16',
        (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              // 显式给 Theme：MaterialApp 的 AnimatedTheme 切换有 200ms 过渡，
              // 直接 pump 一帧会读到上一轮的 light theme。
              body: Theme(
                data: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                child: SettingsLineFrame(
                  title: '测试分组',
                  children: const [Text('甲'), Text('乙')],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final frame = find.byType(SettingsLineFrame);
        final container = tester.widget<Container>(
          find.descendant(of: frame, matching: find.byType(Container)).first,
        );
        final decoration = container.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        expect(
          border.top.color,
          dark
              ? Colors.white.withValues(alpha: 0.09)
              : const Color(0xFFE5E7EB),
          reason: dark ? '深色描边须为纯白 9%' : '浅色描边须为 #E5E7EB',
        );
        expect(border.top.width, 1.0);
        expect(
          (decoration.borderRadius! as BorderRadius).topLeft.x,
          AppRadii.card,
        );

        final divider = tester.widget<Divider>(
          find.descendant(of: frame, matching: find.byType(Divider)),
        );
        expect(divider.thickness, 0.5);
        expect(divider.indent, 16);
        expect(divider.endIndent, 16);
      }
    });
  });
}

/// 外观设置替身：直接改 ui_settings 状态，绕开真实落库等待，专测条件渲染。
class _FakeUiNotifier extends UiSettingsNotifier {
  _FakeUiNotifier(this.value);

  UiSettings value;

  @override
  Future<UiSettings> build() async => value;

  @override
  Future<void> apply(UiSettings next) async {
    value = next;
    state = AsyncData(next);
  }

  void set(UiSettings next) {
    value = next;
    state = AsyncData(next);
  }
}
