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
/// - 三段各成独立线框（2.5.0 WB_SPEC_233 §5.1 去套娃），默认只展开当前时段；
/// - 单节卡片 72dp → 56dp，2.5.0 起去 ▷/▢ 大按钮，改「第 X 节」+ 两个时间块。
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

          // §5（233 重构）：组标题留在框外，上午 / 下午 / 晚上各成独立线框，
          // 框内只放一个段头；午休 / 晚餐间隔行移到框与框之间的留白区。
          // 「默认展开当前时段」保持现状（跟随时钟走，不固定上午）。
          const SettingsGroupHeader('各节上下课时间（点击时间直接修改）'),
          if (morning.isNotEmpty)
            SettingsLineFrame(
              title: '上午',
              showTitle: false,
              dividers: false,
              children: [
                _BandTile(
                  key: const Key('time_band_morning'),
                  title: '上午',
                  sectionRange: _sectionRange(morning),
                  timeRange: _timeRange(morning),
                  expanded: initialBand == TimeBand.morning,
                  children: [
                    for (final s in morning) _buildSlotCard(context, ref, s),
                  ],
                ),
              ],
            ),
          if (morning.isNotEmpty && afternoon.isNotEmpty)
            _buildIntervalRow(context, '午休', morning.last.endTime,
                afternoon.first.startTime),
          if (afternoon.isNotEmpty)
            SettingsLineFrame(
              title: '下午',
              showTitle: false,
              dividers: false,
              children: [
                _BandTile(
                  key: const Key('time_band_afternoon'),
                  title: '下午',
                  sectionRange: _sectionRange(afternoon),
                  timeRange: _timeRange(afternoon),
                  expanded: initialBand == TimeBand.afternoon,
                  children: [
                    for (final s in afternoon) _buildSlotCard(context, ref, s),
                  ],
                ),
              ],
            ),
          if (afternoon.isNotEmpty && evening.isNotEmpty)
            _buildIntervalRow(context, '晚餐', afternoon.last.endTime,
                evening.first.startTime),
          if (evening.isNotEmpty)
            SettingsLineFrame(
              title: '晚上',
              showTitle: false,
              dividers: false,
              children: [
                _BandTile(
                  key: const Key('time_band_evening'),
                  title: '晚上',
                  sectionRange: _sectionRange(evening),
                  timeRange: _timeRange(evening),
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

  /// 段头节次范围：按实际分段的节次起止算（14 节时晚上是 10–14 节，
  /// 不得按默认 13 节写死 10–13）。
  String _sectionRange(List<TimeSlot> band) {
    final first = band.first.section;
    final last = band.last.section;
    return first == last ? '（第 $first 节）' : '（第 $first–$last 节）';
  }

  /// 段头时段范围（空段不显示由调用方判空，这里只处理非空）
  String _timeRange(List<TimeSlot> band) =>
      '${band.first.startTime} – ${band.last.endTime}';

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

  /// §5.2（233 重构）：单节行 56dp，左侧「第 X 节」，右侧两个极简时间块
  /// `[开始] – [结束]`（不再是 ▷ / ▢ 两个大按钮）。点时间块仍弹 showTimePicker。
  Widget _buildSlotCard(
      BuildContext context, WidgetRef ref, TimeSlot slot) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: kSettingsSingleRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              '第 ${slot.section} 节',
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            _SlotTimeChip(
              key: ValueKey('slot_time_${slot.section}_start'),
              text: slot.startTime,
              semanticLabel: '第 ${slot.section} 节上课时间',
              onTap: () => _pickTime(context, ref, slot, true),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '–',
                style: TextStyle(fontSize: 13, color: scheme.outline),
              ),
            ),
            _SlotTimeChip(
              key: ValueKey('slot_time_${slot.section}_end'),
              text: slot.endTime,
              semanticLabel: '第 ${slot.section} 节下课时间',
              onTap: () => _pickTime(context, ref, slot, false),
            ),
          ],
        ),
      ),
    );
  }
}

/// §5.2：极简时间块（68×30、圆角 8、无描边、13.5sp w600 等宽数字）。
///
/// 仍是可点按钮（点按区域就是这个 68×30 的块），点开 showTimePicker。
class _SlotTimeChip extends StatelessWidget {
  const _SlotTimeChip({
    super.key,
    required this.text,
    required this.onTap,
    required this.semanticLabel,
  });

  final String text;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Semantics(
        label: semanticLabel,
        button: true,
        child: Container(
          width: 68,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // 浅色 #F3F4F6 / 深色 #222428（规格 §5.2 定值），无描边
            color: dark ? const Color(0xFF222428) : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
              // 等宽数字：两个块宽高一致，时间换位也不抖
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
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
///
/// §5.3（233 重构）：段头左右分栏——左「上午（第 1–5 节）」，右「08:00 – 12:00」
/// 与 ExpansionTile 自带箭头；箭头位置随 title 结构走，不另画。
class _BandTile extends StatelessWidget {
  const _BandTile({
    super.key,
    required this.title,
    required this.sectionRange,
    required this.expanded,
    required this.children,
    this.tailHint = false,
    this.timeRange,
  });

  final String title;

  /// 节次范围（如「（第 1–5 节）」），按实际分段点算
  final String sectionRange;

  final bool expanded;
  final List<Widget> children;
  final bool tailHint;

  /// 段头时段范围（如 08:00 – 12:00），空段为 null 时不显示
  final String? timeRange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      initiallyExpanded: expanded,
      // §5.3：段头 52dp
      minTileHeight: 52,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      childrenPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    sectionRange,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.outline),
                  ),
                ),
              ],
            ),
          ),
          if (timeRange != null)
            Text(
              timeRange!,
              style: TextStyle(
                fontSize: 13.5,
                color: scheme.outline,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          // 与 ExpansionTile 自带箭头之间留 4dp
          const SizedBox(width: 4),
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

/// 段间间隔信息行（§5.1）：移到框外留白区，纯文字居中、无图标无 emoji、36dp 高。
///
/// 时长仍由上一段最后一节的 endTime 到下一段第一节的 startTime 自动算出。
Widget _buildIntervalRow(
    BuildContext context, String label, String from, String to) {
  final minutes = _minutesBetween(from, to);
  final colorScheme = Theme.of(context).colorScheme;
  return SizedBox(
    height: 36,
    child: Center(
      child: Text(
        '$label $from – $to · ${_formatDuration(minutes)}',
        style: TextStyle(color: colorScheme.outline, fontSize: 13),
      ),
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
