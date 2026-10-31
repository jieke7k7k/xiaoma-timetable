import 'package:flutter/material.dart';

/// 壳内一级视图（WB_SPEC_213 第 2 节）：只用枚举、不用整数索引，
/// 从源头避免「键数变化」时的下标越界（RangeError 红屏）。
enum HomeShellTab { schedule, settings }

/// 底部居中悬浮胶囊（WB_SPEC_213 第 2 节）。
///
/// 2.1.3（WB_SPEC_214 第 1 节）起恒为两键［课表｜设置］：此前「解锁后展开第三个
/// 路由键」的形态随该功能整体删除，本组件不再有 unlock 参数、不再有第三个键，
/// 也不再有展开/收起的尺寸动画——键数固定，宽度自然固定。
///
/// 两个键都是**视图切换键**（有常驻选中高亮），点击只改 [activeTab] 或回到本周，
/// 不 Push 任何路由。本组件保持纯 UI、不依赖 Riverpod，方便直接构造做 widget 测试。
class HomeCapsule extends StatelessWidget {
  const HomeCapsule({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
    required this.onTapSchedule,
  });

  final HomeShellTab activeTab;
  final ValueChanged<HomeShellTab> onSelectTab;
  final VoidCallback onTapSchedule;

  // 胶囊几何（第 2 节定版）：最小高 52、圆角 26（半圆胶囊）、水平内边距 20、
  // 键间距 16，宽度由内容自适应撑开，不死写固定宽度。高度用最小值而不用
  // 写死值：系统字体放大时胶囊可纵向伸展，避免 RenderFlex 纵向溢出（复审 P0-1）。
  static const double height = 52;
  static const double radius = 26;
  static const double hPadding = 20;
  static const double gap = 16;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: hPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _key(
                context,
                icon: Icons.calendar_today_outlined,
                label: '课表',
                selected: activeTab == HomeShellTab.schedule,
                onTap: onTapSchedule,
              ),
              const SizedBox(width: gap),
              _key(
                context,
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

  /// 胶囊里的一个键：图标 + 小字；选中态用主题色高亮。
  Widget _key(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
