import 'package:flutter/material.dart';

import '../ui/bottom_bar_metrics.dart';
import '../ui/liquid_glass.dart';
import 'home_capsule.dart' show HomeShellTab;

/// 液态玻璃标签栏底部栏（WB_SPEC_216 第 1 节·新默认形态，id `tab`；
/// WB_SPEC_217 第 1 节·液态玻璃化）。
///
/// 2.1.6 只改**渲染与动效**，布局与功能一律不变：整宽贴底、不悬浮、无阴影、
/// 两格等宽、图标在上文字在下、文案「课表 / 设置」不变、点「课表」回课表视图
/// （已在课表则回本周）、点「设置」进壳内设置根页。
///
/// 液态化的四件事（按 Argon 方案，与样品 `.phone-bar` 对齐）：
/// - **毛玻璃层独立**：[Stack] 里单独一层 [_LiquidGlass]（`RepaintBoundary`
///   + [BackdropFilter]，模糊 sigma 15），与按键动画层彻底分离——切换时
///   玻璃层零重算，按键动画不会带着整条栏一起重绘；
/// - **选中态由滑动指示器承载**：一块 50% 宽的金黄渐变滑块（[AnimatedAlign]
///   + 380ms 弹簧曲线）只动位置，不再「选中时把整格背景切成渐变」——渐变插值
///   在 Flutter 里天生生硬，改走位移后纯 GPU；
/// - **颜色 / 位移 / 缩放分开过渡**：颜色 280ms 减速曲线（[LiquidIcon] /
///   [LiquidLabel]），位移与缩放 380ms 弹簧曲线，按压另有自己的两段时长，
///   绝不用「一条过渡管所有属性」的老办法；
/// - **按压分两段**：按下 90ms 缩到 0.92，松手 350ms 弹簧回弹（[AnimatedScale]）。
///
/// 与 [HomeCapsule] 的分工不变：本组件是「标签栏」形态，[HomeCapsule] 是
/// 「胶囊」形态，两者功能完全一致（同一套回调、同一套选中语义），只是外形
/// 不同，由 `UiSettings.bottomBarStyle` 二选一，见 main.dart 的 HomeShell。
///
/// 组件保持纯 UI、不依赖 Riverpod，方便直接构造做 widget 测试
/// （2.1.6 起因按压态需要 State，改为 [StatefulWidget]，对外构造签名不变）。
class HomeTabBar extends StatefulWidget {
  const HomeTabBar({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
    required this.onTapSchedule,
  });

  final HomeShellTab activeTab;
  final ValueChanged<HomeShellTab> onSelectTab;
  final VoidCallback onTapSchedule;

  /// 栏体高度（**不含**底部安全区）：该 widget 的实测高度 64
  /// （图标 24 + 间距 4 + 文字行 + 上下内边距各 8，由最小高托到 64）。
  /// 网格底部留白按它算（见 [bottomBarGridBottomInset]）。
  static const double height = kBottomBarTabHeight;

  /// 选中态基色（金黄系）：琥珀黄 `Colors.amber[600]`。
  ///
  /// 不用主题 primary：截图里是琥珀黄，而本项目默认种子色是雾绿 / 可可棕。
  /// 2.1.6 起它用于**液态滑块的金黄渐变**；图标与文字的前景色见
  /// [activeColorFor]（浅色主题压暗、深色主题提亮，保证压在滑块上看得清）。
  static const Color activeColor = kTabBarActiveColor;

