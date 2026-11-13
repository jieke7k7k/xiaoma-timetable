import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../ui/settings_entry_row.dart';
import '../ui/settings_line_frame.dart';
import 'settings_sections.dart' show AppearancePreviewCard;

/// WB_SPEC_228 §4.1《网格与表头设置》：9 项，拆「显示规则」「尺寸与网格线」两组。
///
/// 第 3 层专项子页：全平铺，无 › 入口、无 ExpansionTile；
/// 两条新增联动（自适应开→藏格子高度、网格线关→藏边框粗细）用条件渲染，
/// 隐藏时该行根本不进 children，因此不留空位、不留分隔线。
class AppearanceGridSettingsPage extends ConsumerWidget {
  const AppearanceGridSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    void apply(UiSettings next) => notifier.apply(next);

    final autoCollapse = ref.watch(autoCollapseWeekendProvider);
    final showOther = ref.watch(showOtherWeeksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('网格与表头设置'), centerTitle: true),
      body: ListView(
        children: [
          const AppearancePreviewCard(),
          SettingsLineFrame(
            title: '显示规则',
            children: [
              SettingsSwitchRow(
                title: '周末无课时自动收起周六日',
                value: autoCollapse,
                onChanged: (v) => ref
                    .read(autoCollapseWeekendProvider.notifier)
                    .toggle(v),
              ),
              // §4.1：ⓘ 只留「显示非本周课程」与下方「行高自适应一屏」两处
              SettingsSwitchRow(
                title: '显示非本周课程',
                infoMessage: '开启后其他周次的课程置灰显示，方便全局查看',
                value: showOther,
                onChanged: (v) =>
                    ref.read(showOtherWeeksProvider.notifier).toggle(v),
              ),
              SettingsSwitchRow(
                title: '今天整列边框高亮',
                value: ui.highlightTodayColumn,
                onChanged: (v) =>
                    apply(ui.copyWith(highlightTodayColumn: v)),
              ),
              SettingsSwitchRow(
                title: '节数栏显示时间',
                subtitle: '左侧节数栏显示每节上下课时间',
                value: ui.axisShowTime,
                onChanged: (v) => apply(ui.copyWith(axisShowTime: v)),
              ),
              SettingsSwitchRow(
                title: '标题显示单双周',
                subtitle: '标题栏显示当前周是单周还是双周',
                value: ui.showWeekParity,
                onChanged: (v) => apply(ui.copyWith(showWeekParity: v)),
              ),
            ],
          ),
          SettingsLineFrame(
            title: '尺寸与网格线',
            children: [
              SettingsSwitchRow(
                title: '行高自适应一屏',
                infoMessage: '按屏幕高度均分行高，整张课表不用上下滚',
                value: ui.autoFitHeight,
                onChanged: (v) => apply(ui.copyWith(autoFitHeight: v)),
              ),
              // 联动 ②：自适应开时隐藏「课程格子高度」滑杆行
              if (!ui.autoFitHeight)
                SettingsSliderRow(
                  label: '课程格子高度',
                  valueText: '${ui.cellHeight.round()} px',
                  value: ui.cellHeight,
                  min: 44,
                  max: 96,
                  divisions: 26,
                  onChanged: (v) => apply(ui.copyWith(cellHeight: v)),
                ),
              SettingsSwitchRow(
                title: '显示网格线',
                value: ui.showGridLines,
                onChanged: (v) => apply(ui.copyWith(showGridLines: v)),
              ),
              // 联动 ③：网格线关时隐藏「格子边框粗细」滑杆行
              if (ui.showGridLines)
                SettingsSliderRow(
                  label: '格子边框粗细',
                  valueText: ui.borderWidth <= 0
                      ? '无边框'
                      : '${ui.borderWidth.toStringAsFixed(1)} px',
                  value: ui.borderWidth,
                  min: UiSettings.borderWidthMin,
                  max: UiSettings.borderWidthMax,
                  divisions: 30,
                  onChanged: (v) => apply(ui.copyWith(borderWidth: v)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.group),
        ],
      ),
    );
  }
}
