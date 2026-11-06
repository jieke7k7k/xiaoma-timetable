import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/ui/liquid_glass.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 标签栏无框选中态与动效断言（WB_SPEC_217 第 1 节；2026-11-05 按 Argon Q1
/// 方案改为无框选中态：金黄滑块已删）。
///
/// 按 Argon 方案逐条落地并逐条断言：
/// 1. **栏内没有任何模糊滤镜**：2.1.7 同版本修复——毛玻璃层（[RepaintBoundary]
///    + [BackdropFilter]）整体删除，它在真机上整屏漫溢、整片课表蒙雾；
/// 2. 底色跟主题走（浅色 surface／深色 surfaceContainerLow）、顶部细分割线
///    0.5dp（outlineVariant 浅 0.45／深 0.25）、贴底无阴影；
/// 3. 选中指示小短条：20×3dp、距栏底 5dp、容器宽 = 栏宽 50%、[AnimatedAlign]
///    对齐随选中项变化、320ms 减速曲线、切换时是「滑过去」而不是重建；
/// 4. 按压回弹：按下 0.92（90ms）、松手 1.0（350ms 弹簧）；
/// 5. 选中态图标上浮放大（实心）、颜色 / 位移 / 缩放三条过渡各自分开。
///
/// 与 `bottom_bar_style_test.dart` 的分工：那边管「布局与功能不变」（整宽、
/// 贴底、两格等宽、文案、回调、留白口径），这边管「选中态与动效」。
void main() {
  /// 屏幕尺寸（测试默认 800×600）
  const double screenW = 800;
  const double screenH = 600;

  Future<void> pumpBar(
    WidgetTester tester, {
    HomeShellTab active = HomeShellTab.schedule,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: HomeTabBar(
                  activeTab: active,
                  onSelectTab: _noop,
                  onTapSchedule: _noopVoid,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Material barMaterial(WidgetTester tester) => tester.widget<Material>(
    find
        .descendant(of: find.byType(HomeTabBar), matching: find.byType(Material))
        .first,
  );

  group('无模糊滤镜（2.1.7 同版本修复：毛玻璃层整屏漫溢已删）', () {
    testWidgets('栏内没有任何 BackdropFilter：整片课表永不蒙雾', (tester) async {
      await pumpBar(tester);

      // 栏体子树里一个模糊滤镜都不许有——滤镜层无 ClipRect 整屏漫溢，
      // sigma 从 15 降到 3.5 也没用，根子在滤镜层本身
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HomeTabBar),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      // 玻璃层的两个 Key 也随之消失（没有 RepaintBoundary 包着的滤镜层了）
      expect(find.byKey(const ValueKey('home_tab_bar_glass')), findsNothing);
      expect(find.byKey(const ValueKey('home_tab_bar_blur')), findsNothing);
    });

    testWidgets('深色主题下栏内同样没有任何 BackdropFilter', (tester) async {
      await pumpBar(tester, brightness: Brightness.dark);
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('栏体：主题底色 + 顶部细分割线 + 贴底无阴影', () {
    testWidgets('底色跟主题走：浅色 surface（不再半透白 58%）', (tester) async {
      await pumpBar(tester);

      final material = barMaterial(tester);
      final scheme = ThemeData(brightness: Brightness.light).colorScheme;
      expect(material.color, scheme.surface);
      // 不透明：跟主题 surface 一致，不再是半透明染色
      expect(material.color!.a, 1.0);
    });

    testWidgets('深色主题底色 = surfaceContainerLow', (tester) async {
      await pumpBar(tester, brightness: Brightness.dark);

      final material = barMaterial(tester);
      final scheme = ThemeData(brightness: Brightness.dark).colorScheme;
      expect(material.color, scheme.surfaceContainerLow);
      expect(material.color!.a, 1.0);
    });

    testWidgets('顶部细分割线仍在，且只画顶边（0.5dp，outlineVariant 浅 0.45）', (tester) async {
      await pumpBar(tester);

      final box = tester.widget<DecoratedBox>(find.byKey(kHomeTabBarDividerKey));
      final decoration = box.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      final scheme = ThemeData(brightness: Brightness.light).colorScheme;
      expect(border.top.width, 0.5);
      expect(border.top.color, scheme.outlineVariant.withValues(alpha: 0.45));
      expect(border.bottom, BorderSide.none);
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);
      expect(border.top.style, BorderStyle.solid);
    });

    testWidgets('顶部细分割线：深色 0.5dp，outlineVariant 0.25', (tester) async {
      await pumpBar(tester, brightness: Brightness.dark);

      final box = tester.widget<DecoratedBox>(find.byKey(kHomeTabBarDividerKey));
      final decoration = box.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      final scheme = ThemeData(brightness: Brightness.dark).colorScheme;
      expect(border.top.width, 0.5);
      expect(border.top.color, scheme.outlineVariant.withValues(alpha: 0.25));
      expect(border.bottom, BorderSide.none);
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);
    });

    testWidgets('贴底、整宽、无阴影（栏体不悬浮）', (tester) async {
      await pumpBar(tester);

      final material = barMaterial(tester);
      expect(material.elevation, 0);
      expect(material.shadowColor, Colors.transparent);
      // 装饰层也没有投影（液态栏不悬浮，不加 box-shadow）
      final decoration =
          tester.widget<DecoratedBox>(find.byKey(kHomeTabBarDividerKey))
              .decoration as BoxDecoration;
      expect(decoration.boxShadow, isNull);

      final size = tester.getSize(find.byType(HomeTabBar));
      final topLeft = tester.getTopLeft(find.byType(HomeTabBar));
      expect(size.width, screenW, reason: '仍撑满整宽');
      expect(topLeft.dy + size.height, screenH, reason: '仍贴住屏幕底边');
      expect(size.height, kBottomBarTabHeight);
    });
  });

  group('选中指示小短条（Argon 方案 Q1：无框选中态）', () {
    testWidgets('容器宽度 = 栏宽 50%，短条本体 20×3dp、距栏底 5dp', (tester) async {
      await pumpBar(tester);

      final barWidth = tester.getSize(find.byType(HomeTabBar)).width;
      final box = tester.getSize(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(kLiquidIndicatorWidthFactor, 0.5);
      expect(box.width, closeTo(barWidth * 0.5, 0.5));
      // 容器占满栏高 64（Align 取最大高），短条本体 20×3 贴在容器底部
      final rect = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(rect.height, kBottomBarTabHeight);
      final pillFinder = find.descendant(
        of: find.byKey(kHomeTabBarIndicatorBoxKey),
        matching: find.byType(DecoratedBox),
      );
      final pill = tester.getRect(pillFinder.first);
      expect(kSelectionPillWidth, 20);
      expect(kSelectionPillHeight, 3);
      expect(pill.width, closeTo(20, 0.5));
      expect(pill.height, closeTo(3, 0.5));
      // 短条水平居中在容器里、距栏底 5dp
      expect(pill.center.dx, closeTo(rect.center.dx, 0.5));
      expect(rect.bottom - pill.bottom, closeTo(kSelectionPillBottomGap, 0.5));
      expect(kSelectionPillBottomGap, 5);
      // 短条颜色 = 主题 primary（不再是金黄渐变）
      final pillBox = tester.widget<DecoratedBox>(pillFinder.first);
      final decoration = pillBox.decoration as BoxDecoration;
      final scheme = ThemeData(brightness: Brightness.light).colorScheme;
      expect(decoration.color, scheme.primary);
    });

    testWidgets('320ms 减速曲线，对齐随选中项变化（-1 / +1，贴底）', (tester) async {
      await pumpBar(tester, active: HomeShellTab.schedule);

      var align = tester.widget<AnimatedAlign>(find.byKey(kHomeTabBarIndicatorKey));
      expect(align.alignment, const Alignment(-1, 1), reason: '课表格：贴左半、贴底');
      expect(align.duration, kSelectionPillDuration);
      expect(align.duration, const Duration(milliseconds: 320));
      expect(align.curve, kSelectionPillCurve);
      expect(align.curve, Curves.easeOutCubic);

      // 切到设置格：对齐翻到贴右半
      await pumpBar(tester, active: HomeShellTab.settings);
      align = tester.widget<AnimatedAlign>(find.byKey(kHomeTabBarIndicatorKey));
      expect(align.alignment, const Alignment(1, 1), reason: '设置格：贴右半、贴底');
      expect(align.duration, const Duration(milliseconds: 320));
      expect(align.curve, kSelectionPillCurve);
    });

    testWidgets('切换后短条位置与选中项一致，且是滑过去而不是瞬移', (tester) async {
      await pumpBar(tester, active: HomeShellTab.schedule);

      final scheduleRect = tester.getRect(find.byKey(kHomeTabBarScheduleKey));
      var indicator = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(
        indicator.center.dx,
        closeTo(scheduleRect.center.dx, 1.0),
        reason: '选中课表时短条对齐课表格',
      );

      // 切到设置：先只推进 1ms——短条应该还停在左边（说明是动画）
      await pumpBar(tester, active: HomeShellTab.settings);
      await tester.pump(const Duration(milliseconds: 1));
      indicator = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(
        indicator.center.dx,
        lessThan(tester.getSize(find.byType(HomeTabBar)).width / 2),
        reason: '切换瞬间短条还没跳到右边，是滑过去的',
      );

      // 320ms 后到位：与设置格对齐
      await tester.pump(const Duration(milliseconds: 320));
      final settingsRect = tester.getRect(find.byKey(kHomeTabBarSettingsKey));
      indicator = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(
        indicator.center.dx,
        closeTo(settingsRect.center.dx, 1.0),
        reason: '动画结束后短条对齐设置格',
      );
    });

    testWidgets('短条不拦点击：它不吃指针事件（pointer-events: none 的 Flutter 对应）', (tester) async {
      await pumpBar(tester);

      final scheduleSize = tester.getSize(find.byKey(kHomeTabBarScheduleKey));
      final settingsSize = tester.getSize(find.byKey(kHomeTabBarSettingsKey));
      expect(scheduleSize.width, closeTo(settingsSize.width, 0.5));
      expect(scheduleSize.width + settingsSize.width, closeTo(screenW, 0.5));
      // 短条不拦点击：它不吃指针事件（pointer-events: none 的 Flutter 对应）
      expect(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorKey),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      // 复查 Bug 8：指示器包 IgnorePointer，20×3dp 区域永不吞点击
      // （短条在栏底 5dp 处、位于 43dp 高的按键区下方空白带里，点它
      // 本来就不触发切换；IgnorePointer 是防御性兜底，Stack 顺序或
      // 按键区一变时也不会吞点击）
      expect(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorKey),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('短条中心正落选中格中央（复查优化 4：直接断言短条本体，不只断言容器）', (tester) async {
      await pumpBar(tester, active: HomeShellTab.schedule);
      await tester.pump(const Duration(milliseconds: 320));

      DecoratedBox pillBox() => tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorBoxKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      final pillRect = tester.getRect(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorBoxKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      final scheduleRect = tester.getRect(find.byKey(kHomeTabBarScheduleKey));
      expect(pillRect.center.dx, closeTo(scheduleRect.center.dx, 1.0),
          reason: '短条本体中心应对准课表格中心');
      expect(pillBox().decoration, isA<BoxDecoration>());
      expect((pillBox().decoration as BoxDecoration).color,
          ThemeData(brightness: Brightness.light).colorScheme.primary);

      // 切到设置格：短条本体中心跟到设置格中央
      await pumpBar(tester, active: HomeShellTab.settings);
      await tester.pump(const Duration(milliseconds: 320));
      final pillRect2 = tester.getRect(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorBoxKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      final settingsRect = tester.getRect(find.byKey(kHomeTabBarSettingsKey));
      expect(pillRect2.center.dx, closeTo(settingsRect.center.dx, 1.0),
          reason: '短条本体中心应对准设置格中心');
    });

    testWidgets('两格里没有任何包住图标/文字的色块（复查优化 4：无框的负向断言）', (tester) async {
      await pumpBar(tester);

      // 图标/文字所在的两格子树里，一个 DecoratedBox 都不许有——任何
      // tint、胶囊、色块重现都会先撞上这条断言
      for (final cell in [kHomeTabBarScheduleKey, kHomeTabBarSettingsKey]) {
        expect(
          find.descendant(
            of: find.byKey(cell),
            matching: find.byType(DecoratedBox),
          ),
          findsNothing,
          reason: '「$cell」格里不应有色块容器',
        );
      }
      // 全栏唯一的实色 DecoratedBox 就是 20×3dp 短条本体
      final colored = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(HomeTabBar),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((b) => (b.decoration as BoxDecoration?)?.color != null)
          .toList();
      expect(colored.length, 1, reason: '全栏只许短条一个实色块');
      final pill = tester.getRect(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorBoxKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(pill.width, closeTo(20, 0.5));
      expect(pill.height, closeTo(3, 0.5));
    });
  });

  group('按压回弹（Argon 方案第 4 条：按下 90ms / 松手 350ms 弹簧）', () {
    testWidgets('按下缩到 0.92，松手回到 1.0，且只影响被按的那一格', (tester) async {
      await pumpBar(tester);

      double scheduleScale() => tester
          .widget<AnimatedScale>(find.byKey(kHomeTabBarSchedulePressKey))
          .scale;
      double settingsScale() => tester
          .widget<AnimatedScale>(find.byKey(kHomeTabBarSettingsPressKey))
          .scale;

      expect(scheduleScale(), 1.0);
      expect(settingsScale(), 1.0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(kHomeTabBarScheduleKey)),
      );
      await tester.pump(); // 让 onTapDown 生效
      expect(scheduleScale(), closeTo(kLiquidPressedScale, 1e-9));
      expect(kLiquidPressedScale, 0.92);
      expect(settingsScale(), 1.0, reason: '按「课表」不该带得「设置」也缩');
      var press = tester.widget<AnimatedScale>(
        find.byKey(kHomeTabBarSchedulePressKey),
      );
      expect(press.duration, kLiquidPressDownDuration);
      expect(press.duration, const Duration(milliseconds: 90));

      await tester.pump(const Duration(milliseconds: 90));
      await gesture.up();
      await tester.pump(); // 让 onTapUp 生效
      expect(scheduleScale(), 1.0);
      press = tester.widget<AnimatedScale>(
        find.byKey(kHomeTabBarSchedulePressKey),
      );
      expect(press.duration, kLiquidPressUpDuration);
      expect(press.duration, const Duration(milliseconds: 350));
      expect(press.curve, kLiquidSpringCurve, reason: '松手回弹走弹簧曲线');
      await tester.pump(const Duration(milliseconds: 350));
      expect(scheduleScale(), 1.0);
    });

    testWidgets('手指划开取消：同样回弹到 1.0', (tester) async {
      await pumpBar(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(kHomeTabBarSettingsKey)),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byKey(kHomeTabBarSettingsPressKey)).scale,
        closeTo(0.92, 1e-9),
      );
      await gesture.moveBy(const Offset(400, 0)); // 划出这一格
      await gesture.cancel();
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byKey(kHomeTabBarSettingsPressKey)).scale,
        1.0,
        reason: 'onTapCancel 也要回弹，不能卡在 0.92',
      );
    });
  });

  group('选中态图标上浮放大与颜色过渡（三条过渡分开）', () {
    testWidgets('选中格图标放大 1.08 并上浮 1.5 像素，未选中格不动', (tester) async {
      await pumpBar(tester, active: HomeShellTab.settings);

      final selected = tester.widget<AnimatedScale>(
        find.byKey(kHomeTabBarSettingsIconKey),
      );
      final selectedLift = tester.widget<AnimatedSlide>(
        find.byKey(kHomeTabBarSettingsLiftKey),
      );
      expect(selected.scale, closeTo(kLiquidActiveIconScale, 1e-9));
      expect(kLiquidActiveIconScale, 1.08);
      expect(selectedLift.offset.dy, lessThan(0), reason: '选中图标上浮（dy 为负）');
      expect(
        selectedLift.offset.dy * kLiquidTabIconSize,
        closeTo(kLiquidActiveIconLift, 1e-9),
      );
      expect(kLiquidActiveIconLift, -1.5);

      // 未选中格：不放大、不上浮
      final unselected = tester.widget<AnimatedScale>(
        find.byKey(kHomeTabBarScheduleIconKey),
      );
      final unselectedLift = tester.widget<AnimatedSlide>(
        find.byKey(kHomeTabBarScheduleLiftKey),
      );
      expect(unselected.scale, 1.0);
      expect(unselectedLift.offset, Offset.zero);
    });

    testWidgets('选中态图标渲染位置确实更高（上浮是效果，不只是参数）', (tester) async {
      await pumpBar(tester, active: HomeShellTab.settings);
      final liftedTop = tester
          .getRect(
            find.descendant(
              of: find.byKey(kHomeTabBarSettingsKey),
              matching: find.byType(Icon),
            ),
          )
          .top;

      // 同一格改成未选中：图标应回落
      await pumpBar(tester, active: HomeShellTab.schedule);
      await tester.pump(const Duration(milliseconds: 380));
      final restTop = tester
          .getRect(
            find.descendant(
              of: find.byKey(kHomeTabBarSettingsKey),
              matching: find.byType(Icon),
            ),
          )
          .top;

      expect(restTop, greaterThan(liftedTop), reason: '选中时图标位置更高');
      expect(restTop - liftedTop, lessThan(4), reason: '只是微微上浮，不是大位移');
    });

    testWidgets('颜色过渡是 280ms 减速曲线，与位移的弹簧曲线分开', (tester) async {
      await pumpBar(tester);

      final icon = tester.widget<LiquidIcon>(
        find.descendant(
          of: find.byKey(kHomeTabBarSchedulePressKey),
          matching: find.byType(LiquidIcon),
        ),
      );
      expect(icon.duration, kLiquidColorDuration);
      expect(icon.duration, const Duration(milliseconds: 280));
      expect(icon.curve, kLiquidColorCurve);
      expect(icon.curve, Curves.easeOutCubic);
      expect(icon.curve, isNot(kLiquidSpringCurve), reason: '颜色与位移不共用曲线');

      final label = tester.widget<LiquidLabel>(
        find.descendant(
          of: find.byKey(kHomeTabBarSchedulePressKey),
          matching: find.byType(LiquidLabel),
        ),
      );
      expect(label.duration, kLiquidLabelDuration);
      expect(label.duration, const Duration(milliseconds: 180));
      expect(label.curve, Curves.easeOutCubic);
      expect(label.style.color, isNotNull);
    });
  });

  group('无框选中态不改功能', () {
    testWidgets('两格回调不变：课表格 onTapSchedule、设置格 onSelectTab', (
      tester,
    ) async {
      HomeShellTab? selected;
      var scheduleTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
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
                    onSelectTab: (t) => selected = t,
                    onTapSchedule: () => scheduleTaps++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('设置'));
      await tester.pump(const Duration(milliseconds: 380));
      expect(selected, HomeShellTab.settings);
      await tester.tap(find.text('课表'));
      await tester.pump(const Duration(milliseconds: 380));
      expect(scheduleTaps, 1);
    });

    testWidgets('底栏不引入第三个键，也没有 AI 入口', (tester) async {
      await pumpBar(tester);
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
      expect(find.text('课表'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('我的'), findsNothing);
    });
  });
}

void _noop(HomeShellTab _) {}
void _noopVoid() {}
