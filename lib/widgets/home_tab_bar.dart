import 'package:flutter/material.dart';

import '../ui/bottom_bar_metrics.dart';
import 'home_capsule.dart' show HomeShellTab;

/// 图标 + 文字标签栏底部栏（WB_SPEC_216 第 1 节·新默认形态，id `tab`）。
///
/// 按用户发来的自助打印小程序主页截图做，两格等宽、贴底、不悬浮、无阴影：
/// - 栏体：背景取主题表面色（[ColorScheme.surface]），顶部一条 1 逻辑像素细分割线
///   （主题 outline 低透明度），`elevation: 0`、无阴影；由 `HomeShell` 以
///   `Positioned(left: 0, right: 0, bottom: 0)` 钉在屏幕底边，栏内 `SafeArea(bottom)`
///   吃掉底部手势条安全区（色块一直铺到屏幕最底部）；
/// - 每格：图标在上、文字在下、上下居中，两格等宽平铺（各占一半宽度）；
///   左边「课表」（日历图标）、右边「设置」（齿轮图标）——文案沿用 2.1.4，
///   「设置」不改成「我的」；
/// - 颜色：选中态图标与文字**同为琥珀黄**（[activeColor]，取 Colors.amber[600]，
///   不用主题 primary 的蓝/绿）；未选中态图标与文字同为 [ColorScheme.onSurfaceVariant] 灰；
/// - 功能与 2.1.4 两键一致：点「课表」回课表视图（已在课表则回本周），
///   点「设置」进壳内设置根页；关栏时 `HomeShell` 回到 2.1.1 单页结构。
///
/// 与 [HomeCapsule] 的分工：本组件是「标签栏」形态，[HomeCapsule] 是「胶囊」形态，
/// 两者功能完全一致（同一套回调、同一套选中语义），只是外形不同，
/// 由 `UiSettings.bottomBarStyle` 二选一，见 main.dart 的 HomeShell。
///
/// 组件保持纯 UI、不依赖 Riverpod，方便直接构造做 widget 测试。
class HomeTabBar extends StatelessWidget {
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

  /// 选中态前景色（图标与文字共用）：琥珀黄 Colors.amber[600]。
  ///
  /// 不用主题 primary：截图里是琥珀黄，而本项目默认种子色是雾绿 / 可可棕。
  static const Color activeColor = kTabBarActiveColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // 贴底不悬浮：elevation 恒 0、无 shadowColor，色块一直铺到屏幕最底部。
    return Material(
      color: scheme.surface,
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
            height: height,
            child: Row(
              children: [
                _tab(
                  context,
                  key: kHomeTabBarScheduleKey,
                  icon: Icons.calendar_today_outlined,
                  label: '课表',
                  selected: activeTab == HomeShellTab.schedule,
                  onTap: onTapSchedule,
                ),
                _tab(
                  context,
                  key: kHomeTabBarSettingsKey,
                  icon: Icons.settings_outlined,
                  label: '设置',
                  selected: activeTab == HomeShellTab.settings,
                  onTap: () => onSelectTab(HomeShellTab.settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 标签栏里的一格：图标在上、文字在下，垂直居中，两格等宽（各占一半）。
  Widget _tab(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 选中/未选中只换前景色：图标与文字同色，选中琥珀黄、未选中灰
    final Color foreground = selected ? activeColor : scheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: foreground),
            const SizedBox(height: 4),
            Text(
              label,
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
    );
  }
}

/// 标签栏顶部细分割线的 Key（测试据此断言这条 1 像素线的有无与粗细）
const Key kHomeTabBarDividerKey = ValueKey('home_tab_bar_divider');

/// 标签栏里「课表」格的 Key
const Key kHomeTabBarScheduleKey = ValueKey('home_tab_bar_schedule_key');

/// 标签栏里「设置」格的 Key
const Key kHomeTabBarSettingsKey = ValueKey('home_tab_bar_settings_key');
