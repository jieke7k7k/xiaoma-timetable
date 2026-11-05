
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/ui/liquid_glass.dart';
import 'package:xiaoma_timetable/widgets/home_capsule.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 底部栏两形态的渲染断言（WB_SPEC_215 第 2/3 节；WB_SPEC_216 第 1 节改形态）。
///
/// 两个形态都贴底、都不悬浮，只换外形：
/// - 形态 A「图标+文字标签栏」[HomeTabBar]（默认）：整宽、贴屏幕底边、无悬浮阴影、
///   顶部一条细分割线（浅色 0.8dp／深色 0.6dp，2.1.7 WB_SPEC_218 第 ② 节），
///   两格等宽（图标在上、文字在下），
///   选中态图标与文字同为琥珀黄，未选中态同为灰；
/// - 形态 B「胶囊占位式」[HomeCapsule]（2.1.7 WB_SPEC_218 第 ① 节改占位式，
///   不再贴底）：宽度随内容自适应、在主布局底部专属槽位内居中、无阴影、圆角 26。
///
/// 2.1.4 的「通栏贴底」形态（HomeBottomBar）已删除，本文件不再有它的用例。
///
/// 这里是纯 widget 测试：不碰库、不碰 Riverpod，直接把栏放进 Stack 底部，
/// 断言几何与外观（宽度、贴底位置、elevation、分割线、颜色、格宽），以及键的回调语义。
void main() {
  /// 屏幕尺寸（测试默认 800×600：宽 800、高 600）
  const double screenW = 800;
  const double screenH = 600;

  /// 把栏按 HomeShell 里的方式钉在屏幕底部
  Future<void> pumpBar(WidgetTester tester, Widget bar) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              Positioned(left: 0, right: 0, bottom: 0, child: bar),
            ],
          ),
        ),
      ),
    );
  }

  Widget tabBarAtBottom({HomeShellTab active = HomeShellTab.schedule}) =>
      HomeTabBar(
        activeTab: active,
        onSelectTab: _noop,
        onTapSchedule: _noopVoid,
      );

  /// HomeShell 里胶囊形态的实际包法：贴底 + 居中 + SafeArea
  Widget capsuleAtBottom() => const SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: HomeCapsule(
        activeTab: HomeShellTab.schedule,
        onSelectTab: _noop,
        onTapSchedule: _noopVoid,
      ),
    ),
  );

  group('形态 A：图标+文字标签栏 HomeTabBar（默认）', () {
    testWidgets('整宽 + 贴屏幕底边：无悬浮间距，实测高度 64', (tester) async {
      await pumpBar(tester, tabBarAtBottom());

      final size = tester.getSize(find.byType(HomeTabBar));
      final topLeft = tester.getTopLeft(find.byType(HomeTabBar));
      // 整宽：宽度撑满整宽
      expect(size.width, screenW, reason: '标签栏形态栏体必须撑满整宽');
      // 贴底：栏体底边与屏幕底边齐平（没有悬浮间距）
      expect(topLeft.dy + size.height, screenH, reason: '标签栏必须贴住屏幕底边');
      // 栏高 = 该 widget 的实测高度（图标 24 + 间距 4 + 文字 + 上下内边距 10）
      expect(size.height, kBottomBarTabHeight);
      expect(kBottomBarTabHeight, 64);
      expect(HomeTabBar.height, size.height, reason: '栏体高度常量与实测一致');
    });

    testWidgets('无悬浮阴影：栏体 elevation 为 0（留白口径与实测同高）', (tester) async {
      await pumpBar(tester, tabBarAtBottom());
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HomeTabBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0, reason: '两形态都不悬浮，不得有悬浮阴影');
      expect(material.shadowColor, Colors.transparent);
      expect(material.color, isNotNull, reason: '栏体背景取表面色');
      // 留白口径用的就是这一栏的实测高度
      expect(
        bottomBarGridBottomInset(
          showBottomBar: true,
          style: BottomBarStyle.tab,
        ),
        tester.getSize(find.byType(HomeTabBar)).height,
      );
    });

    testWidgets('顶部一条细分割线（浅色 0.8dp）', (tester) async {
      await pumpBar(tester, tabBarAtBottom());

      final box = tester.widget<DecoratedBox>(
        find.byKey(kHomeTabBarDividerKey),
      );
      final decoration = box.decoration as BoxDecoration;
      final border = decoration.border!;
      expect(border, isA<Border>());
      expect(
        border.top.width,
        kBottomBarDividerWidthLight,
        reason: '标签栏顶部细分割线：浅色 0.8dp（WB_SPEC_218 第 ② 节）',
      );
      expect(bottomBarDividerWidth(Brightness.light), 0.8);
      // 只有顶边有线，其余三边没有
      final sides = border as Border;
      expect(sides.bottom, BorderSide.none);
      expect(sides.left, BorderSide.none);
      expect(sides.right, BorderSide.none);
      // 线的颜色不透明（取主题 outline 的低透明度版本）
      expect(border.top.color.a, greaterThan(0));
      expect(border.top.style, BorderStyle.solid);
    });

    testWidgets('两格等宽：各占一半，图标在上、文字在下', (tester) async {
      await pumpBar(tester, tabBarAtBottom());

      final scheduleKey = find.byKey(kHomeTabBarScheduleKey);
      final settingsKey = find.byKey(kHomeTabBarSettingsKey);
      expect(scheduleKey, findsOneWidget);
      expect(settingsKey, findsOneWidget);

      final scheduleSize = tester.getSize(scheduleKey);
      final settingsSize = tester.getSize(settingsKey);
      expect(scheduleSize.width, settingsSize.width, reason: '两格必须等宽');
      expect(
        scheduleSize.width + settingsSize.width,
        closeTo(screenW, 0.5),
        reason: '两格等分整宽',
      );

      // 图标在上、文字在下：同一格里 Icon 的底部在 Text 顶部之上，且水平居中
      for (final key in <Key>[kHomeTabBarScheduleKey, kHomeTabBarSettingsKey]) {
        final iconRect = tester.getRect(
          find.descendant(of: find.byKey(key), matching: find.byType(Icon)),
        );
        final textRect = tester.getRect(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        );
        expect(
          iconRect.bottom,
          lessThanOrEqualTo(textRect.top + 0.5),
          reason: '图标必须排在文字上方',
        );
        expect(
          iconRect.center.dx,
          closeTo(tester.getRect(find.byKey(key)).center.dx, 1.0),
          reason: '图标水平居中',
        );
      }
    });

    testWidgets('选中态前景色按主题分档：浅色深褐黑、未选中态灰', (tester) async {
      // 选「设置」：设置格深褐黑、课表格灰
      await pumpBar(tester, tabBarAtBottom(active: HomeShellTab.settings));
      final scheme = Theme.of(
        tester.element(find.byType(HomeTabBar)),
      ).colorScheme;
      expect(scheme.brightness, Brightness.light);

      final settingsIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kHomeTabBarSettingsKey),
          matching: find.byType(Icon),
        ),
      );
      final settingsText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(kHomeTabBarSettingsKey),
          matching: find.byType(Text),
        ),
      );
      final scheduleIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kHomeTabBarScheduleKey),
          matching: find.byType(Icon),
        ),
      );
      final scheduleText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(kHomeTabBarScheduleKey),
          matching: find.byType(Text),
        ),
      );

      // 金黄基色仍是 2.1.5 的琥珀黄（液态滑块渐变用它），前景色与滑块分家；
      // 不用主题 primary（本项目默认种子色是雾绿 / 可可棕一类）。
      expect(HomeTabBar.activeColor, const Color(0xFFFFB300));
      expect(HomeTabBar.activeColor, Colors.amber[600]);
      expect(settingsIcon.color, isNot(scheme.primary));
      // 2.1.7（WB_SPEC_218 第 ② 节）：滑块降到半透明金黄后，浅色主题前景色
      // 改用深褐黑 #1C1917（压在金黄上对比度 ≥ 4.5:1），不再沿用金黄系。
      expect(kTabBarActiveColorLight, const Color(0xFF1C1917));
      expect(settingsIcon.color, HomeTabBar.activeColorFor(scheme));
      expect(settingsIcon.color, kTabBarActiveColorLight);
      expect(settingsText.style?.color, kTabBarActiveColorLight);
      // 深褐黑压在滑块最亮端 #FFE066 上仍看得清
      expect(
        _contrastRatio(settingsIcon.color!, const Color(0xFFFFE066)),
        greaterThanOrEqualTo(4.5),
        reason: '深褐黑压在金黄滑块上对比度要够',
      );
      // 未选中：图标与文字同为 onSurfaceVariant 灰
      expect(scheduleIcon.color, scheme.onSurfaceVariant);
      expect(scheduleText.style?.color, scheme.onSurfaceVariant);
      expect(scheduleIcon.color, isNot(HomeTabBar.activeColorFor(scheme)));
      expect(_isGolden(scheduleIcon.color!), isFalse, reason: '未选中态是灰，不是金黄');
    });

    testWidgets('深色主题：选中态换暖白（与浅色主题的深褐黑分档）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: tabBarAtBottom(active: HomeShellTab.settings),
                ),
              ],
            ),
          ),
        ),
      );
      final scheme = Theme.of(
        tester.element(find.byType(HomeTabBar)),
      ).colorScheme;
      expect(scheme.brightness, Brightness.dark);

      final settingsIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kHomeTabBarSettingsKey),
          matching: find.byType(Icon),
        ),
      );
      // 2.1.7（WB_SPEC_218 第 ② 节）：深色主题前景色改为暖白 #FEF3C7，
      // 压在压暗的金黄滑块上对比度 ≥ 4.5:1，不再是 2.1.6 的浅金黄。
      expect(kTabBarActiveColorDark, const Color(0xFFFEF3C7));
      expect(HomeTabBar.activeColorFor(scheme), kTabBarActiveColorDark);
      expect(settingsIcon.color, kTabBarActiveColorDark);
      // 深色滑块是 28%→18% 低不透明金黄叠加在 #18181C 栏底上，有效色很暗，
      // 暖白压上去仍有对比度（按最亮端 #F59F00 28% 叠加算，最保守）
      final effectiveSlider = _over(
        kLiquidSliderGradientDark.first,
        kLiquidGlassSurfaceColorDark,
      );
      expect(
        _contrastRatio(settingsIcon.color!, effectiveSlider),
        greaterThanOrEqualTo(4.5),
        reason: '暖白压在压暗后的滑块上要看得清',
      );
      // 未选中态仍是灰
      final scheduleIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kHomeTabBarScheduleKey),
          matching: find.byType(Icon),
        ),
      );
      expect(scheduleIcon.color, scheme.onSurfaceVariant);
    });

    testWidgets('两格文案仍是「课表」「设置」，键数恒为 2', (tester) async {
      await pumpBar(tester, tabBarAtBottom());
      expect(find.text('课表'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('我的'), findsNothing, reason: '右边那格仍叫「设置」，不改名');
      expect(
        tester
            .widgetList<InkWell>(
              find.descendant(
                of: find.byType(HomeTabBar),
                matching: find.byType(InkWell),
              ),
            )
            .length,
        2,
      );
    });

    testWidgets('两格回调：课表格走 onTapSchedule，设置格走 onSelectTab', (tester) async {
      HomeShellTab? selected;
      var scheduleTaps = 0;
      await pumpBar(
        tester,
        HomeTabBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (t) => selected = t,
          onTapSchedule: () => scheduleTaps++,
        ),
      );

      await tester.tap(find.text('设置'));
      expect(selected, HomeShellTab.settings);
      await tester.tap(find.text('课表'));
      expect(scheduleTaps, 1);
    });

    testWidgets('底部安全区：栏体自己吃掉 SafeArea，高度 = 64 + 安全区', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  const SizedBox.expand(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: HomeTabBar(
                      activeTab: HomeShellTab.schedule,
                      onSelectTab: _noop,
                      onTapSchedule: _noopVoid,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(HomeTabBar));
      expect(size.height, kBottomBarTabHeight + 34);
      expect(
        tester.getBottomRight(find.byType(HomeTabBar)).dy,
        closeTo(screenH, 0.5),
        reason: '含安全区也仍贴屏幕底边',
      );
    });

    testWidgets('字体放大 1.3 倍：标签栏不纵向溢出', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: Stack(
                children: [
                  const SizedBox.expand(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: HomeTabBar(
                      activeTab: HomeShellTab.schedule,
                      onSelectTab: _noop,
                      onTapSchedule: _noopVoid,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('课表'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });
  });

  group('形态 B：胶囊贴底 HomeCapsule（保留）', () {
    testWidgets('胶囊宽度随内容自适应（不是整宽）+ 贴屏幕底边', (tester) async {
      await pumpBar(tester, capsuleAtBottom());

      final size = tester.getSize(find.byType(HomeCapsule));
      final topLeft = tester.getTopLeft(find.byType(HomeCapsule));
      // 宽度随内容自适应：明显小于整宽，且水平居中
      expect(size.width, lessThan(screenW));
      expect(size.width, greaterThan(0));
      expect(
        topLeft.dx + size.width / 2,
        closeTo(screenW / 2, 0.5),
        reason: '胶囊仍居中',
      );
      // 贴底：底边与屏幕底边齐平
      expect(
        topLeft.dy + size.height,
        screenH,
        reason: '胶囊形态必须贴住屏幕底边，不再悬浮',
      );
      // 胶囊最小高 52
      expect(size.height, greaterThanOrEqualTo(kBottomBarKeyHeight));
      expect(kBottomBarKeyHeight, 52);
    });

    testWidgets('无悬浮阴影：胶囊 elevation 为 0、圆角 26', (tester) async {
      await pumpBar(tester, capsuleAtBottom());

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HomeCapsule),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0, reason: '胶囊贴底后不再有悬浮阴影');
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(26));
    });
  });

  group('几何常量与网格留白口径', () {
    test('三态留白：关栏 16 / 标签栏 64 / 胶囊占位式 0', () {
      // 关栏：16（沿用 2.1.3）
      expect(
        bottomBarGridBottomInset(
          showBottomBar: false,
          style: BottomBarStyle.tab,
        ),
        16,
      );
      expect(
        bottomBarGridBottomInset(
          showBottomBar: false,
          style: BottomBarStyle.capsule,
        ),
        16,
      );
      // 标签栏（默认）：64 = 该 widget 实测高度
      expect(
        bottomBarGridBottomInset(
          showBottomBar: true,
          style: BottomBarStyle.tab,
        ),
        kBottomBarTabHeight,
      );
      expect(kBottomBarTabHeight, HomeTabBar.height);
      // 胶囊占位式：0（WB_SPEC_218 第 ① 节）——胶囊改成主布局底部一整条
      // 专属槽位，槽位自己占布局高度，网格滚动视口截断在槽位上方，
      // 不再按胶囊高度留白
      expect(
        bottomBarGridBottomInset(
          showBottomBar: true,
          style: BottomBarStyle.capsule,
        ),
        0,
      );
      expect(kCapsuleSlotHeight, 64,
          reason: '槽位最小高 64 = 胶囊 52 + 上下各 6 间隙（字体放大时随内容长高）');
    });

    test('叠加底部安全区：安全区只加一次，不重复计算', () {
      expect(
        bottomBarGridBottomPadding(
          34,
          showBottomBar: true,
          style: BottomBarStyle.tab,
        ),
        34 + kBottomBarTabHeight,
      );
      // 胶囊占位式：槽位已吃掉安全区，网格不叠加，返回 0（不重复留白）
      expect(
        bottomBarGridBottomPadding(
          34,
          showBottomBar: true,
          style: BottomBarStyle.capsule,
        ),
        0,
      );
      expect(
        bottomBarGridBottomPadding(
          34,
          showBottomBar: false,
          style: BottomBarStyle.tab,
        ),
        34 + 16,
      );
      // 异常值（负数/无穷）按 0 处理，绝不把 NaN 塞进 EdgeInsets
      expect(
        bottomBarGridBottomPadding(
          -1,
          showBottomBar: true,
          style: BottomBarStyle.tab,
        ),
        kBottomBarTabHeight,
      );
    });
  });
}

