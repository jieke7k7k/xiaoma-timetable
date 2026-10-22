import 'package:flutter/material.dart';

import '../ui/app_styles.dart';

/// 全 App 统一弹窗（WB-202 第 4 项，长期规范）
///
/// 标题、正文、按钮区的圆角 / 内边距 / 排版走同一套规范，与现有主题色一致：
/// - 形状：圆角固定取 [AppRadii.dialog]（20px），不再各处默认 28；
/// - 标题：16 号 w600；正文：正文档字号，左对齐；
/// - 按钮区：右对齐，「取消/次要」用 TextButton、「确认/主动」用 FilledButton，
///   破坏性确认（删除、覆盖恢复等）用 error 色标红。
///
/// 用法：
/// - 纯信息展示（ⓘ 说明、公告等）用 [showAppInfoDialog]；
/// - 二次确认用 [showAppConfirmDialog]（返回 true = 确认）；
/// - 需要自定义内容（输入框、列表、进度遮罩等）时直接嵌 [AppDialog]，
///   形状与排版仍然统一，按钮区自行给 [AppDialog.actions]。
///
/// **新弹窗必须用它**；设置区与主页的高频确认弹窗已在 2.0.2 第二批切完，
/// 其余页面后续迁移也必须用它（规范已写进 DEV_STATE.md）。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  /// 弹窗标题（必填，保持各页面标题层级一致）
  final String title;

  /// 弹窗正文（任意组件；纯文本优先传 [AppDialogText] 保持排版一致）
  final Widget content;

  /// 按钮区（右对齐；不需要按钮时可传空列表）
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.l,
        AppSpacing.l,
        0,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.m,
        AppSpacing.l,
        0,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.s,
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      content: DefaultTextStyle(
        style: theme.textTheme.bodyMedium ?? const TextStyle(),
        child: content,
      ),
      actions: actions,
    );
  }
}

/// [AppDialog] 的正文文本（统一排版：正文档、默认字色）
class AppDialogText extends StatelessWidget {
  const AppDialogText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text);
  }
}

/// 统一信息弹窗（ⓘ 说明、公告等只告知不决策的场景）
///
/// 返回用户点的那个按钮的值（默认只有「知道了」，点哪都是 null）。
Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = '知道了',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AppDialog(
      title: title,
      content: AppDialogText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

/// 统一确认弹窗（删除、覆盖恢复、重置等需要用户点头的场景）
///
/// 返回 true = 确认；false / null（点遮罩 dismiss）= 取消。
/// [destructive] 为 true 时确认按钮用 error 色标红，与旧 AlertDialog 里
/// 手写 `backgroundColor: scheme.error` 的破坏性确认视觉一致。
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AppDialog(
        title: title,
        content: AppDialogText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

/// 条目标题旁的小 ⓘ 信息图标按钮（WB-202 第 4 项）
///
/// 长说明不再以卡片平铺：条目标题旁放这个小图标，点击弹 [showAppInfoDialog]
/// 显示全文。图标走 outline 色、18 号，不抢条目的视觉重心。
class AppInfoIconButton extends StatelessWidget {
  const AppInfoIconButton({super.key, required this.onPressed, this.tooltip});

  final VoidCallback onPressed;

  /// 长按提示（一般填弹窗标题，用户不用点也知道里面是什么）
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: const Icon(Icons.info_outline),
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.outline,
    );
  }
}
