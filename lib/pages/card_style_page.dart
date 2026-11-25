import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../ui/settings_entry_row.dart';
import '../ui/settings_line_frame.dart';
import '../utils/app_haptics.dart';
import '../widgets/conflict_block.dart';
import 'settings_sections.dart' show AppearancePreviewCard;

/// WB_SPEC_228 §4.2《课程卡片样式》：5 项，全平铺，一个线框包住。
///
/// 子页内部控件顺序硬规则（Argon 第四轮补 2）：滑杆归拢置顶、开关集中沉底；
/// 中间是圆角 / 内边距 / 阴影等分段项。v3 样品即此顺序，这里沿用现代码的
/// 5 个控件（格子圆角半径 / 卡片文字大小 / 显示教室 / 显示老师 / 显示备注）
/// + WB_SPEC_253 §2 的 4 个开关（隐藏课名里的标记 / 隐藏地点里的校区 /
/// 格子内显示上课时间 / 上课地点前显示 @）。
/// WB_SPEC_237 §6：冲突课程块外观组另起一个线框在下方（预览 + 颜色三选 +
/// 强度滑杆 + 模糊开关）。
class CardStylePage extends ConsumerWidget {
  const CardStylePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    void apply(UiSettings next) => notifier.apply(next);

    // WB_SPEC_237 §6 演示预览数据（前半学期 药物化学 1–8 周 /
    // 后半学期 药理学 9–16 周，无老师名；预览高 100，半块 50px）
    final previewTopCourse = Course(
      semesterId: 1,
      name: '药物化学',
      classroom: '16-102',
      colorValue: 0xFF6B8E7B,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: [1, 2, 3, 4, 5, 6, 7, 8],
    );
    final previewBottomCourse = Course(
      semesterId: 1,
      name: '药理学',
      classroom: '16-639',
      colorValue: 0xFF7E9BB5,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: [9, 10, 11, 12, 13, 14, 15, 16],
    );

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
                subtitle: '备注以小字显示在卡片上',
                value: ui.showNote,
                onChanged: (v) => apply(ui.copyWith(showNote: v)),
              ),
              // WB_SPEC_253 §2：导入后可编辑是否隐藏（与显示教室/老师/备注同组）
              SettingsSwitchRow(
                title: '隐藏课名里的标记',
                subtitle: '隐藏开头的方括号前缀与尾部的「N周」',
                value: ui.hideNameMarks,
                onChanged: (v) => apply(ui.copyWith(hideNameMarks: v)),
              ),
              SettingsSwitchRow(
                title: '隐藏地点里的校区',
                subtitle: '去除地点开头的「…校区」前缀',
                value: ui.hideCampus,
                onChanged: (v) => apply(ui.copyWith(hideCampus: v)),
              ),
              SettingsSwitchRow(
                title: '格子内显示上课时间',
                subtitle: '在课程格内显示起止时间（如 09:50–10:35）',
                value: ui.showCellTime,
                onChanged: (v) => apply(ui.copyWith(showCellTime: v)),
              ),
              SettingsSwitchRow(
                title: '上课地点前显示 @',
                subtitle: '例如「@獐314」',
                value: ui.showLocationAt,
                onChanged: (v) => apply(ui.copyWith(showLocationAt: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.group),
          // WB_SPEC_237 §6：冲突课程块外观组
          SettingsLineFrame(
            title: '冲突课程块',
            children: [
              // 组内顶部实时预览（真实 ConflictBlock widget）
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Center(
                  child: SizedBox(
                    width: 200,
                    height: 100,
                    child: ConflictBlock(
                      topCourse: previewTopCourse,
                      bottomCourse: previewBottomCourse,
                      height: 100,
                      width: 200,
                      colorId: ui.conflictBlockColorId,
                      intensity: ui.conflictGradientIntensity,
                      blurEnabled: ui.conflictBlurEnabled,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              // 1. 颜色三选行
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('颜色',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ),
                    Row(
                      children: [
                        _buildColorChip(
                          context,
                          id: 'caramel',
                          name: '焦糖',
                          hex: '#EBC9A0 → #BE8A5A',
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEBC9A0), Color(0xFFBE8A5A)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          selected: ui.conflictBlockColorId == 'caramel',
                          onTap: () {
                            AppHaptics.tap();
                            apply(ui.copyWith(conflictBlockColorId: 'caramel'));
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildColorChip(
                          context,
                          id: 'mistBlue',
                          name: '雾蓝',
                          hex: '#B9C9D9 → #7E9BB5',
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB9C9D9), Color(0xFF7E9BB5)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          selected: ui.conflictBlockColorId == 'mistBlue',
                          onTap: () {
                            AppHaptics.tap();
                            apply(
                                ui.copyWith(conflictBlockColorId: 'mistBlue'));
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildColorChip(
                          context,
                          id: 'sage',
                          name: '豆沙绿',
                          hex: '#C2CDB4 → #8A9A7A',
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC2CDB4), Color(0xFF8A9A7A)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          selected: ui.conflictBlockColorId == 'sage',
                          onTap: () {
                            AppHaptics.tap();
                            apply(ui.copyWith(conflictBlockColorId: 'sage'));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 2. 渐变强度滑杆（震动由 SettingsSliderRow 内部按 235 §6 处理：
              // 档位真的变了才震，拖动中的像素级回调不重复震）
              SettingsSliderRow(
                label: '渐变强度',
                valueText: '${(ui.conflictGradientIntensity * 100).round()}%',
                value: ui.conflictGradientIntensity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) =>
                    apply(ui.copyWith(conflictGradientIntensity: v)),
              ),
              // 3. 模糊毛玻璃开关
              SettingsSwitchRow(
                title: '模糊',
                subtitle: '毛玻璃效果，下方格子呈虚化',
                value: ui.conflictBlurEnabled,
                onChanged: (v) => apply(ui.copyWith(conflictBlurEnabled: v)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.group),
        ],
      ),
    );
  }

  Widget _buildColorChip(
    BuildContext context, {
    required String id,
    required String name,
    required String hex,
    required Gradient gradient,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 选中态：2px 深色描边 + 右上角深色 ✓（规格 §6），不用主题色。
    const selectedColor = Color(0xFF1F2937);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? selectedColor : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Stack(
                children: [
                  if (selected)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child:
                          Icon(Icons.check, size: 16, color: selectedColor),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(name,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text(hex,
                style: TextStyle(fontSize: 9, color: scheme.outline),
                maxLines: 1),
          ],
        ),
      ),
    );
  }
}
