import 'package:flutter/material.dart';

import 'app_styles.dart';

/// 全 App 统一的单选 Chip（WB_SPEC_230 第 6.1 节）。
///
/// 不用系统 `ChoiceChip`：原生 M3 ChoiceChip 选中时左侧会动态插入打勾图标，
/// 宽度随选中态伸缩跳动；高度受 `MaterialTapTargetSize` 影响，易留上下隐形
/// 死区；圆角默认 8dp。这里统一手搓——高 36、圆角 [AppRadii.chip]、选中态
/// 主色 12% 底 + 1.5dp 主色描边 + w600 主色 12sp 字，未选中态
/// surfaceContainerHighest 30% 底 + 1.0dp outlineVariant 描边 + 12sp 常规字。
///
/// 长文案用 [FittedBox] 缩到单行，保证同一行芯片等高且文案完整可见。
/// 视觉参数由导入核对页原 `_scheduleChoiceChip` 原样提炼，两处调用点
/// （导入核对页二选一、设置页切换动效三选一）长相完全一致。
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.expanded = false,
  });

  /// 芯片文案（沿用原选项文案，不改字）。
  final String label;

  /// 是否选中。
  final bool selected;

  /// 点按回调（选中态由调用方维护，本组件不持状态）。
  final VoidCallback onSelected;

  /// 为 true 时外包一层 [Expanded] 占满可用宽（导入核对页并排两枚用法）；
  /// false 时按内容宽（设置页 Wrap 里的三枚用法）。
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chip = InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? cs.primary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
    return expanded ? Expanded(child: chip) : chip;
  }
}
