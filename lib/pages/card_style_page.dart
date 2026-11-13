import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../ui/settings_entry_row.dart';
import '../ui/settings_line_frame.dart';
import 'settings_sections.dart' show AppearancePreviewCard;

/// WB_SPEC_228 §4.2《课程卡片样式》：5 项，全平铺，一个线框包住。
///
/// 子页内部控件顺序硬规则（Argon 第四轮补 2）：滑杆归拢置顶、开关集中沉底；
/// 中间是圆角 / 内边距 / 阴影等分段项。v3 样品即此顺序，这里沿用现代码的
/// 5 个控件（格子圆角半径 / 卡片文字大小 / 显示教室 / 显示老师 / 显示备注）。
class CardStylePage extends ConsumerWidget {
  const CardStylePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    void apply(UiSettings next) => notifier.apply(next);

    return Scaffold(
      appBar: AppBar(title: const Text('课程卡片样式'), centerTitle: true),
      body: ListView(
        children: [
          const AppearancePreviewCard(),
          SettingsLineFrame(
            title: '卡片样式',
            children: [
              // 滑杆归拢置顶
              SettingsSliderRow(
                label: '格子圆角半径',
                valueText: '${ui.cornerRadius.round()} px',
                value: ui.cornerRadius,
                min: 0,
                max: 20,
                divisions: 20,
                onChanged: (v) => apply(ui.copyWith(cornerRadius: v)),
              ),
              SettingsSliderRow(
                label: '卡片文字大小',
                valueText: '${(ui.cardTextScale * 100).round()}%',
                value: ui.cardTextScale,
                min: UiSettings.textScaleMin,
                max: UiSettings.textScaleMax,
                divisions: 50,
                onChanged: (v) => apply(ui.copyWith(cardTextScale: v)),
              ),
              // 开关集中沉底
              SettingsSwitchRow(
                title: '显示教室',
                value: ui.showClassroom,
                onChanged: (v) => apply(ui.copyWith(showClassroom: v)),
              ),
              SettingsSwitchRow(
                title: '显示老师',
                value: ui.showTeacher,
                onChanged: (v) => apply(ui.copyWith(showTeacher: v)),
              ),
              SettingsSwitchRow(
                title: '显示备注',
                subtitle: '备注过长时自动省略',
                value: ui.showNote,
                onChanged: (v) => apply(ui.copyWith(showNote: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.group),
        ],
      ),
    );
  }
}
