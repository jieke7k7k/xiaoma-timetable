import 'package:flutter/material.dart';

import '../ui/bottom_bar_metrics.dart';
import 'home_capsule.dart' show HomeShellTab;

/// 通栏贴底底部栏（WB_SPEC_215 第 2 节·形态 A）。
///
/// 与 2.1.3 那个「底部居中悬浮胶囊」的区别，正是用户原话要的：
/// 「把以前底部显示去掉 AI 的底部栏加回来，按钮做成胶囊，圆角，但是不要悬浮」。
/// - 栏体：撑满整宽、贴住屏幕底边，背景取主题表面色，**不做圆角、不加阴影**，
///   底部安全区（手势条）由栏体内部的 SafeArea 吃掉，色块一直铺到屏幕最底部；
/// - 键体：「课表｜设置」两键各自做成胶囊圆角按钮（圆角 26、最小高 52），
///   选中态用主题色实心填充 + onPrimary 前景，未选中态透明填充 + onSurfaceVariant
///   文字，靠填充与文字颜色区分，两个键等宽平铺（各占一半宽度）。
///
/// 与 [HomeCapsule] 的分工：本组件是「通栏」形态，[HomeCapsule] 是「胶囊」形态，
/// 两者功能完全一致（同一套回调、同一套选中语义），只是外形与贴底方式不同，
/// 由 `UiSettings.bottomBarStyle` 二选一，见 main.dart 的 HomeShell。
///
/// 组件保持纯 UI、不依赖 Riverpod，方便直接构造做 widget 测试。
class HomeBottomBar extends StatelessWidget {
  const HomeBottomBar({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
    required this.onTapSchedule,
  });

  final HomeShellTab activeTab;
  final ValueChanged<HomeShellTab> onSelectTab;
  final VoidCallback onTapSchedule;

  /// 栏体高度（**不含**底部安全区）：52 键高 + 上下各 8 内边距 = 68。
  /// 网格底部留白按它算（见 [bottomBarGridBottomInset]）。
  static const double height = kBottomBarBarHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // elevation 恒 0、形状为直角矩形：通栏贴底不悬浮，自然没有悬浮阴影。
    return Material(
      color: scheme.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kBottomBarHorizontalPadding,
            vertical: kBottomBarVerticalPadding,
          ),
          child: Row(
            children: [
              _barKey(
                context,
                key: kBottomBarScheduleKey,
                icon: Icons.calendar_today_outlined,
                label: '课表',
                selected: activeTab == HomeShellTab.schedule,
                onTap: onTapSchedule,
              ),
              const SizedBox(width: kBottomBarKeyGap),
              _barKey(
                context,
                key: kBottomBarSettingsKey,
                icon: Icons.settings_outlined,
                label: '设置',
                selected: activeTab == HomeShellTab.settings,
                onTap: () => onSelectTab(HomeShellTab.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 通栏栏里的一个键：胶囊圆角键体（圆角 26、最小高 52），两键等宽平铺。
  Widget _barKey(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 选中/未选中的区分只看填充与文字颜色：选中实心主题色，未选中透明底
    final Color fill = selected ? scheme.primary : Colors.transparent;
    final Color foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kBottomBarRadius),
    );

    return Expanded(
      child: ConstrainedBox(
        // 最小高而不是写死高：系统字体放大时键体可纵向伸展，不溢出
        constraints: const BoxConstraints(minHeight: kBottomBarKeyHeight),
        child: Material(
          key: key,
          color: fill,
          elevation: 0,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 通栏栏里「课表」键的 Key（测试据此取键体，断言圆角与最小高）
const Key kBottomBarScheduleKey = ValueKey('bottom_bar_schedule_key');

/// 通栏栏里「设置」键的 Key
const Key kBottomBarSettingsKey = ValueKey('bottom_bar_settings_key');
