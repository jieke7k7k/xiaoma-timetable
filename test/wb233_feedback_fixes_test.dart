import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/pages/time_settings_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/settings_entry_row.dart';
import 'package:xiaoma_timetable/ui/settings_line_frame.dart';

/// WB_SPEC_233 新增回归测试（2.5.0 真机反馈跟进修复）：
///
/// 1. §2 预览外框线用线框 Token、表头/时间列两条基准分界线常显且网格十字线受开关控制；
/// 2. §3 入口行箭头与值文字右缘对齐、长值 ellipsis 不挤爆标题；
/// 3. §4 全局 AppBar 关掉 M3 滚动染色（浅/深两处）；
/// 4. §5 作息页三段各成独立框、间隔行框外居中纯文字、单节行无 ▷/▢ 且时间块仍弹 picker、
///    段头左右分栏、节次范围按实际分段点算（14 节时晚上是 10–14）；
/// 5. §6 两默认值翻转 + `v250_defaults_migrated` 一次性迁移。
///
/// 变异自检：把任一修法改回旧实现（外框回 outlineVariant、值区回 Flexible、
/// appBarTheme 去掉两行、段头回「N 节 · 时间」、默认值回 true/false）对应用例必挂。
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

  // ── §3 入口行对齐 ───────────────────────────────────────────────
  group('§3 入口行箭头与值文字对齐', () {
    /// 手机尺寸视口（逻辑 390 宽）下摆一列入口行：标题/值长短不一，
    /// 还带一个色块 valueWidget 行。
    Future<void> pumpRows(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SettingsEntryRow(title: '显示字体', value: '系统默认'),
                SettingsEntryRow(title: '课表网格与表头', value: '自适应'),
                SettingsEntryRow(
                  title: '课程卡片样式',
                  subtitle: '卡片圆角、字号大小、教室与教师显示',
                  value: '12px · 100%',
                ),
                SettingsEntryRow(
                  title: '界面主题色',
                  valueWidget: Container(
                    key: const Key('theme_dot'),
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  value: '可可棕',
                ),
                SettingsEntryRow(title: '无值行'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('多行 chevron 横坐标相同，且钉在最右缘（内边距 16）', (tester) async {
      await pumpRows(tester);
      final chevrons = find.byIcon(Icons.chevron_right);
      expect(chevrons, findsNWidgets(5));

      final rights = chevrons
          .evaluate()
          .map((e) => (e.renderObject as RenderBox).localToGlobal(Offset.zero).dx +
              (e.renderObject as RenderBox).size.width)
          .toList();
      for (final dx in rights) {
        expect(dx, closeTo(rights.first, 0.01),
            reason: '8 行入口的 › 必须落在同一条竖线上');
      }
      expect(rights.first, closeTo(390 - 16, 0.01),
          reason: '箭头钉在行内右缘（左右内边距 16）');
    });

    testWidgets('值文字右缘相同（含色块行）', (tester) async {
      await pumpRows(tester);
      Rect rectOf(String text) => tester.getRect(find.text(text));

      final base = rectOf('系统默认').right;
      for (final value in ['自适应', '12px · 100%', '可可棕']) {
        expect(rectOf(value).right, closeTo(base, 0.01),
            reason: '值文字右缘要对齐成一条竖线：$value');
      }
      // 色块行：色块在值文字左侧，不把文字挤到别处
      expect(
        rectOf('可可棕').right,
        closeTo(base, 0.01),
        reason: '带 valueWidget 的行同样对齐（色块在文字之前）',
      );
      final dot = tester.getRect(find.byKey(const Key('theme_dot')));
      expect(dot.right, lessThan(rectOf('可可棕').left));
    });

    testWidgets('长值只在屏宽 45% 内 ellipsis，不挤爆标题', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const longTitle = '课程卡片样式与教室教师备注的显示细节';
      const longValue = '超长值文字超长值文字超长值文字超长值文字超长值文字';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingsEntryRow(title: longTitle, value: longValue),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '长值不得溢出（RenderFlex overflow）');
      final valueRect = tester.getRect(find.text(longValue));
      expect(valueRect.width, lessThanOrEqualTo(390 * 0.45 + 0.01),
          reason: '值区上界是屏宽 45%');
      // 值确实做了省略号（不是硬撑开布局）
      expect(
        tester.renderObject<RenderParagraph>(find.text(longValue)).didExceedMaxLines,
        isTrue,
        reason: '超长值在 45% 内 ellipsis',
      );
      // 标题仍保住自己的宽度（旧实现值会跟着字长跑、把标题挤没）
      final titleRect = tester.getRect(find.text(longTitle));
      expect(titleRect.width, greaterThan(390 * 0.35),
          reason: '标题独享 Expanded，长值最多占 45%，标题不得被腰斩');
      // 值仍右对齐，箭头仍最右
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right));
      expect(chevron.right, closeTo(390 - 16, 0.01));
      expect(valueRect.right, closeTo(chevron.left - 6, 0.01));
    });
  });

  // ── §2 预览外框线 ───────────────────────────────────────────────
  group('§2 实时预览外框线与基准分界线', () {
    List<TimeSlot> slots() => List.generate(
          6,
          (i) => TimeSlot(
            section: i + 1,
            startTime: '08:00',
            endTime: '08:45',
          ),
        );

    Future<void> pumpPreview(
      WidgetTester tester, {
      required bool dark,
      required bool showGridLines,
    }) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: Theme(
              // MaterialApp 换主题有 200ms 过渡，显式给 Theme 免得读到上一帧
              data: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              child: Preview(
                ui: UiSettings(showGridLines: showGridLines),
                columnCount: 5,
                slots: slots(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    BoxDecoration outerDecoration(WidgetTester tester) {
      final container = tester.widget<Container>(
        find
            .descendant(of: find.byType(Preview), matching: find.byType(Container))
            .first,
      );
      // 外框画在 foregroundDecoration：表头底色与网格都压不住它
      return container.foregroundDecoration! as BoxDecoration;
    }

    testWidgets('浅色外框 #E5E7EB、深色外框纯白 9%，粗细 1.0', (tester) async {
      await pumpPreview(tester, dark: false, showGridLines: false);
      var border = outerDecoration(tester).border! as Border;
      expect(border.top.color, SettingsLineFrame.kLightBorder);
      expect(border.top.width, 1.0);
      expect(border.bottom.color, SettingsLineFrame.kLightBorder);
      expect(border.left.color, SettingsLineFrame.kLightBorder);

      await pumpPreview(tester, dark: true, showGridLines: false);
      border = outerDecoration(tester).border! as Border;
      expect(
        border.top.color,
        Colors.white.withValues(alpha: SettingsLineFrame.kDarkBorderAlpha),
      );
      expect(border.right.color, border.top.color);
      expect(border.top.width, 1.0);
    });

    testWidgets('网格线关：两条基准分界线常显，课程区无十字线', (tester) async {
      await pumpPreview(tester, dark: false, showGridLines: false);
      expect(find.byKey(kPreviewHeaderBaselineKey), findsOneWidget);
      expect(find.byKey(kPreviewAxisBaselineKey), findsOneWidget);
      expect(gridPainter(tester), findsNothing,
          reason: 'showGridLines=false 时不得无视开关常画十字线');
    });

    testWidgets('网格线开：十字线出现，基准分界线仍在', (tester) async {
      await pumpPreview(tester, dark: false, showGridLines: true);
      expect(find.byKey(kPreviewHeaderBaselineKey), findsOneWidget);
      expect(find.byKey(kPreviewAxisBaselineKey), findsOneWidget);
      expect(gridPainter(tester), findsOneWidget);
    });
  });

  // ── §4 全局 AppBar ──────────────────────────────────────────────
  group('§4 全局 AppBar 滚动不变色', () {
    testWidgets('浅色/深色 appBarTheme 都关掉 surfaceTint 与 scrolledUnderElevation',
        (tester) async {
      PackageInfo.setMockInitialValues(
        appName: '小马课表',
        packageName: 'com.example.simple_timetable',
        version: '2.5.0',
        buildNumber: '39',
        buildSignature: '',
      );
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await HttpOverrides.runZoned(
          () async {
            await tester.pumpWidget(
              const ProviderScope(child: SimpleTimetableApp()),
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
        );
      });
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      for (final entry in {'浅色': app.theme!, '深色': app.darkTheme!}.entries) {
        final bar = entry.value.appBarTheme;
        expect(bar.surfaceTintColor, Colors.transparent,
            reason: '${entry.key}顶栏不得叠 surfaceTint 染色');
        expect(bar.scrolledUnderElevation, 0,
            reason: '${entry.key}顶栏滚动时不得起投影');
        // 底色不写死：AppBar 与 Scaffold 默认都取 colorScheme.surface
        expect(bar.backgroundColor, isNull);
        expect(bar.toolbarHeight, 48, reason: '高 48 不动');
      }

      await tester.pump(const Duration(seconds: 11));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── §5 作息时间页重构 ───────────────────────────────────────────
  group('§5 作息时间页重构', () {
    Future<void> pumpTimePage(
      WidgetTester tester, {
      List<Override> overrides = const [],
    }) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: overrides,
            child: const MaterialApp(home: TimeSettingsPage()),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// 默认只展开「当前时段」，单节行用例要先把上午段展开（与跑测试的钟点无关）
    Future<void> ensureMorningExpanded(WidgetTester tester) async {
      if (find.text('第 1 节').evaluate().isNotEmpty) return;
      await tester.tap(find.text('上午'));
      await tester.pumpAndSettle();
    }

    testWidgets('三段各成独立框（1 全局规则 + 3 段），组标题在框外', (tester) async {
      await pumpTimePage(tester);
      expect(find.byType(SettingsLineFrame), findsNWidgets(4));
      expect(find.byType(ExpansionTile), findsNWidgets(3));
      // 组标题在框外：它是 SettingsGroupHeader，不是某个框的标题
      expect(find.text('各节上下课时间（点击时间直接修改）'), findsOneWidget);
      for (final band in TimeBand.values) {
        final frame = tester.widget<SettingsLineFrame>(
          find.ancestor(
            of: find.byKey(Key('time_band_${band.name}')),
            matching: find.byType(SettingsLineFrame),
          ),
        );
        expect(frame.showTitle, isFalse, reason: '段框不另起框标题');
        expect(frame.dividers, isFalse);
        expect(
          find.descendant(
            of: find.byKey(Key('time_band_${band.name}')),
            matching: find.byType(ExpansionTile),
          ),
          findsOneWidget,
          reason: '一段一框，框内只有一个段头',
        );
      }
    });

    testWidgets('午休/晚餐间隔行移到框外，纯文字居中、无图标无 emoji', (tester) async {
      await pumpTimePage(tester);
      for (final text in [
        '午休 12:00 – 14:00 · 约 2 小时',
        '晚餐 17:10 – 18:00 · 约 50 分钟',
      ]) {
        expect(find.text(text), findsOneWidget);
        final finder = find.text(text);
        // 不在任何线框里
        expect(
          find.ancestor(of: finder, matching: find.byType(SettingsLineFrame)),
          findsNothing,
          reason: '间隔行必须移到框外留白区',
        );
        // 纯文字居中：水平中心≈屏宽一半
        final rect = tester.getRect(finder);
        expect(rect.center.dx, closeTo(390 / 2, 1.0), reason: '间隔行居中');
        // 36dp 高的居中条
        final box = find.ancestor(of: finder, matching: find.byType(SizedBox)).first;
        expect(tester.getSize(box).height, 36);
      }
      // 无图标、无 emoji
      expect(
        find.descendant(
          of: find.byType(TimeSettingsPage),
          matching: find.byIcon(Icons.access_time),
        ),
        findsNothing,
      );
    });

    testWidgets('单节行：第 X 节 + 两个时间块，无 ▷/▢ 图标，点时间块仍弹 picker', (tester) async {
      await pumpTimePage(tester);
      // 默认展开的是当前时段；把上午段展开，验证第一节的单节行
      await ensureMorningExpanded(tester);
      expect(find.text('第 1 节'), findsOneWidget);
      expect(
        find.byIcon(Icons.play_arrow_outlined),
        findsNothing,
        reason: '单节行不再用 ▷ 开始按钮',
      );
      expect(find.byIcon(Icons.stop_outlined), findsNothing);

      // 时间块尺寸与样式（68×30、圆角 8）
      final chip = find.byKey(const ValueKey('slot_time_1_start'));
      expect(chip, findsOneWidget);
      final chipRect = tester.getRect(chip);
      expect(chipRect.width, 68);
      expect(chipRect.height, 30);
      final box = tester.widget<Container>(
        find.descendant(of: chip, matching: find.byType(Container)).first,
      );
      final deco = box.decoration! as BoxDecoration;
      expect((deco.borderRadius! as BorderRadius).topLeft.x, 8);
      expect(
        deco.color,
        Theme.of(tester.element(chip)).brightness == Brightness.dark
            ? const Color(0xFF222428)
            : const Color(0xFFF3F4F6),
      );

      // 点开仍是 showTimePicker（helpText 一字未改）
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('第 1 节上课时间'), findsOneWidget,
          reason: '点时间块仍弹 showTimePicker，helpText 未改');
    });

    testWidgets('段头左右分栏：左名称带节次范围，右时间 + 自带箭头', (tester) async {
      await pumpTimePage(tester);
      expect(find.text('（第 1–5 节）'), findsOneWidget);
      expect(find.text('（第 6–9 节）'), findsOneWidget);
      expect(find.text('（第 10–13 节）'), findsOneWidget);
      expect(find.text('08:00 – 12:00'), findsOneWidget);

      final name = tester.getRect(find.text('上午'));
      final range = tester.getRect(find.text('（第 1–5 节）'));
      final time = tester.getRect(find.text('08:00 – 12:00'));
      expect(range.left, greaterThan(name.right - 0.01), reason: '节次范围紧跟名称');
      // 时间在右半栏（测试字体下文字偏宽，按「靠右」而非「紧接范围」断言）
      expect(time.left, greaterThan(name.right), reason: '时间在名称右侧');
      expect(time.right, greaterThan(390 / 2 + 100), reason: '时间靠右排，不挤在名称后');
      expect(time.top, closeTo(name.top, 10), reason: '同一行左右分栏，不上下堆叠');

      // 段头 52dp
      final tile = tester.widget<ExpansionTile>(
        find.descendant(
          of: find.byKey(const Key('time_band_morning')),
          matching: find.byType(ExpansionTile),
        ),
      );
      expect(tile.minTileHeight, 52);
    });

    testWidgets('14 节时晚上段是 10–14 节（不得写死 10–13）', (tester) async {
      final slots = List.generate(
        14,
        (i) => TimeSlot(
          section: i + 1,
          startTime: '0${8 + i ~/ 2}:00',
          endTime: '0${8 + i ~/ 2}:45',
        ),
      );
      await pumpTimePage(
        tester,
        overrides: [
          timeSlotsProvider.overrideWith(() => _FakeSlotsNotifier(slots)),
          segmentSettingsProvider.overrideWith(
            () => _FakeSegmentNotifier(5, 9),
          ),
        ],
      );
      expect(find.text('（第 1–5 节）'), findsOneWidget);
      expect(find.text('（第 6–9 节）'), findsOneWidget);
      expect(find.text('（第 10–14 节）'), findsOneWidget,
          reason: '节次范围按实际分段点算，14 节时晚上是 10–14');
      expect(find.text('（第 10–13 节）'), findsNothing);
    });
  });

  // ── §6 默认值翻转 + 一次性迁移 ─────────────────────────────────
  group('§6 两默认值翻转 + 一次性迁移', () {
    test('默认值：底部栏默认关、上课播报默认开（构造与反序列化两处一致）', () {
      const ui = UiSettings();
      expect(ui.showBottomBar, isFalse);
      expect(ui.showClassBroadcast, isTrue);
      final fromEmpty = UiSettings.fromEncoded('{}');
      expect(fromEmpty.showBottomBar, isFalse);
      expect(fromEmpty.showClassBroadcast, isTrue);
    });

    test('标志位未置：老库两值被翻成新默认并落盘，标志置 1', () async {
      await Dao.instance.setSetting(
        'ui_settings',
        '{"showBottomBar": true, "showClassBroadcast": false}',
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ui = await container.read(uiSettingsProvider.future);
      expect(ui.showBottomBar, isFalse, reason: '老用户升级后底栏默认关');
      expect(ui.showClassBroadcast, isTrue, reason: '老用户升级后播报默认开');

      expect(await Dao.instance.getSetting(UiSettingsNotifier.kDefaultsMigratedKey), '1');
      final stored = UiSettings.fromEncoded(
        await Dao.instance.getSetting('ui_settings'),
      );
      expect(stored.showBottomBar, isFalse, reason: '迁移结果要落盘');
      expect(stored.showClassBroadcast, isTrue);
    });

    test('标志位置 1 后：用户手动改的值不再被覆盖', () async {
      await Dao.instance.setSetting(
        'ui_settings',
        '{"showBottomBar": true, "showClassBroadcast": false}',
      );
      await Dao.instance.setSetting(UiSettingsNotifier.kDefaultsMigratedKey, '1');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ui = await container.read(uiSettingsProvider.future);
      expect(ui.showBottomBar, isTrue, reason: '只跑一次，用户自己的开关说了算');
      expect(ui.showClassBroadcast, isFalse);
    });

    test('新安装（库里没有 ui_settings）：直接吃新默认并立标志', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final ui = await container.read(uiSettingsProvider.future);
      expect(ui.showBottomBar, isFalse);
      expect(ui.showClassBroadcast, isTrue);
      expect(await Dao.instance.getSetting(UiSettingsNotifier.kDefaultsMigratedKey), '1');
      // 迁移不碰提醒开关与其它设置键（不弹权限、不改通知）
      expect(await Dao.instance.getSetting('reminder.enabled'), isNull);
    });
  });
}

/// 预览网格十字线的画笔（_PreviewGridPainter 是私有类，按 runtimeType 找）
Finder gridPainter(WidgetTester tester) => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter != null &&
          w.painter.runtimeType.toString().contains('PreviewGridPainter'),
    );

class _FakeSlotsNotifier extends TimeSlotsNotifier {
  _FakeSlotsNotifier(this.slots);

  final List<TimeSlot> slots;

  @override
  Future<List<TimeSlot>> build() async => slots;
}

class _FakeSegmentNotifier extends SegmentSettingsNotifier {
  _FakeSegmentNotifier(this.lunch, this.dinner);

  final int lunch;
  final int dinner;

  @override
  Future<SegmentSettings> build() async => SegmentSettings(
        lunchAfterSection: lunch,
        dinnerAfterSection: dinner,
      );
}
