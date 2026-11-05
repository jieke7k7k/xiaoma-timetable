
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 底部栏（只有新标签栏一种形态）的渲染断言（WB_SPEC_215 第 2/3 节；WB_SPEC_216 第 1 节）。
///
/// 标签栏 [HomeTabBar]（默认、唯一形态）：整宽、贴屏幕底边、无悬浮阴影、
/// 顶部一条细分割线（0.5dp，outlineVariant 浅 0.45／深 0.25），
/// 两格等宽（图标在上、文字在下），
/// 选中态图标与文字同为主题 primary，未选中态同为灰。
///
/// 2.1.7 同版本修复：胶囊形态整体删除（用户定：只要新标签栏），本文件不再有
/// 它的用例；毛玻璃层整体删除（`BackdropFilter` 真机整屏漫溢），栏体只留
/// 半透明底色，栏内无任何模糊滤镜（见 liquid_bottom_bar_test.dart 的断言）。
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

  group('图标+文字标签栏 HomeTabBar（唯一形态）', () {
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
      expect(material.elevation, 0, reason: '标签栏不悬浮，不得有悬浮阴影');
      expect(material.shadowColor, Colors.transparent);
      expect(material.color, isNotNull, reason: '栏体背景取表面色');
      // 留白口径用的就是这一栏的实测高度
      expect(
        bottomBarGridBottomInset(showBottomBar: true),
        tester.getSize(find.byType(HomeTabBar)).height,
      );
    });

    testWidgets('顶部一条细分割线（0.5dp，outlineVariant 浅 0.45）', (tester) async {
      await pumpBar(tester, tabBarAtBottom());

      final box = tester.widget<DecoratedBox>(
        find.byKey(kHomeTabBarDividerKey),
      );
      final decoration = box.decoration as BoxDecoration;
      final border = decoration.border!;
      expect(border, isA<Border>());
      expect(
        border.top.width,
        0.5,
        reason: '标签栏顶部细分割线：0.5dp（Argon 方案 Q2）',
      );
      final scheme = Theme.of(
        tester.element(find.byType(HomeTabBar)),
      ).colorScheme;
      expect(border.top.color, scheme.outlineVariant.withValues(alpha: 0.45));
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

    testWidgets('选中态前景色 = 主题 primary，未选中态 onSurfaceVariant 0.60', (tester) async {
      // 选「设置」：设置格主题色、课表格灰
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

      // 选中态 = 主题 primary（跟主题走，不再固定金黄）
      expect(settingsIcon.color, scheme.primary);
      expect(settingsText.style?.color, scheme.primary);
      // 选中图标实心、未选中线框（双态图标，Argon 方案 Q1）
      expect(settingsIcon.icon, Icons.settings);
      expect(scheduleIcon.icon, Icons.calendar_today_outlined);
      // 主题色压在栏底 surface 上要看得清
      expect(
        _contrastRatio(settingsIcon.color!, scheme.surface),
        greaterThanOrEqualTo(3.0),
        reason: '主题色压在栏底上对比度要够',
      );
      // 未选中：图标与文字同为 onSurfaceVariant 0.60
      expect(
        scheduleIcon.color,
        scheme.onSurfaceVariant.withValues(alpha: 0.60),
      );
      expect(
        scheduleText.style?.color,
        scheme.onSurfaceVariant.withValues(alpha: 0.60),
      );
      expect(scheduleIcon.color, isNot(scheme.primary));
    });

    testWidgets('深色主题：选中态同样是主题 primary，未选中 0.55', (tester) async {
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
      // 深色主题选中态同样是主题 primary（跟主题走，不再固定暖白）
      expect(settingsIcon.color, scheme.primary);
      expect(settingsIcon.icon, Icons.settings);
      // 主题色压在深色栏底 surfaceContainerLow 上要看得清
      expect(
        _contrastRatio(settingsIcon.color!, scheme.surfaceContainerLow),
        greaterThanOrEqualTo(3.0),
        reason: '主题色压在深色栏底上对比度要够',
      );
      // 未选中态仍是灰（深色 0.55）
      final scheduleIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(kHomeTabBarScheduleKey),
          matching: find.byType(Icon),
        ),
      );
      expect(
        scheduleIcon.color,
        scheme.onSurfaceVariant.withValues(alpha: 0.55),
      );
      expect(scheduleIcon.icon, Icons.calendar_today_outlined);
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

  group('几何常量与网格留白口径', () {
    test('两态留白：关栏 16 / 开栏 64', () {
      // 关栏：16（沿用 2.1.3）
      expect(bottomBarGridBottomInset(showBottomBar: false), 16);
      // 开栏：64 = 该 widget 实测高度
      expect(
        bottomBarGridBottomInset(showBottomBar: true),
        kBottomBarTabHeight,
      );
      expect(kBottomBarTabHeight, HomeTabBar.height);
    });

    test('叠加底部安全区：安全区只加一次，不重复计算', () {
      expect(
        bottomBarGridBottomPadding(34, showBottomBar: true),
        34 + kBottomBarTabHeight,
      );
      expect(
        bottomBarGridBottomPadding(34, showBottomBar: false),
        34 + 16,
      );
      // 异常值（负数/无穷）按 0 处理，绝不把 NaN 塞进 EdgeInsets
      expect(
        bottomBarGridBottomPadding(-1, showBottomBar: true),
        kBottomBarTabHeight,
      );
    });
  });
}

void _noop(HomeShellTab _) {}
void _noopVoid() {}

/// WCAG 对比度（用于断言「主题色压在栏底上」看得清，不靠肉眼）。
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
