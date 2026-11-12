import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/time_slot.dart';
import '../providers/providers.dart' show SegmentSettings;
import 'app_styles.dart';

/// 全站统一的选择器（WB_SPEC_232 第 5 节）。
///
/// 230 定版后，App 里还剩 11 处原生 `DropdownButtonFormField`：弹出层是 Material
/// 默认浮层，套不上 [AppRadii.menu]；列表项与回显项被强制要求是同一个 Widget，
/// 塞时间文字和午休分隔行极别扭；内部固定箭头宽度还会在 360dp 窄屏上把三个框
/// 并排挤溢出。这里用「只读触发框 + 底部抽屉」替换掉它：
///
/// - 表单里的下拉 → [AppSelectField]（外观直接吃全局 `InputDecorationTheme`，
///   即 CleanGap 圆角 10 边框与填充色，不另画边框）；
/// - 设置页里的下拉 → [AppSelectSettingRow]（56dp 标准设置行，右侧当前值 + ›）；
/// - 弹出端统一收敛到 [showAppSelectSheet]，圆角走全局 `bottomSheetTheme`。
///
/// 选项模型 [AppSelectOption] 把「抽屉里的行」与「框里的简短回显」拆开：
/// 抽屉行可以是富内容（时间副文案、色条、用自身字体渲染的字体名），
/// 框里只放不带时间的短文案，窄屏不截断。

/// 抽屉里普通行的行高（px）；分隔行固定 [AppSelectOption.dividerHeight]
const double kAppSelectRowHeight = 48;

/// 抽屉里不可选分隔行的高度（px，WB_SPEC_232 第 7 节）
const double kAppSelectDividerHeight = 28;

/// 一个选项：值 + 抽屉行内容 + 框内简短回显
class AppSelectOption<T> {
  const AppSelectOption({
    required this.value,
    required this.shortLabel,
    String? label,
    this.subLabel,
    this.leading,
    this.trailing,
    this.labelStyle,
    this.height = kAppSelectRowHeight,
    this.enabled = true,
    this.isDivider = false,
  }) : label = label ?? shortLabel;

  /// 不可选分隔行（午休 / 晚餐）：纯文字、无值、不响应点击
  const AppSelectOption.divider({required String label})
      : value = null,
        shortLabel = '',
        label = label,
        subLabel = null,
        leading = null,
        trailing = null,
        labelStyle = null,
        height = kAppSelectDividerHeight,
        enabled = false,
        isDivider = true;

  /// 选中后回传给父级的值（分隔行为 null，永远不会被选中）
  final T? value;

  /// 框内的简短回显（如「第 5 节」，不带时间）
  final String shortLabel;

  /// 抽屉里的主文案
  final String label;

  /// 抽屉行右侧的副文案（如「11:20 – 12:00」）
  final String? subLabel;

  /// 抽屉行左侧富内容（配色方案的色条）
  final Widget? leading;

  /// 抽屉行右侧富内容（配色的代表色圆点），排在选中勾之前
  final Widget? trailing;

  /// 主文案样式（字体行用各自字体渲染）
  final TextStyle? labelStyle;

  /// 行高（节次行 44，其余 48；分隔行 28）
  final double height;

  /// false = 置灰不可点（结束节次抽屉里小于开始节次的那几节）
  final bool enabled;

  /// true = 分隔行（午休 / 晚餐），不参与选中
  final bool isDivider;
}

