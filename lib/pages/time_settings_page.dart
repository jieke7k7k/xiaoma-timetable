import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../ui/grid_metrics.dart';
import '../ui/settings_entry_row.dart';
import '../ui/settings_line_frame.dart';
import '../widgets/app_dialog.dart';

/// 作息时间设置页（WB_SPEC_228 §5）。
///
/// 父页从「4 张卡 + 13 节全平铺」收成「2 行入口 + 上/下/晚三段折叠」：
/// - 「节次数量与分段」进专项子页（[SectionRulesBody] 承接原 4 张卡的控件，
///   绑定、校验、持久化一字未动）；
/// - 三段共用一个大框（线框形态 A），默认只展开当前时段；
/// - 单节卡片 72dp → 56dp。
class TimeSettingsPage extends ConsumerWidget {
  const TimeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    final segSettings = ref.watch(segmentSettingsProvider).value;
    final lunch = segSettings?.lunchAfterSection ?? 5;
    final dinner = segSettings?.dinnerAfterSection ?? 9;
    final initialBand = currentTimeBand(DateTime.now());

    final morning = slots.where((s) => s.section <= lunch).toList();
    final afternoon = slots
        .where((s) => s.section > lunch && s.section <= dinner)
        .toList();
    final evening = slots.where((s) => s.section > dinner).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('作息时间')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        children: [
          // §5：2 行入口，各 56dp，标题左、右端当前值 + ›
          SettingsLineFrame(
            title: '全局规则',
            children: [
              SettingsEntryRow(
                title: '节次数量与分段',
                value:
                    '共 ${slots.length} 节 ($lunch-${dinner - lunch}-${slots.length - dinner}) · 含午休晚餐',
                route: '/settings-section-rules',
              ),
              SettingsEntryRow(
                title: '一键套用与批量推算',
                value: '按首节与课间推算',
                onTap: () => _openPresetSheet(context, ref),
              ),
            ],
          ),

          // §5：三段共用一个大框；午休随上午组、晚餐随下午组
          SettingsLineFrame(
            title: '各节上下课时间（点击时间直接修改）',
            dividers: false,
            children: [
              _BandTile(
                key: const Key('time_band_morning'),
                title: '上午',
                count: morning.length,
                expanded: initialBand == TimeBand.morning,
                children: [
                  for (final s in morning) _buildSlotCard(context, ref, s),
                ],
              ),
              if (morning.isNotEmpty && afternoon.isNotEmpty)
                _buildIntervalRow(context, '午休', morning.last.endTime,
                    afternoon.first.startTime),
              _BandTile(
                key: const Key('time_band_afternoon'),
                title: '下午',
                count: afternoon.length,
                expanded: initialBand == TimeBand.afternoon,
                children: [
                  for (final s in afternoon) _buildSlotCard(context, ref, s),
                ],
              ),
              if (afternoon.isNotEmpty && evening.isNotEmpty)
                _buildIntervalRow(context, '晚餐', afternoon.last.endTime,
                    evening.first.startTime),
              _BandTile(
                key: const Key('time_band_evening'),
                title: '晚上',
                count: evening.length,
                expanded: initialBand == TimeBand.evening,
                tailHint: true,
                children: [
                  for (final s in evening) _buildSlotCard(context, ref, s),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.group),
        ],
      ),
    );
  }

