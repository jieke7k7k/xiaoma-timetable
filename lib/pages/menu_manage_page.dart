import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/menu_config.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/app_haptics.dart';

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
                  // WB_SPEC_235 跟进 §1-16：「恢复默认」= 轻点档
                  style: OutlinedButton.styleFrom(enableFeedback: false),
                  onPressed: () {
                    AppHaptics.tap();
                    ref.read(menuConfigProvider.notifier).reset();
                  },
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
      // 右侧：显隐开关。WB_SPEC_235 跟进 §3：震动一律以 AppHaptics 为准——
      // 不再依赖 Switch 自带的系统反馈（下面 `enableFeedback: false` 已关掉），
      // 也不再额外加动画
      trailing: Switch(
        value: visible,
        onChanged: (v) {
          AppHaptics.select();
          onVisibleChanged(v);
        },
      ),
      // WB_SPEC_230 第 7 节 c：优先方案是换 SwitchListTile，但它的 secondary
      // 只能放在开关对面（LTR 下即右侧），而本行拖拽手柄必须钉在左侧——
      // 塞进 title 又会和整行点击抢手势（手柄拖拽与 onTap 触摸区打架）。
      // 故走规格给的退路：保留 ListTile + trailing Switch，补 onTap 让
      // 点整行文字与点开关行为一致。
      // §3：整行点按与点开关走同一档（select），两条路径各震一次、不叠加
      enableFeedback: false,
      onTap: () {
        AppHaptics.select();
        onVisibleChanged(!visible);
      },
    );
  }
}