/// 表单里的只读选择框：点击先收键盘，再弹统一抽屉
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.labelText,
    required this.value,
    required this.options,
    required this.onChanged,
    this.sheetTitle,
    this.useRootNavigator = false,
  });

  /// 浮动标签（与改前 DropdownButtonFormField 的 labelText 一字不差）
  final String labelText;

  /// 当前值：受控组件，只渲染父级传进来的值，组件自己不缓存
  final T? value;

  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;

  /// 抽屉标题（默认用 [labelText]）
  final String? sheetTitle;

  /// 草稿弹窗等 Dialog 场景要传 true，否则抽屉会被 Dialog 裁剪
  final bool useRootNavigator;

  String get _short {
    for (final o in options) {
      if (!o.isDivider && o.value == value) return o.shortLabel;
    }
    return '';
  }

  Future<void> _open(BuildContext context) async {
    // 先收软键盘：否则键盘收起动画与抽屉弹出动画撞在一起会跳一下
    FocusScope.of(context).unfocus();
    final picked = await showAppSelectSheet<T>(
      context: context,
      title: sheetTitle ?? labelText,
      options: options,
      currentValue: value,
      useRootNavigator: useRootNavigator,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: InputDecorator(
        // 外观全部来自全局 InputDecorationTheme（CleanGap 圆角 10 边框 + 填充色），
        // 这里既不画边框也不设填充色，与 TextFormField 保持同一套
        isEmpty: false,
        decoration: InputDecoration(
          labelText: labelText,
          // 三个框并排：水平内边距收到 10dp，360dp 窄屏才装得下
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _short,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 4),
            // 紧凑 18dp 小箭头（原生下拉自带固定宽度箭头，是窄屏溢出的元凶之一）
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 设置页的选择行：56dp 标准设置行，右侧「当前值 + ›」，点开同一套抽屉
class AppSelectSettingRow<T> extends StatelessWidget {
  const AppSelectSettingRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.trailing,
    this.sheetTitle,
    this.footer,
  });

  final String title;
  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T> onChanged;

  /// 右侧当前值展示（配色 = 色条 + 方案名；字体 = 用该字体渲染的字体名）
  final Widget trailing;

  final String? sheetTitle;

  /// 抽屉底部的附加入口（字体页的「导入本地 TTF/OTF 字体」）
  final Widget? footer;

  Future<void> _open(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final picked = await showAppSelectSheet<T>(
      context: context,
      title: sheetTitle ?? title,
      options: options,
      currentValue: value,
      footer: footer,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _open(context),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          child: Row(
            children: [
              // 标题 5 : 右侧值 6 分宽：右侧值（长方案名/长字体名）优先占够，
              // 标题在极窄屏省略，两列都不会顶破 56dp 行宽
              Expanded(
                flex: 5,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Flexible(
                flex: 6,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 统一选择抽屉（全站唯一弹出端）：圆角走全局 bottomSheetTheme（[AppRadii.sheet]），
/// 最大高度屏幕 60%，当前项右侧打勾，打开时自动滚到当前已选行。
Future<T?> showAppSelectSheet<T>({
  required BuildContext context,
  required String title,
  required List<AppSelectOption<T>> options,
  T? currentValue,
  bool useRootNavigator = false,
  Widget? footer,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    // shape 交给全局 bottomSheetTheme（AppRadii.sheet），不在每个调用点各写一遍
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (_) => _AppSelectSheet<T>(
      title: title,
      options: options,
      currentValue: currentValue,
      footer: footer,
    ),
  );
}

class _AppSelectSheet<T> extends StatefulWidget {
  const _AppSelectSheet({
    required this.title,
    required this.options,
    required this.currentValue,
    this.footer,
  });

  final String title;
  final List<AppSelectOption<T>> options;
  final T? currentValue;
  final Widget? footer;

  @override
  State<_AppSelectSheet<T>> createState() => _AppSelectSheetState<T>();
}

class _AppSelectSheetState<T> extends State<_AppSelectSheet<T>> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    // 行高固定，直接按「当前项之前所有行的高度」算出初始偏移，
    // 再往上留两行上下文——长列表不用用户自己翻找当前值
    var offset = 0.0;
    var currentTop = 0.0;
    var found = false;
    for (final o in widget.options) {
      if (!o.isDivider && !found && o.value == widget.currentValue) {
        currentTop = offset;
        found = true;
      }
      offset += o.height;
    }
    final initial =
        found ? math.max(0.0, currentTop - kAppSelectRowHeight * 2) : 0.0;
    _controller = ScrollController(initialScrollOffset: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.l,
              AppSpacing.l,
              AppSpacing.l,
              AppSpacing.s,
            ),
            child: Text(
              widget.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              controller: _controller,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in widget.options)
                    if (o.isDivider)
                      SizedBox(
                        height: kAppSelectDividerHeight,
                        child: Center(
                          child: Text(
                            o.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      )
                    else
                      _SelectRow<T>(
                        option: o,
                        selected: o.value == widget.currentValue,
                      ),
                  if (widget.footer != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s),
                      child: widget.footer!,
                    ),
                  const SizedBox(height: AppSpacing.s),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectRow<T> extends StatelessWidget {
  const _SelectRow({required this.option, required this.selected});

  final AppSelectOption<T> option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      enabled: option.enabled,
      minTileHeight: option.height,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      leading: option.leading,
      title: Text(
        option.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (option.labelStyle ?? const TextStyle()).copyWith(
          fontSize: option.labelStyle?.fontSize ?? 14,
          // 选中态主色加粗（WB_SPEC_232 第 7 节）
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: !option.enabled
              ? scheme.outline
              : (selected ? scheme.primary : scheme.onSurface),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (option.trailing != null) ...[
            option.trailing!,
            const SizedBox(width: AppSpacing.s),
          ],
          if (option.subLabel != null)
            Text(
              option.subLabel!,
              style: TextStyle(
                fontSize: 12.5,
                color: option.enabled
                    ? scheme.onSurfaceVariant
                    : scheme.outline,
                // 等宽数字，一列时间右对齐不抖动
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (selected) ...[
            const SizedBox(width: AppSpacing.s),
            Icon(Icons.check, size: 18, color: scheme.primary),
          ],
        ],
      ),
      onTap: option.enabled
          ? () => Navigator.pop(context, option.value)
          : null,
    );
  }
}

/// 星期选项（编辑页 / 调课页 / 草稿弹窗共用这一份）
List<AppSelectOption<int>> buildWeekdayOptions() {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  return [
    for (var d = 1; d <= 7; d++)
      AppSelectOption(value: d, shortLabel: '周${names[d - 1]}'),
  ];
}

/// 节次选项（三处表单共用）：行里带上下课时间，并在午休 / 晚餐分段点后插入分隔行
///
/// - [slots] 来自 `timeSlotsProvider`（用户改过作息后时间跟着变，不写死）；
/// - [seg] 的分段点决定分隔行位置（午休默认第 5 节后、晚餐默认第 9 节后）；
/// - [minSection] 非空时小于它的节次置灰（结束节次抽屉不允许选到开始节次之前）。
List<AppSelectOption<int>> buildSectionOptions({
  required List<TimeSlot> slots,
  SegmentSettings? seg,
  int? minSection,
}) {
  final sorted = [...slots]..sort((a, b) => a.section.compareTo(b.section));
  final bySection = {for (final s in sorted) s.section: s};
  final lunchAfter = seg?.lunchAfterSection ?? 5;
  final dinnerAfter = seg?.dinnerAfterSection ?? 9;
  final out = <AppSelectOption<int>>[];
  for (final s in sorted) {
    out.add(AppSelectOption(
      value: s.section,
      // 框内只显简短节次，不带时间（WB_SPEC_232 第 7 节：富展示与回显分离）
      shortLabel: '第 ${s.section} 节',
      subLabel: '${s.startTime} – ${s.endTime}',
      height: 44,
      enabled: minSection == null || s.section >= minSection,
    ));
    final next = bySection[s.section + 1];
    if (next == null) continue;
    // 分隔行时间取相邻两节的边界：上一节下课 ~ 下一节上课
    if (s.section == lunchAfter) {
      out.add(AppSelectOption.divider(
        label: '— 午休 (${s.endTime}–${next.startTime}) —',
      ));
    }
    if (s.section == dinnerAfter) {
      out.add(AppSelectOption.divider(
        label: '— 晚餐 (${s.endTime}–${next.startTime}) —',
      ));
    }
  }
  return out;
}
