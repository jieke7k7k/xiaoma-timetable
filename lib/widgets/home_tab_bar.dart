import 'package:flutter/material.dart';

import '../ui/bottom_bar_metrics.dart';
import '../ui/liquid_glass.dart';

/// 壳内一级视图的两键：课表 / 设置（原在 home_capsule.dart，胶囊删除后迁入此处）。
enum HomeShellTab { schedule, settings }

/// 标签栏底部栏（WB_SPEC_216 第 1 节·新默认形态；
/// WB_SPEC_217 第 1 节·丝滑切换；2026-11-05 按 Argon Q1 方案改为无框选中态）。
///
/// 布局与功能：整宽贴底、不悬浮、无阴影、两格等宽、图标在上文字在下、
/// 文案「课表 / 设置」不变、点「课表」回课表视图（已在课表则回本周）、
/// 点「设置」进壳内设置根页。
///
/// 无框选中态（Argon 方案 Q1，用户反馈「选中框」后改）：
/// - **没有包住图标/文字的色块**：50% 宽金黄渐变滑块已删，选中只剩四重
///   轻提示——实心图标、1.08x 微放大、主题色加粗文字、底部一根 20×3dp
///   主题色小短条（[AnimatedAlign] + 320ms 减速曲线，只动位置）；
/// - **颜色 / 位移 / 缩放分开过渡**：图标颜色 280ms 减速曲线（[LiquidIcon]）、
///   文字 180ms 微过渡（[LiquidLabel]），位移与缩放 380ms 弹簧曲线，按压
///   另有自己的两段时长，绝不用「一条过渡管所有属性」的老办法；
/// - **按压分两段**：按下 90ms 缩到 0.92，松手 350ms 弹簧回弹（[AnimatedScale]）；
///   点击水波纹设透明——方形水波纹本身也会被当成「选中框」。
///
/// 2.1.7 同版本修复：**毛玻璃层已整体删除**——2.1.6 起的 [_LiquidGlass]
/// （`RepaintBoundary` + [BackdropFilter]）在真机上整屏漫溢，整片课表
/// 像蒙了雾、只有底栏本身清晰；sigma 从 15 降到 3.5 也没用，根子在滤镜
/// 层本身不在数值。栏体底色改为主题色（浅色 surface／深色 surfaceContainerLow），
/// 栏内从此没有任何模糊滤镜，课表永不蒙雾。
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
  /// （图标 23 + 间距 4 + 文字行 + 上下内边距各 8，由最小高托到 64）。
  /// 网格底部留白按它算（见 [bottomBarGridBottomInset]）。
  static const double height = kBottomBarTabHeight;

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
    // 底色跟主题走（浅色 surface／深色 surfaceContainerLow），栏内没有任何
    // 模糊滤镜（2.1.7 同版本修复：毛玻璃层整屏漫溢已删，见本文件头注释）。
    return Material(
      color: scheme.brightness == Brightness.dark
          ? scheme.surfaceContainerLow
          : scheme.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          key: kHomeTabBarDividerKey,
          // 顶部一条细分割线：用 DecoratedBox 画在栏体内部
          // （装饰不参与布局，不额外占高，栏体实测高度仍是 64），
          // 0.5dp，主题 outlineVariant（浅色 0.45／深色 0.25），
          // 跟主题走，不再按亮度手写颜色（Argon 方案 Q2）。
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                width: 0.5,
                color: scheme.outlineVariant.withValues(
                  alpha: scheme.brightness == Brightness.dark ? 0.25 : 0.45,
                ),
              ),
            ),
          ),
          child: SizedBox(
            // 栏高固定为实测值 64（图标 24 + 间距 4 + 文字行，上下自动留白）；
            // 不用 minHeight 兜底是为了让「实测高度 == 留白口径」这条断言成立，
            // 字体放大时由 _tab 内部的 Column 居中，不会纵向溢出。
            height: HomeTabBar.height,
            child: Stack(
              // 两层从下到上：选中小短条 → 两格按键（玻璃层与金黄滑块已删，
              // 见本文件头注释）
              fit: StackFit.expand,
              children: [
                // ① 选中指示小短条：20×3dp，随选中项在左右两格之间滑动
                _selectionPill(),
                // ② 两格按键：仍 Expanded 等宽平铺，宽度与 2.1.5 一致
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
                      selectedIcon: Icons.calendar_today,
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
                      selectedIcon: Icons.settings,
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

  /// 选中指示小短条（Argon 方案 Q1：无框选中态的唯一指示器）。
  ///
  /// 一根 20×3dp 的主题色小短条，贴在栏底上方 5dp，随选中项在左右两格
  /// 之间滑动（[AnimatedAlign] 的 alignment 从 -1 到 +1，320ms 减速曲线）。
  /// 短条放在 50% 宽的容器里水平居中，容器本身不贴边——视觉上短条始终
  /// 悬在选中那格的正下方中央。
  ///
  /// 旧的 50% 宽金黄渐变滑块已删：用户反馈它就是「选中框」，任何包住
  /// 图标/文字的色块（含淡 tint、M3 小胶囊）都必须排除。
  Widget _selectionPill() {
    final isSchedule = widget.activeTab == HomeShellTab.schedule;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedAlign(
      key: kHomeTabBarIndicatorKey,
      // -1 = 贴左（课表格），+1 = 贴右（设置格）；y=1 贴栏底
      alignment: Alignment(isSchedule ? -1 : 1, 1),
      duration: kSelectionPillDuration,
      curve: kSelectionPillCurve,
      child: FractionallySizedBox(
        key: kHomeTabBarIndicatorBoxKey,
        widthFactor: kLiquidIndicatorWidthFactor,
        child: Align(
          // 水平居中、底部对齐：短条悬在选中那格正下方中央、距栏底 5dp
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: kSelectionPillBottomGap),
            child: SizedBox(
              width: kSelectionPillWidth,
              height: kSelectionPillHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(
                    kSelectionPillHeight / 2,
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
  /// - 前景色：[LiquidIcon] 280ms 减速曲线 / [LiquidLabel] 180ms 微过渡；
  /// - 选中态图标实心、未选中线框（双态图标，Argon 方案 Q1）。
  Widget _tab(
    BuildContext context, {
    required HomeShellTab tab,
    required Key key,
    required Key pressKey,
    required Key liftKey,
    required Key iconKey,
    required Key labelKey,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 选中/未选中只换前景色：图标与文字同色，选中取主题 primary、未选灰
    // （浅色 0.60／深色 0.55），跟主题走，不再固定金黄（Argon 方案 Q2）。
    final Color foreground = selected
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.55 : 0.60,
          );
    final pressed = _pressedTab == tab;

    return Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        // 点击水波纹设透明：方形水波纹本身也会被当成「选中框」（Argon 方案 Q1）；
        // 按压反馈仍由外层 AnimatedScale（0.92）承担。
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
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
                // -1.5px ÷ 23px 图标 = -0.0652
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
                    // 选中实心、未选中线框（Argon 方案 Q1：双态图标）
                    icon: selected ? selectedIcon : icon,
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
                  fontSize: 11.5,
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

/// 标签栏顶部细分割线的 Key（测试据此断言这条线有无与粗细）
const Key kHomeTabBarDividerKey = ValueKey('home_tab_bar_divider');

/// 选中指示小短条的 Key（[AnimatedAlign]：测试据此断言对齐、时长、曲线）
const Key kHomeTabBarIndicatorKey = ValueKey('home_tab_bar_indicator');

/// 选中指示器容器的 Key（[FractionallySizedBox]：测试据此断言宽度为栏宽 50%）
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