void _noop(HomeShellTab _) {}
void _noopVoid() {}

/// 是否「金黄系」：HSV 色相落在 25°~60°（琥珀黄 #FFB300 是 42°）且不是灰。
///
/// 2.1.6 起选中态不再写死 == #FFB300（浅色主题压暗、深色主题提亮），
/// 所以断言改成「色相仍是金黄」而不是「等于某个固定 RGB」——
/// 这样既能分档保证对比度，又不会让选中色跑成蓝的绿的。
bool _isGolden(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv.hue >= 25 && hsv.hue <= 60 && hsv.saturation >= 0.5;
}

/// WCAG 对比度（用于断言「深金黄压在金黄滑块上」看得清，不靠肉眼）。
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 把半透明前景色 [fg] 叠加到不透明背景色 [bg] 上，得到有效色。
///
/// 2.1.7 起滑块改成半透明金黄，对比度不能拿「不透明端点色」直接算——
/// 要先叠加到栏底/页面底色上求有效色，再与前景色比。
Color _over(Color fg, Color bg) {
  final a = fg.a;
  int blend(double f, double b) =>
      ((f * a + b * (1 - a)) * 255).round().clamp(0, 255);
  return Color.fromARGB(
    255,
    blend(fg.r, bg.r),
    blend(fg.g, bg.g),
    blend(fg.b, bg.b),
  );
}
