import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/bottom_bar_metrics.dart';
import 'package:xiaoma_timetable/ui/liquid_glass.dart';
import 'package:xiaoma_timetable/widgets/home_capsule.dart' show HomeShellTab;
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// 标签栏液态玻璃化的渲染与动效断言（WB_SPEC_217 第 1 节）。
///
/// 按 Argon 方案逐条落地并逐条断言：
/// 1. 毛玻璃层独立（[RepaintBoundary] + [BackdropFilter]，浅色 sigma 3.5／
///    深色 sigma 4.0，2.1.7 WB_SPEC_218 第 ② 节轻透），与按键动画层分离——
///    按键不在玻璃层里；
/// 2. 底色不透明度浅色 0.58／深色 0.64、顶部细分割线（浅色 0.8dp／深色 0.6dp）、
///    贴底无阴影；
/// 3. 液态指示器：宽度 = 栏宽 50%、[AnimatedAlign] 对齐随选中项变化、
///    380ms 弹簧曲线、切换时是「滑过去」而不是重建；
/// 4. 按压回弹：按下 0.92（90ms）、松手 1.0（350ms 弹簧）；
/// 5. 选中态图标上浮放大，颜色 / 位移 / 缩放三条过渡各自分开。
///
/// 与 `bottom_bar_style_test.dart` 的分工：那边管「布局与功能不变」（整宽、
/// 贴底、两格等宽、文案、回调、留白口径），这边管「液态与动效」。
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

  group('毛玻璃层（Argon 方案第 5 条：必须与按键动画层分离）', () {
    testWidgets('玻璃层独立存在：RepaintBoundary + BackdropFilter，铺满栏体', (
      tester,
    ) async {
      await pumpBar(tester);

      expect(find.byKey(kHomeTabBarGlassKey), findsOneWidget);
      expect(tester.widget(find.byKey(kHomeTabBarGlassKey)), isA<RepaintBoundary>());
      expect(find.byKey(kHomeTabBarBlurKey), findsOneWidget);
      expect(
        tester.widget(find.byKey(kHomeTabBarBlurKey)),
        isA<BackdropFilter>(),
        reason: '玻璃层里必须有真正的 BackdropFilter',
      );
      // 铺满整个栏体（上下左右不留缝）
      final glass = tester.getRect(find.byKey(kHomeTabBarGlassKey));
      final bar = tester.getRect(find.byType(HomeTabBar));
      expect(glass.width, closeTo(bar.width, 0.5));
      expect(glass.height, closeTo(bar.height, 0.5));
    });

    testWidgets('模糊 sigma 轻透化：浅色 3.5、深色 4.0（不再 15 重模糊）', (
      tester,
    ) async {
      await pumpBar(tester);

      final blur = tester.widget<BackdropFilter>(find.byKey(kHomeTabBarBlurKey));
      // 常量口径：轻透，sigma 不超过 6（否则 12~14sp 汉字糊成色块）
      expect(kLiquidGlassBlurSigmaLight, inInclusiveRange(3, 6));
      expect(kLiquidGlassBlurSigmaLight, 3.5);
      expect(kLiquidGlassBlurSigmaDark, 4.0);
      expect(liquidGlassBlurSigma(Brightness.light), 3.5);
      expect(liquidGlassBlurSigma(Brightness.dark), 4.0);
      // 默认浅色主题：实际挂到 BackdropFilter 上的滤镜确实是 3.5（不是写死的 15）
      expect(blur.filter.toString(), contains('ImageFilter.blur(3.5, 3.5'));
      // 常量与实现同源：改了常量，滤镜跟着变
      expect(
        liquidGlassImageFilter(brightness: Brightness.light).toString(),
        blur.filter.toString(),
        reason: '滤镜必须由 liquidGlassImageFilter 按主题亮度生成',
      );
      expect(
        liquidGlassImageFilter(brightness: Brightness.light),
        isA<ImageFilter>(),
      );
    });

    testWidgets('玻璃层与按键层分离：按键不在 BackdropFilter 里面', (tester) async {
      await pumpBar(tester);

      // 两格按键都不是玻璃层的后代 → 切换时按键动画不会带着模糊一起重算
      expect(
        find.ancestor(
          of: find.byKey(kHomeTabBarScheduleKey),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(kHomeTabBarSettingsKey),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(kHomeTabBarScheduleKey),
          matching: find.byKey(kHomeTabBarGlassKey),
        ),
        findsNothing,
      );
      // 反过来：玻璃层里也没有任何按键
      expect(
        find.descendant(
          of: find.byKey(kHomeTabBarGlassKey),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
    });
  });

  group('栏体：高透染色底色 + 顶部细分割线 + 贴底无阴影', () {
    testWidgets('底色 = 高透染色玻璃：浅色白 58%（不再 72% 重底色）', (tester) async {
      await pumpBar(tester);

      final material = barMaterial(tester);
      expect(kLiquidGlassSurfaceColorLight, const Color(0x94FFFFFF));
      expect(kLiquidGlassSurfaceColorDark, const Color(0xA318181C));
      expect(material.color, liquidGlassSurfaceColor(Brightness.light));
      // 白 58%：纯白 + 半透明
      expect(material.color!.a, closeTo(0x94 / 255, 0.001));
      expect(material.color!.r, 1.0);
      expect(material.color!.g, 1.0);
      expect(material.color!.b, 1.0);
      // 高透：比 2.1.6 的 0.72 更透
      expect(material.color!.a, lessThan(0.72));
    });

    testWidgets('深色主题底色 = #18181C 64%', (tester) async {
      await pumpBar(tester, brightness: Brightness.dark);

      final material = barMaterial(tester);
      expect(material.color, liquidGlassSurfaceColor(Brightness.dark));
      expect(material.color!.a, closeTo(0xA3 / 255, 0.001));
      expect(material.color!.r, closeTo(0x18 / 255, 0.001));
      expect(material.color!.g, closeTo(0x18 / 255, 0.001));
      expect(material.color!.b, closeTo(0x1C / 255, 0.001));
    });

    testWidgets('顶部细分割线仍在，且只画顶边（浅色 0.8dp）', (tester) async {
      await pumpBar(tester);

      final box = tester.widget<DecoratedBox>(find.byKey(kHomeTabBarDividerKey));
      final decoration = box.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, kBottomBarDividerWidthLight);
      expect(bottomBarDividerWidth(Brightness.light), 0.8);
      expect(border.bottom, BorderSide.none);
      expect(border.left, BorderSide.none);
      expect(border.right, BorderSide.none);
      expect(border.top.color.a, greaterThan(0));
      expect(border.top.style, BorderStyle.solid);
    });

    testWidgets('顶部细分割线：深色 0.6dp', (tester) async {
      await pumpBar(tester, brightness: Brightness.dark);

      final box = tester.widget<DecoratedBox>(find.byKey(kHomeTabBarDividerKey));
      final decoration = box.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.width, kBottomBarDividerWidthDark);
      expect(bottomBarDividerWidth(Brightness.dark), 0.6);
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

  group('液态滑动指示器（Argon 方案第 1 条：只动位置，不切渐变）', () {
    testWidgets('宽度 = 栏宽 50%', (tester) async {
      await pumpBar(tester);

      final barWidth = tester.getSize(find.byType(HomeTabBar)).width;
      final box = tester.getSize(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(kLiquidIndicatorWidthFactor, 0.5);
      expect(box.width, closeTo(barWidth * 0.5, 0.5));
      // 滑块容器占满栏高 64，视觉滑块本体高 56（上下各留 4）
      final rect = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(rect.height, kBottomBarTabHeight);
      final slider = tester.getRect(
        find
            .descendant(
              of: find.byKey(kHomeTabBarIndicatorBoxKey),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(slider.height, kLiquidIndicatorHeight);
      expect(kLiquidIndicatorHeight, 56);
      expect(slider.width, closeTo(barWidth * 0.5, 0.5));
    });

    testWidgets('380ms 弹簧曲线，对齐随选中项变化（-1 / +1）', (tester) async {
      await pumpBar(tester, active: HomeShellTab.schedule);

      var align = tester.widget<AnimatedAlign>(find.byKey(kHomeTabBarIndicatorKey));
      expect(align.alignment, const Alignment(-1, 0), reason: '课表格：贴左半');
      expect(align.duration, kLiquidSlideDuration);
      expect(align.duration, const Duration(milliseconds: 380));
      expect(align.curve, kLiquidSpringCurve);
      // 弹簧曲线的四个控制点（Web 侧 cubic-bezier(0.34, 1.56, 0.64, 1)）
      final cubic = align.curve as Cubic;
      expect(cubic.a, closeTo(0.34, 1e-9));
      expect(cubic.b, closeTo(1.56, 1e-9));
      expect(cubic.c, closeTo(0.64, 1e-9));
      expect(cubic.d, closeTo(1.0, 1e-9));

      // 切到设置格：对齐翻到贴右半
      await pumpBar(tester, active: HomeShellTab.settings);
      align = tester.widget<AnimatedAlign>(find.byKey(kHomeTabBarIndicatorKey));
      expect(align.alignment, const Alignment(1, 0), reason: '设置格：贴右半');
      expect(align.duration, const Duration(milliseconds: 380));
      expect(align.curve, kLiquidSpringCurve);
    });

    testWidgets('切换后滑块位置与选中项一致，且是滑过去而不是瞬移', (tester) async {
      await pumpBar(tester, active: HomeShellTab.schedule);

      final scheduleRect = tester.getRect(find.byKey(kHomeTabBarScheduleKey));
      var indicator = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(
        indicator.center.dx,
        closeTo(scheduleRect.center.dx, 1.0),
        reason: '选中课表时滑块对齐课表格',
      );

      // 切到设置：先只推进 1ms——滑块应该还停在左边（说明是动画）
      await pumpBar(tester, active: HomeShellTab.settings);
      await tester.pump(const Duration(milliseconds: 1));
      indicator = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(
        indicator.center.dx,
        lessThan(tester.getSize(find.byType(HomeTabBar)).width / 2),
        reason: '切换瞬间滑块还没跳到右边，是滑过去的',
      );

      // 380ms 后到位：与设置格对齐
      await tester.pump(const Duration(milliseconds: 380));
      final settingsRect = tester.getRect(find.byKey(kHomeTabBarSettingsKey));
      indicator = tester.getRect(find.byKey(kHomeTabBarIndicatorBoxKey));
      expect(
        indicator.center.dx,
        closeTo(settingsRect.center.dx, 1.0),
        reason: '动画结束后滑块对齐设置格',
      );
    });

    testWidgets('滑块是独立层：不占按键布局，两格仍各占整宽一半', (tester) async {
      await pumpBar(tester);

      final scheduleSize = tester.getSize(find.byKey(kHomeTabBarScheduleKey));
      final settingsSize = tester.getSize(find.byKey(kHomeTabBarSettingsKey));
      expect(scheduleSize.width, closeTo(settingsSize.width, 0.5));
      expect(scheduleSize.width + settingsSize.width, closeTo(screenW, 0.5));
      // 滑块不拦点击：它不吃指针事件（pointer-events: none 的 Flutter 对应）
      expect(
        find.descendant(
          of: find.byKey(kHomeTabBarIndicatorKey),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
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
      expect(label.duration, const Duration(milliseconds: 280));
      expect(label.curve, Curves.easeOutCubic);
      expect(label.style.color, isNotNull);
    });
  });

  group('液态化不改功能', () {
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

    testWidgets('液态栏不引入第三个键，也没有 AI 入口', (tester) async {
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
