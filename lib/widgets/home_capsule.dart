import 'package:flutter/material.dart';

/// 壳内一级视图（WB_SPEC_213 第 2 节）：只用枚举、不用整数索引，
/// 从源头避免「三键变两键」时的下标越界（RangeError 红屏）。
enum HomeShellTab { schedule, settings }

/// 底部居中悬浮胶囊（WB_SPEC_213 第 2 节）。
///
/// 平时两键［课表｜设置］；解锁开发者选项后三键［助手｜课表｜设置］（课表居中）。
/// 三个键定性（追加第 1 条）：课表/设置是**视图切换键**（有常驻选中高亮），
/// 助手是**路由跳转键**（仅按压态、无常驻选中态；从聊天页返回后底层仍是
/// 之前所在的课表或设置高亮）。
///
/// [unlocked] 由调用方（HomeShell）watch `developerOptionsProvider` 后传入，
/// 本组件保持纯 UI、不依赖 Riverpod，方便直接构造做 widget 测试。胶囊容器用
/// [AnimatedSize] 响应解锁状态变化，无需刻意等用户从关于页返回再播动画。
class HomeCapsule extends StatelessWidget {
  const HomeCapsule({
    super.key,
    required this.activeTab,
    required this.unlocked,
    required this.onSelectTab,
    required this.onTapSchedule,
  });

  final HomeShellTab activeTab;
  final bool unlocked;
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

    final children = <Widget>[
      if (unlocked)
        _key(
          context,
          icon: Icons.smart_toy_outlined,
          label: '助手',
          selected: false,
          onTap: () => Navigator.pushNamed(context, '/ai-chat'),
        ),
      _key(
        context,
        icon: Icons.calendar_today_outlined,
        label: '课表',
        selected: activeTab == HomeShellTab.schedule,
        onTap: onTapSchedule,
      ),
      _key(
        context,
        icon: Icons.settings_outlined,
        label: '设置',
        selected: activeTab == HomeShellTab.settings,
        onTap: () => onSelectTab(HomeShellTab.settings),
      ),
    ];

    // 状态响应式展开：解锁/关锁时胶囊宽度随键数变化，AnimatedSize 平滑过渡。
    // clipBehavior 置 none，避免 AnimatedSize 默认的 hardEdge 裁掉胶囊阴影。
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      child: Material(
        color: scheme.surface,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: hPadding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 胶囊里的一个键：图标 + 小字；选中态用主题色高亮（助手键恒不选中）。
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
