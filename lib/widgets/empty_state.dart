import 'package:flutter/material.dart';

import '../ui/app_styles.dart';

/// 统一空状态占位组件（阶段五·视觉打磨）
///
/// 所有列表 / 网格没有数据时都必须用它给出中文占位提示：
/// 图标 + 一句话主文案 +（可选）补充说明 +（可选）操作按钮，不允许白屏。
///
/// 深浅色全部走 colorScheme 语义色，深色模式自动适配。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.iconImage,
  });

  /// 占位图标（推荐使用 *_outlined 线性图标，视觉更轻）
  final IconData icon;

  /// 可选的图片图标（如像素小马 PNG）；非空时优先于 [icon] 渲染
  final ImageProvider? iconImage;

  /// 一句话主文案，如「还没有设置考试日期」
  final String title;

  /// 可选的补充说明（告诉用户怎么解决）
  final String? message;

  /// 可选操作按钮文案（如「新建学期」「重试」）
  final String? actionLabel;

  /// 操作按钮回调
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标垫一个浅色圆底，比裸图标更有「占位插画」感
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: iconImage != null
                  ? Image(image: iconImage!, width: 40, height: 40)
                  : Icon(icon, size: 40, color: colorScheme.outline),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.l),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
