import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import 'settings_sections.dart' show FontSettingsSection;

/// WB_SPEC_228 §4.3《显示字体》：1 个字体网格（线框内平铺）+ 导入入口。
///
/// 第 3 层专项子页全平铺：字体选项直接列在线框里，选中打勾；导入/删除与
/// 说明放在框外。控件逻辑（导入、删除、apply(fontId)）沿用 [FontSettingsSection]
/// 的 inline 形态，绑定一字未动。
class FontSettingsPage extends ConsumerWidget {
  const FontSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('显示字体'), centerTitle: true),
      body: ListView(
        children: [
          FontSettingsSection(
            ui: ui,
            apply: (next) => notifier.apply(next),
            inline: true,
          ),
          const SizedBox(height: AppSpacing.group),
        ],
      ),
    );
  }
}