  /// 选中态前景色（图标与文字共用）：按主题亮度二选一——
  /// 浅色主题 [kTabBarActiveColorLight]（深金黄，压在金黄滑块上仍有
  /// ≥ 4.5:1 对比度）、深色主题 [kTabBarActiveColorDark]（浅金黄）。
  ///
  /// 2.1.5 是深浅色都用 [kTabBarActiveColor]（亮黄 #FFB300）；2.1.6 因为选中格
  /// 底下多了一块金黄实心滑块，亮黄压亮黄会糊成一片，故按亮度分开取值。
  static Color activeColorFor(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? kTabBarActiveColorDark
          : kTabBarActiveColorLight;

  @override
  State<HomeTabBar> createState() => _HomeTabBarState();
}

class _HomeTabBarState extends State<HomeTabBar> {
  /// 当前被按下的那一格（没有则为 null）：按压反馈要按格独立，
  /// 否则按「课表」时「设置」也会跟着缩。
  HomeShellTab? _pressedTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 贴底不悬浮：elevation 恒 0、无 shadowColor，色块一直铺到屏幕最底部。
    // 底色改半透明（主题 surface 的 72%），模糊由下面独立的玻璃层提供。
    return Material(
      color: scheme.surface.withValues(alpha: kLiquidGlassSurfaceOpacity),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          key: kHomeTabBarDividerKey,
          // 顶部一条 1 逻辑像素细分割线：用 DecoratedBox 画在栏体内部
          // （装饰不参与布局，不额外占高，栏体实测高度仍是 64），
          // 颜色取主题 outline 的低透明度版本，深浅色都能看见又不抢眼。
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                width: kBottomBarDividerWidth,
                color: scheme.outline.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: SizedBox(
            // 栏高固定为实测值 64（图标 24 + 间距 4 + 文字行，上下自动留白）；
            // 不用 minHeight 兜底是为了让「实测高度 == 留白口径」这条断言成立，
            // 字体放大时由 _tab 内部的 Column 居中，不会纵向溢出。
            height: HomeTabBar.height,
            child: Stack(
              // 三层从下到上：玻璃层（独立层）→ 液态滑块 → 两格按键
              fit: StackFit.expand,
              children: [
                // ① 毛玻璃层：独立一层，只做模糊，不参与任何按键动画
                const Positioned.fill(child: _LiquidGlass()),
                // ② 液态滑动指示器：50% 宽，随选中项在左右两格之间滑动
                _liquidIndicator(),
                // ③ 两格按键：仍 Expanded 等宽平铺，宽度与 2.1.5 一致
                Row(
                  children: [
                    _tab(
                      context,
                      tab: HomeShellTab.schedule,
                      key: kHomeTabBarScheduleKey,
                      pressKey: kHomeTabBarSchedulePressKey,
                      liftKey: kHomeTabBarScheduleLiftKey,
                      iconKey: kHomeTabBarScheduleIconKey,
                      labelKey: kHomeTabBarScheduleLabelKey,
                      icon: Icons.calendar_today_outlined,
                      label: '课表',
                      selected: widget.activeTab == HomeShellTab.schedule,
                      onTap: widget.onTapSchedule,
                    ),
                    _tab(
                      context,
                      tab: HomeShellTab.settings,
                      key: kHomeTabBarSettingsKey,
                      pressKey: kHomeTabBarSettingsPressKey,
                      liftKey: kHomeTabBarSettingsLiftKey,
                      iconKey: kHomeTabBarSettingsIconKey,
                      labelKey: kHomeTabBarSettingsLabelKey,
                      icon: Icons.settings_outlined,
                      label: '设置',
                      selected: widget.activeTab == HomeShellTab.settings,
                      onTap: () => widget.onSelectTab(HomeShellTab.settings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 液态滑动指示器（Argon 方案第 1 条）。
  ///
  /// 一块 50% 栏宽的滑块承载金黄渐变，切换时**只动位置**（[AnimatedAlign] 的
  /// alignment 从 -1 到 +1），380ms 弹簧曲线。选中态背景因此不需要渐变插值，
  /// 也就不会出现「黄→灰之间过渡出脏色」的生硬感。
  ///
  /// 滑块是 [Stack] 里的独立层，不占按键的布局位置，所以两格仍是各自 50% 宽，
  /// 「两格等分整宽」的几何断言不受影响。
  Widget _liquidIndicator() {
    final isSchedule = widget.activeTab == HomeShellTab.schedule;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedAlign(
      key: kHomeTabBarIndicatorKey,
      // -1 = 贴左（课表格），+1 = 贴右（设置格）
      alignment: Alignment(isSchedule ? -1 : 1, 0),
      duration: kLiquidSlideDuration,
      curve: kLiquidSpringCurve,
      child: FractionallySizedBox(
        key: kHomeTabBarIndicatorBoxKey,
        widthFactor: kLiquidIndicatorWidthFactor,
        child: Padding(
          // 上下各留 4（栏 64、滑块 56），左右不留——与现有栏内边距一致
          padding: const EdgeInsets.symmetric(
            vertical: (kBottomBarTabHeight - kLiquidIndicatorHeight) / 2,
          ),
          child: SizedBox(
            height: kLiquidIndicatorHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kBottomBarRadius),
                // 金黄渐变（与 2.1.5 的琥珀黄同色）：左上→右下的 135° 斜向。
                // 深色主题用压暗的同一组金黄，好让浅金黄的前景看得清。
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? kLiquidSliderGradientDark
                      : kLiquidSliderGradientLight,
                  stops: const <double>[0, 0.55, 1],
                ),
                border: Border.all(
                  color: const Color(0xB3FFFFFF), // rgba(255,255,255,.7)
                  width: 1,
                ),
              ),
              // 顶部一抹高光：液态感的关键（样品 .liquid::before 的斜向光泽），
              // 用叠加的渐变表达，不加投影——栏体口径是「不悬浮、无阴影」。
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kBottomBarRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? kLiquidSliderGlossDark
                        : kLiquidSliderGlossLight,
                    stops: const <double>[0, 0.4],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 标签栏里的一格：图标在上、文字在下，垂直居中，两格等宽（各占一半）。
  ///
  /// 三层动画各管各的（Argon 方案第 2 / 3 条）：
  /// - 按压：[AnimatedScale]，按下 90ms→0.92、松手 350ms 弹簧→1.0；
  /// - 图标上浮放大：[AnimatedSlide] + [AnimatedScale]，380ms 弹簧曲线；
  /// - 前景色：[LiquidIcon] / [LiquidLabel]，280ms 减速曲线。
  Widget _tab(
    BuildContext context, {
    required HomeShellTab tab,
    required Key key,
    required Key pressKey,
    required Key liftKey,
    required Key iconKey,
    required Key labelKey,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 选中/未选中只换前景色：图标与文字同色，选金黄系、未选灰
    final Color foreground = selected
        ? HomeTabBar.activeColorFor(scheme)
        : scheme.onSurfaceVariant;
    final pressed = _pressedTab == tab;

    return Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        // 按压两段：按下立刻缩、松手（或手指划开取消）弹簧回弹
        onTapDown: (_) => _setPressed(tab),
        onTapUp: (_) => _setPressed(null),
        onTapCancel: () => _setPressed(null),
        child: AnimatedScale(
          key: pressKey,
          scale: pressed ? kLiquidPressedScale : 1.0,
          duration: pressed
              ? kLiquidPressDownDuration
              : kLiquidPressUpDuration,
          curve: pressed ? Curves.easeOut : kLiquidSpringCurve,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSlide(
                key: liftKey,
                // AnimatedSlide 的 offset 以 child 尺寸为单位：
                // -1.5px ÷ 24px 图标 = -0.0625
                offset: selected
                    ? const Offset(
                        0,
                        kLiquidActiveIconLift / kLiquidTabIconSize,
                      )
                    : Offset.zero,
                duration: kLiquidSlideDuration,
                curve: kLiquidSpringCurve,
                child: AnimatedScale(
                  key: iconKey,
                  scale: selected ? kLiquidActiveIconScale : 1.0,
                  duration: kLiquidSlideDuration,
                  curve: kLiquidSpringCurve,
                  child: LiquidIcon(
                    icon: icon,
                    size: kLiquidTabIconSize,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              LiquidLabel(
                key: labelKey,
                text: label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setPressed(HomeShellTab? tab) {
    if (_pressedTab == tab) return;
    if (!mounted) return;
    setState(() => _pressedTab = tab);
  }
}

/// 独立的毛玻璃层（Argon 方案第 5 条）：[RepaintBoundary] + [BackdropFilter]，
/// 只做模糊、没有子节点参与布局，既不与按键动画互相牵连，也不会因为按键重绘
/// 而反复重算模糊（低端机上这一步最贵）。
///
/// 它不挂在栏本体上——栏本体 [Material] 只负责 72% 不透明度的底色，
/// 玻璃层是 [Stack] 里平级的独立一层。
class _LiquidGlass extends StatelessWidget {
  const _LiquidGlass();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: kHomeTabBarGlassKey,
      child: BackdropFilter(
        key: kHomeTabBarBlurKey,
        filter: liquidGlassImageFilter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 标签栏顶部细分割线的 Key（测试据此断言这条 1 像素线的有无与粗细）
const Key kHomeTabBarDividerKey = ValueKey('home_tab_bar_divider');

/// 独立毛玻璃层的 Key（测试据此断言玻璃层与按键层分离）
const Key kHomeTabBarGlassKey = ValueKey('home_tab_bar_glass');

/// 毛玻璃 BackdropFilter 自身的 Key（测试据此断言模糊 sigma）
const Key kHomeTabBarBlurKey = ValueKey('home_tab_bar_blur');

/// 液态滑动指示器的 Key（[AnimatedAlign]：测试据此断言对齐、时长、曲线）
const Key kHomeTabBarIndicatorKey = ValueKey('home_tab_bar_indicator');

/// 液态滑块本体的 Key（[FractionallySizedBox]：测试据此断言宽度为栏宽 50%）
const Key kHomeTabBarIndicatorBoxKey = ValueKey('home_tab_bar_indicator_box');

/// 标签栏里「课表」格的 Key
const Key kHomeTabBarScheduleKey = ValueKey('home_tab_bar_schedule_key');

/// 标签栏里「设置」格的 Key
const Key kHomeTabBarSettingsKey = ValueKey('home_tab_bar_settings_key');

/// 「课表」格按压缩放层的 Key（[AnimatedScale]）
const Key kHomeTabBarSchedulePressKey = ValueKey(
  'home_tab_bar_schedule_press',
);

/// 「设置」格按压缩放层的 Key（[AnimatedScale]）
const Key kHomeTabBarSettingsPressKey = ValueKey(
  'home_tab_bar_settings_press',
);

/// 「课表」格图标上浮层的 Key（[AnimatedSlide]）
const Key kHomeTabBarScheduleLiftKey = ValueKey('home_tab_bar_schedule_lift');

/// 「设置」格图标上浮层的 Key（[AnimatedSlide]）
const Key kHomeTabBarSettingsLiftKey = ValueKey('home_tab_bar_settings_lift');

/// 「课表」格图标放大层的 Key（[AnimatedScale]）
const Key kHomeTabBarScheduleIconKey = ValueKey('home_tab_bar_schedule_icon');

/// 「设置」格图标放大层的 Key（[AnimatedScale]）
const Key kHomeTabBarSettingsIconKey = ValueKey('home_tab_bar_settings_icon');

/// 「课表」格文字的 Key（[LiquidLabel]）
const Key kHomeTabBarScheduleLabelKey = ValueKey('home_tab_bar_schedule_label');

/// 「设置」格文字的 Key（[LiquidLabel]）
const Key kHomeTabBarSettingsLabelKey = ValueKey('home_tab_bar_settings_label');
