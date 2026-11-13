import 'package:flutter/material.dart';

import '../widgets/app_dialog.dart';

/// WB_SPEC_228 §2 全站统一 Token：
/// 单行 56dp / 双行 72dp / 滑杆行 72dp；组间距 24dp；
/// 行内边距左右 16dp、上下 12dp。
const double kSettingsSingleRowHeight = 56;
const double kSettingsDoubleRowHeight = 72;
const double kSettingsSliderRowHeight = 72;

/// 标准入口行：56dp（带副标题时 72dp），标题左、副标题可选、右端 ›。
///
/// 导航层级封顶 3 层：第 3 层专项子页全平铺，不再用本组件放 › 入口。
class SettingsEntryRow extends StatelessWidget {
  const SettingsEntryRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.valueWidget,
    this.route,
    this.onTap,
    this.showChevron = true,
  });

  final String title;
  final String? subtitle;

  /// 右端当前值文案（如「柔和」「系统默认」）
  final String? value;

  /// 右端富内容（如主题色圆点、课程配色 4 色带），排在文字值之前
  final Widget? valueWidget;

  final String? route;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final handler = onTap ??
        (route == null ? null : () => Navigator.pushNamed(context, route!));
    return InkWell(
      onTap: handler,
      child: SizedBox(
        height: subtitle == null
            ? kSettingsSingleRowHeight
            : kSettingsDoubleRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (valueWidget != null) valueWidget!,
              if (value != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              if (showChevron) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 滑杆行 72dp（§2）：标题固定宽 108，滑杆占满，右侧当前值。
class SettingsSliderRow extends StatelessWidget {
  const SettingsSliderRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kSettingsSliderRowHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                valueText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 开关行：内部仍是 SwitchListTile（保留既有 widget 测试与 ⓘ 说明按钮语义），
/// 描边与分隔线交给外层 [SettingsLineFrame]。
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.infoMessage,
    this.secondary,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;
  final String? infoMessage;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: secondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: infoMessage != null
          ? SettingsInfoTitle(title: title, message: infoMessage!)
          : Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      value: value,
      onChanged: onChanged,
    );
  }
}

/// 条目标题 + 旁挂 ⓘ 说明按钮（原 `_InfoTitle`，样式与交互一字不动）。
class SettingsInfoTitle extends StatelessWidget {
  const SettingsInfoTitle({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        AppInfoIconButton(
          tooltip: title,
          onPressed: () => showAppInfoDialog(
            context,
            title: title,
            message: message,
          ),
        ),
      ],
    );
  }
}
