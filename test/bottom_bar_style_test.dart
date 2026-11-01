import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/widgets/home_bottom_bar.dart';
import 'package:xiaoma_timetable/widgets/home_capsule.dart';

/// 底部栏两形态的渲染断言（WB_SPEC_215 第 2/3 节）。
///
/// 两个形态都不悬浮，只换外形：
/// - 形态 A「通栏贴底」[HomeBottomBar]：整宽、贴屏幕底边、无悬浮阴影，
///   内部「课表｜设置」两键各自是胶囊圆角键（圆角 26、最小高 52）；
/// - 形态 B「胶囊贴底」[HomeCapsule]：宽度随内容自适应、贴屏幕底边（无 12 悬浮间距）、
///   无阴影，圆角 26。
///
/// 这里是纯 widget 测试：不碰库、不碰 Riverpod，直接把栏放进 Stack 底部，
/// 断言几何与外观（宽度、贴底位置、elevation、圆角），以及键的回调语义。
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

  group('形态 A：通栏贴底 HomeBottomBar', () {
    testWidgets('整宽 + 贴屏幕底边：无悬浮间距，高度 68', (tester) async {
      await pumpBar(
        tester,
        HomeBottomBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      );

      final size = tester.getSize(find.byType(HomeBottomBar));
      final topLeft = tester.getTopLeft(find.byType(HomeBottomBar));
      // 通栏：宽度撑满整宽
      expect(size.width, screenW, reason: '通栏形态栏体必须撑满整宽');
      // 贴底：栏体底边与屏幕底边齐平（没有 12 之类的悬浮间距）
      expect(topLeft.dy + size.height, screenH, reason: '通栏形态必须贴住屏幕底边');
      // 栏高 = 52 键高 + 上下各 8 内边距
      expect(size.height, kBottomBarBarHeight);
      expect(kBottomBarBarHeight, 68);
    });

    testWidgets('无悬浮阴影：栏体 elevation 为 0', (tester) async {
      await pumpBar(
        tester,
        HomeBottomBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HomeBottomBar),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0, reason: '两形态都不悬浮，不得有悬浮阴影');
      expect(material.color, isNotNull, reason: '栏体背景取表面色');
    });

    testWidgets('两键各自是胶囊圆角键：圆角 26、最小高 52、等宽平铺', (tester) async {
      await pumpBar(
        tester,
        HomeBottomBar(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      );

      final scheduleKey = find.byKey(kBottomBarScheduleKey);
      final settingsKey = find.byKey(kBottomBarSettingsKey);
      expect(scheduleKey, findsOneWidget);
      expect(settingsKey, findsOneWidget);

      final scheduleSize = tester.getSize(scheduleKey);
      final settingsSize = tester.getSize(settingsKey);
      expect(scheduleSize.height, greaterThanOrEqualTo(kBottomBarKeyHeight));
      expect(kBottomBarKeyHeight, 52);
      // 两键等宽平铺（各占一半，扣掉左右内边距与键间距）
      expect(scheduleSize.width, settingsSize.width);
      expect(
        scheduleSize.width + settingsSize.width + kBottomBarKeyGap,
        screenW - kBottomBarHorizontalPadding * 2,
      );

      final shape = tester.widget<Material>(scheduleKey).shape;
      expect(shape, isA<RoundedRectangleBorder>());
      final radius = (shape! as RoundedRectangleBorder).borderRadius;
      expect(radius, BorderRadius.circular(26));
      expect(kBottomBarRadius, 26);
    });

    testWidgets('选中态与未选中态用填充/文字颜色区分', (tester) async {
      await pumpBar(
        tester,
        HomeBottomBar(
          activeTab: HomeShellTab.settings,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      );
      final scheme = Theme.of(tester.element(find.byType(HomeBottomBar)))
          .colorScheme;
      final scheduleFill = tester
          .widget<Material>(find.byKey(kBottomBarScheduleKey))
          .color;
      final settingsFill = tester
          .widget<Material>(find.byKey(kBottomBarSettingsKey))
          .color;
      // 设置键选中：实心主题色；课表键未选中：透明填充
      expect(settingsFill, scheme.primary);
      expect(scheduleFill, Colors.transparent);
      final settingsText = tester.widget<Text>(find.text('设置'));
      final scheduleText = tester.widget<Text>(find.text('课表'));
      expect(settingsText.style?.color, scheme.onPrimary);
      expect(scheduleText.style?.color, scheme.onSurfaceVariant);
    });

    testWidgets('两键回调：课表键走 onTapSchedule，设置键走 onSelectTab', (tester) async {
      HomeShellTab? selected;
      var scheduleTaps = 0;
      await pumpBar(
        tester,
        HomeBottomBar(
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

    testWidgets('字体放大 1.3 倍：通栏栏不纵向溢出', (tester) async {
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
                    child: HomeBottomBar(
                      activeTab: HomeShellTab.schedule,
                      onSelectTab: (_) {},
                      onTapSchedule: () {},
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
    });
  });

  group('形态 B：胶囊贴底 HomeCapsule', () {
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
      // 贴底：底边与屏幕底边齐平（2.1.3 的 12 悬浮间距已删）
      expect(
        topLeft.dy + size.height,
        screenH,
        reason: '胶囊形态必须贴住屏幕底边，不再悬浮',
      );
      // 胶囊最小高 52
      expect(size.height, greaterThanOrEqualTo(kBottomBarCapsuleHeight));
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
    test('两形态都是贴底不悬浮：留白只按栏高 + 安全区算', () {
      // 关栏：16（沿用 2.1.3）
      expect(
        bottomBarGridBottomInset(
          showBottomBar: false,
          style: BottomBarStyle.bar,
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
      // 通栏贴底：68 = 52 键高 + 上下各 8
      expect(
        bottomBarGridBottomInset(
          showBottomBar: true,
          style: BottomBarStyle.bar,
        ),
        kBottomBarBarHeight,
      );
      // 胶囊贴底：52 = 胶囊高
      expect(
        bottomBarGridBottomInset(
          showBottomBar: true,
          style: BottomBarStyle.capsule,
        ),
        kBottomBarCapsuleHeight,
      );
    });

    test('叠加底部安全区：安全区只加一次，不重复计算', () {
      expect(
        bottomBarGridBottomPadding(
          34,
          showBottomBar: true,
          style: BottomBarStyle.bar,
        ),
        34 + kBottomBarBarHeight,
      );
      expect(
        bottomBarGridBottomPadding(
          34,
          showBottomBar: true,
          style: BottomBarStyle.capsule,
        ),
        34 + kBottomBarCapsuleHeight,
      );
      expect(
        bottomBarGridBottomPadding(
          34,
          showBottomBar: false,
          style: BottomBarStyle.bar,
        ),
        34 + 16,
      );
      // 异常值（负数/无穷）按 0 处理，绝不把 NaN 塞进 EdgeInsets
      expect(
        bottomBarGridBottomPadding(
          -1,
          showBottomBar: true,
          style: BottomBarStyle.bar,
        ),
        kBottomBarBarHeight,
      );
    });
  });
}

void _noop(HomeShellTab _) {}
void _noopVoid() {}
