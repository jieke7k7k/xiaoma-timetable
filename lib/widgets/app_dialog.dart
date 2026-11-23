import 'package:flutter/material.dart';

import '../ui/app_styles.dart';
import '../utils/app_haptics.dart';

/// 全 App 统一弹窗（WB-202 第 4 项，长期规范）
///
/// 标题、正文、按钮区的圆角 / 内边距 / 排版走同一套规范，与现有主题色一致：
/// - 形状：圆角固定取 [AppRadii.dialog]（24px），不再各处默认 28；
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

/// 弹窗按钮震动档位（WB_SPEC_235 跟进 §2）
enum AppDialogHaptic { tap, select, medium }

/// [AppDialog] 的标准 action 构造：**按钮 + 震动 + 关掉自带反馈**三合一。
///
/// 为什么要有这个（WB_SPEC_235 跟进 §4）：2.5.0 的漏点里占比最大的一类不是
/// 「忘了写震动」，而是「AppDialog 外壳是对的、按钮是调用方手写的」——外壳
/// 管不到 [AppDialog.actions] 里塞进来的裸 `TextButton` / `FilledButton`。
/// 把按钮做成标准件后，调用方写 action 时就自带档位与 `enableFeedback: false`，
/// 结构上不再有「补一个漏一个」的口子。
///
/// 档位默认：破坏性（[destructive]）→ [AppDialogHaptic.medium]（删除确认要让
/// 手指意识到份量），其余 → [AppDialogHaptic.tap]；需要 select 时显式传 [haptic]。
///
/// 视觉与旧行为完全一致：[primary] / [destructive] 出 `FilledButton`
/// （破坏性用 error 色），否则出 `TextButton`——所以既有的
/// `find.widgetWithText(FilledButton, '删除')` 一类测试仍然命中。
class AppDialogAction extends StatelessWidget {
  const AppDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
    this.foreground,
    this.haptic,
  });

  final String label;

  /// 点击回调（先震动、后回调）；null = 禁用态，不震
  final VoidCallback? onPressed;

  /// 出 `FilledButton`（主动色）而非 `TextButton`
  final bool primary;

  /// 破坏性：error 色 + 默认 medium 档
  final bool destructive;

  /// 文字色覆盖（仅 [TextButton] 分支用：如「放弃」这类次要但需警示的按钮）
  final Color? foreground;

  /// 显式指定档位；不传则按 [destructive] 取默认
  final AppDialogHaptic? haptic;

  AppDialogHaptic get _effectiveHaptic =>
      haptic ?? (destructive ? AppDialogHaptic.medium : AppDialogHaptic.tap);

  void _fire() {
    switch (_effectiveHaptic) {
      case AppDialogHaptic.tap:
        AppHaptics.tap();
      case AppDialogHaptic.select:
        AppHaptics.select();
      case AppDialogHaptic.medium:
        AppHaptics.medium();
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = onPressed == null
        ? null
        : () {
            _fire();
            onPressed!();
          };
    if (primary || destructive) {
      final scheme = Theme.of(context).colorScheme;
      return FilledButton(
        style: destructive
            ? FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
                enableFeedback: false,
              )
            : FilledButton.styleFrom(enableFeedback: false),
        onPressed: handler,
        child: Text(label),
      );
    }
    return TextButton(
      style: TextButton.styleFrom(
        enableFeedback: false,
        foregroundColor: foreground,
      ),
      onPressed: handler,
      child: Text(label),
    );
  }
}

/// 统一信息弹窗（ⓘ 说明、公告等只告知不决策的场景）
///
/// 返回用户点的那个按钮的值（默认只有「知道了」，点哪都是 null）。
/// [barrierDismissible] 默认 true（点遮罩关闭）；引导类弹窗可显式传 false。
Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = '知道了',
  bool barrierDismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AppDialog(
      title: title,
      content: AppDialogText(message),
      actions: [
        // WB_SPEC_235 §6 / 跟进 §4：按钮走标准 action 构造（带 tap 档 +
        // 关掉自带反馈），不再手写 TextButton
        AppDialogAction(
          label: actionLabel,
          onPressed: () => Navigator.pop(ctx),
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
/// [barrierDismissible] 默认 true；「不可点外取消」的引导类弹窗显式传 false。
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      return AppDialog(
        title: title,
        content: AppDialogText(message),
        actions: [
          // 取消：轻点档（WB_SPEC_235 §6）
          AppDialogAction(
            label: cancelLabel,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          // 确认：普通确认轻点档；破坏性确认（删除/覆盖恢复）中档，
          // 让手指在「点下去」这一下就意识到这一步份量更重
          AppDialogAction(
            label: confirmLabel,
            primary: true,
            destructive: destructive,
            onPressed: () => Navigator.pop(ctx, true),
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
      // WB_SPEC_235 §7：ⓘ 说明按钮 = 轻点档（全站唯一实现，改这一处即覆盖
      // 设置行与设置子页的所有 ⓘ）；自带反馈关掉防双震
      onPressed: () {
        AppHaptics.tap();
        onPressed();
      },
      enableFeedback: false,
      tooltip: tooltip,
      icon: const Icon(Icons.info_outline),
      iconSize: 18,
      color: Theme.of(context).colorScheme.outline,
    );
  }
}