  /// 一键套用弹层：只列现代码已有的「常用大节时间」，行为与原按钮一致。
  void _openPresetSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('一键套用与批量推算',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              title: const Text('常用大节时间'),
              subtitle: const Text('第 1-2 节 09:40–12:00，第 3-4 节 14:00–16:20'),
              onTap: () {
                Navigator.pop(ctx);
                _applyPreset(context, ref);
              },
            ),
            ListTile(
              title: Text(
                '取消',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyPreset(BuildContext context, WidgetRef ref) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '套用常用大节时间',
      message: '将前 4 节课设置为：\n\n第 1 节 09:40-10:40\n第 2 节 10:40-12:00\n'
          '第 3 节 14:00-15:10\n第 4 节 15:10-16:20\n\n确定套用吗？',
      confirmLabel: '套用',
    );
    if (ok != true) return;
    try {
      await ref.read(timeSlotsProvider.notifier).applyPresetBigSections();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已套用常用大节时间')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('套用失败：$e')));
      }
    }
  }

  Future<void> _pickTime(
      BuildContext context, WidgetRef ref, TimeSlot slot, bool isStart) async {
    final initial =
        _parseTimeOfDay(isStart ? slot.startTime : slot.endTime);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '第 ${slot.section} 节上课时间' : '第 ${slot.section} 节下课时间',
    );
    if (picked == null) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final updated = isStart
        ? slot.copyWith(startTime: text)
        : slot.copyWith(endTime: text);
    try {
      await ref.read(timeSlotsProvider.notifier).updateSlot(updated);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  TimeOfDay _parseTimeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts[1]) ?? 0);
  }

  /// §5：单节卡片 72dp → 56dp
  Widget _buildSlotCard(
      BuildContext context, WidgetRef ref, TimeSlot slot) {
    return SizedBox(
      height: kSettingsSingleRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${slot.section}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(context, ref, slot, true),
                icon: const Icon(Icons.play_arrow_outlined, size: 16),
                label: Text(slot.startTime),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('~'),
            ),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(context, ref, slot, false),
                icon: const Icon(Icons.stop_outlined, size: 16),
                label: Text(slot.endTime),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前时段（§5）：06:00–12:00 上午、12:00–18:00 下午、18:00–次日 06:00 晚上。
///
/// 抽成纯函数便于测试；抽出来后「默认只展开当前时段」不依赖真实时钟注入。
enum TimeBand { morning, afternoon, evening }

TimeBand currentTimeBand(DateTime now) {
  final h = now.hour;
  if (h >= 6 && h < 12) return TimeBand.morning;
  if (h >= 12 && h < 18) return TimeBand.afternoon;
  return TimeBand.evening;
}

/// 三段折叠之一：默认展开当前时段；`tailHint` 只在晚上段末尾显示提示。
class _BandTile extends StatelessWidget {
  const _BandTile({
    super.key,
    required this.title,
    required this.count,
    required this.expanded,
    required this.children,
    this.tailHint = false,
  });

  final String title;
  final int count;
  final bool expanded;
  final List<Widget> children;
  final bool tailHint;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: expanded,
      title: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            '$count 节',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      children: [
        ...children,
        if (tailHint)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              '提示：修改即时生效，周视图左侧时间轴会自动同步。',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// 段间间隔信息行：由上一段最后一节的 endTime 到下一段第一节的 startTime 自动算出
Widget _buildIntervalRow(
    BuildContext context, String label, String from, String to) {
  final minutes = _minutesBetween(from, to);
  final colorScheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
    child: Row(
      children: [
        Icon(Icons.access_time, size: 16, color: colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label $from – $to · ${_formatDuration(minutes)}',
            style: TextStyle(color: colorScheme.outline, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

/// WB_SPEC_228 §4.4《节次数量与分段规则》的正文（作息父页第 1 行入口进来）。
///
/// 原作息页 4 张卡里的控件按 §4.4 归进三个线框组，provider、校验、
/// 落库、SnackBar 文案一字未动；第 3 层全平铺。
class SectionRulesBody extends ConsumerWidget {
  const SectionRulesBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    final courses = ref.watch(coursesProvider).value ?? [];
    final segSettings = ref.watch(segmentSettingsProvider).value;
    final lunch = segSettings?.lunchAfterSection ?? 5;
    final dinner = segSettings?.dinnerAfterSection ?? 9;
    final maxSection = slots.isEmpty ? 12 : slots.length;
    final band = ref.watch(bandSettingsProvider).value ?? const BandSettings();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsLineFrame(
          title: '节次数量',
          children: [
            _StepperRow(
              title: '每日节次总数',
              subtitle: '可自定义 4 ~ 20 节',
              value: slots.length,
              min: 4,
              max: 20,
              onChanged: (v) => _changeSectionCount(
                  context, ref, v, slots.length, courses),
            ),
          ],
        ),
        SettingsLineFrame(
          title: '分段设置',
          children: [
            _StepperRow(
              title: '午休在第几节课之后',
              value: lunch,
              min: 1,
              max: dinner - 1,
              onChanged: (v) => ref
                  .read(segmentSettingsProvider.notifier)
                  .setLunchAfterSection(v),
            ),
            _StepperRow(
              title: '晚餐在第几节课之后',
              value: dinner,
              min: lunch + 1,
              max: maxSection,
              onChanged: (v) => ref
                  .read(segmentSettingsProvider.notifier)
                  .setDinnerAfterSection(v),
            ),
          ],
        ),
        SettingsLineFrame(
          title: '休息时段',
          children: [
            SettingsSwitchRow(
              title: '午休',
              value: band.lunchVisible,
              onChanged: (v) => ref
                  .read(bandSettingsProvider.notifier)
                  .setLunchVisible(v),
            ),
            _TimeRow(
              title: '午休开始',
              value: band.lunchStart,
              onTap: () => _pickBandTime(context, ref,
                  lunch: true, isStart: true),
            ),
            _TimeRow(
              title: '午休结束',
              value: band.lunchEnd,
              onTap: () => _pickBandTime(context, ref,
                  lunch: true, isStart: false),
            ),
            SettingsSwitchRow(
              title: '晚间',
              value: band.dinnerVisible,
              onChanged: (v) => ref
                  .read(bandSettingsProvider.notifier)
                  .setDinnerVisible(v),
            ),
            _TimeRow(
              title: '晚间开始',
              value: band.dinnerStart,
              onTap: () => _pickBandTime(context, ref,
                  lunch: false, isStart: true),
            ),
            _TimeRow(
              title: '晚间结束',
              value: band.dinnerEnd,
              onTap: () => _pickBandTime(context, ref,
                  lunch: false, isStart: false),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _changeSectionCount(BuildContext context, WidgetRef ref,
      int target, int current, List<Course> courses) async {
    final notifier = ref.read(timeSlotsProvider.notifier);
    if (target > current) {
      for (var i = current; i < target; i++) {
        await notifier.addSection();
      }
    } else if (target < current) {
      final affected = courses.where((c) => c.endSection > target).length;
      if (affected > 0) {
        final ok = await showAppConfirmDialog(
          context,
          title: '减少节次',
          message: '第 ${target + 1} 节及之后还有 $affected 门课程，'
              '减少后这些课程将没有对应的上课时间。确定要减少吗？',
          confirmLabel: '确定减少',
        );
        if (ok != true) return;
      }
      for (var i = current; i > target; i--) {
        await notifier.removeLastSection();
      }
    }
  }

  Future<void> _pickBandTime(
    BuildContext context,
    WidgetRef ref, {
    required bool lunch,
    required bool isStart,
  }) async {
    final band = ref.read(bandSettingsProvider).value ?? const BandSettings();
    final current = isStart
        ? (lunch ? band.lunchStart : band.dinnerStart)
        : (lunch ? band.lunchEnd : band.dinnerEnd);
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTimeOfDay(current),
      helpText: lunch ? '午休时间' : '晚间时间',
    );
    if (picked == null) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    final start = isStart ? text : (lunch ? band.lunchStart : band.dinnerStart);
    final end = isStart ? (lunch ? band.lunchEnd : band.dinnerEnd) : text;
    final ok = lunch
        ? await ref.read(bandSettingsProvider.notifier).setLunchTime(start, end)
        : await ref
            .read(bandSettingsProvider.notifier)
            .setDinnerTime(start, end);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开始时间必须早于结束时间')),
      );
    }
  }

  TimeOfDay _parseTimeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0);
  }
}

/// 步进器行（56dp / 带副标题 72dp）
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
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
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed:
                      value > min ? () => onChanged(value - 1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$value',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                IconButton(
                  onPressed:
                      value < max ? () => onChanged(value + 1) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 休息时段起止时间行（56dp）
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: kSettingsSingleRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 将 "HH:mm" 转为当天分钟数
int _toMinutes(String hhmm) {
  final parts = hhmm.split(':');
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

/// 两时刻间隔分钟数（跨天则按次日凌晨计）
int _minutesBetween(String from, String to) {
  var m = _toMinutes(to) - _toMinutes(from);
  if (m < 0) m += 24 * 60;
  return m;
}

/// 间隔时长文案：满 1 小时用「约 X 小时[ Y 分钟]」，不足 1 小时用「约 Y 分钟」
String _formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '约 $m 分钟';
  if (m == 0) return '约 $h 小时';
  return '约 $h 小时 $m 分钟';
}
