import 'package:flutter/material.dart';

import 'app_styles.dart';

/// WB_SPEC_228 §7 线框形态 A（全站统一）。
///
/// 标题留在框外左上方（距框顶 6dp），线框只包子项：
/// - 描边 1.0dp，浅色 #E5E7EB；深色为纯白 9%（Argon 第四轮评审确认
///   正好落在 8%～10% 区间内，无需改值）；
/// - 圆角 14dp，取 [AppRadii.card]；
/// - 框内相邻子项之间 0.5dp 分隔线，左右各缩进 16dp；
/// - 实时预览卡片自身有边框，不套本组件。
///
/// 条件渲染的隐藏行由调用方在构造 children 时用 `if` 过滤掉，本组件只按
/// 实际存在的子项插分隔线——因此不会出现「留空位 / 留分隔线」。
class SettingsLineFrame extends StatelessWidget {
  const SettingsLineFrame({
    super.key,
    required this.title,
    required this.children,
    this.dividers = true,
    this.showTitle = true,
  });

  final String title;
  final List<Widget> children;

  /// 作息页三段共用一个大框时，段间分隔由 ExpansionTile 自己画，关掉本组件的
  /// 统一分隔线，避免双线。
  final bool dividers;

  final bool showTitle;

  /// §7 定值：浅色描边
  static const Color kLightBorder = Color(0xFFE5E7EB);

  /// 框内分隔线（样品 v4 同色）
  static const Color kLightDivider = Color(0xFFECECEF);

  /// §7 定值：深色描边纯白 9%
  static const double kDarkBorderAlpha = 0.09;

  /// 深色框内分隔线（样品 v4 同口径）
  static const double kDarkDividerAlpha = 0.07;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = dark
        ? Colors.white.withValues(alpha: kDarkBorderAlpha)
        : kLightBorder;
    final dividerColor = dark
        ? Colors.white.withValues(alpha: kDarkDividerAlpha)
        : kLightDivider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          SettingsGroupHeader(title, top: AppSpacing.group, bottom: 6),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (dividers && i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: AppSpacing.l,
                      endIndent: AppSpacing.l,
                      color: dividerColor,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 分组标题：沿用现 `_Header` 样式（13sp / w600 / 小灰字），样式不动。
///
/// 线框形态 A 里标题在框外，`bottom` 固定 6dp（距框顶 6dp）；
/// `top` 默认 24dp（§2 组间距）。
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(
    this.title, {
    super.key,
    this.top = AppSpacing.group,
    this.bottom = 6,
  });

  final String title;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.l,
        top,
        AppSpacing.l,
        bottom,
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
