import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/menu_config.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';

/// 菜单管理子页（WB_SPEC_212 第 4 节）：路由 `/menu-manage`。
///
/// 每行 = 左侧拖拽手柄 + 中间功能图标与名称 + 右侧显隐开关；用
/// ReorderableListView 拖拽排序（自带动效，不加花哨动画），底部「恢复默认」
/// 一键回到「全部显示 + 定版顺序」。
///
/// 「设置」不在这里：它固定显示、不可关闭、不可排序移出（见 MenuConfig）。
class MenuManagePage extends ConsumerWidget {
  const MenuManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(menuConfigProvider);
    // provider 未加载完（首帧）先按默认渲染，读库完成后自动到位
    final config = configAsync.value ?? MenuConfig.defaults();

    return Scaffold(
      appBar: AppBar(title: const Text('菜单管理'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              // 关掉框架默认手柄：我们要左侧固定手柄（见 _MenuRow 的 leading）
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              itemCount: config.items.length,
              // Flutter 3.41+ 用 onReorderItem（newIndex 已代做 -1 调整）
              onReorderItem: (oldIndex, newIndex) => ref
                  .read(menuConfigProvider.notifier)
                  .reorder(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final cfg = config.items[index];
                final spec = menuItemSpecById(cfg.id);
                return _MenuRow(
                  key: ValueKey(cfg.id),
                  index: index,
                  icon: spec?.icon ?? Icons.help_outline,
                  title: spec?.title ?? '',
                  visible: cfg.visible,
                  onVisibleChanged: (v) => ref
                      .read(menuConfigProvider.notifier)
                      .setVisible(cfg.id, v),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复默认'),
                  onPressed: () =>
                      ref.read(menuConfigProvider.notifier).reset(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 菜单管理页的一行：左侧拖拽手柄 + 中间图标/名称 + 右侧显隐开关。
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    super.key,
    required this.index,
    required this.icon,
    required this.title,
    required this.visible,
    required this.onVisibleChanged,
  });

  /// 当前显示序号，供拖拽手柄回传 ReorderableListView。
  final int index;
  final IconData icon;
  final String title;
  final bool visible;
  final ValueChanged<bool> onVisibleChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      // 左侧固定拖拽手柄：按住即拖（ReorderableListView 自带动效）
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(Icons.drag_handle, color: scheme.outline),
      ),
      // 中间：功能图标 + 名称
      title: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.m),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
      // 右侧：显隐开关（Switch 自带反馈，不加额外动画）
      trailing: Switch(value: visible, onChanged: onVisibleChanged),
    );
  }
}
