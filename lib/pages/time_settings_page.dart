import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../ui/grid_metrics.dart';

/// 作息时间设置页
///
/// 逐节修改上下课时间（改动即时保存），支持一键套用常用大节时间
/// （第 1-2 节 09:40-12:00，第 3-4 节 14:00-16:20）。
/// 节次按「上午 / 下午 / 晚上」三段分组展示，分段点（午休/晚餐在第几节课之后）
/// 在顶部「分段设置」卡片用步进器调整并即时持久化；段与段之间显示由相邻节次时间
/// 自动算出的午休/晚餐间隔时长。修改后周视图左侧时间轴通过 timeSlotsProvider 自动同步刷新。
class TimeSettingsPage extends ConsumerWidget {
  const TimeSettingsPage({super.key});

  Future<void> _pickTime(
      BuildContext context, WidgetRef ref, TimeSlot slot, bool isStart) async {
    final initial = _parseTimeOfDay(
        isStart ? slot.startTime : slot.endTime);
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

  Future<void> _applyPreset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('套用常用大节时间'),
        content: const Text(
            '将前 4 节课设置为：\n\n第 1 节 09:40-10:40\n第 2 节 10:40-12:00\n第 3 节 14:00-15:10\n第 4 节 15:10-16:20\n\n确定套用吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('套用')),
        ],
      ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    final courses = ref.watch(coursesProvider).value ?? [];
    final segSettings = ref.watch(segmentSettingsProvider).value;
    final lunch = segSettings?.lunchAfterSection ?? 5;
    final dinner = segSettings?.dinnerAfterSection ?? 9;
    // 分段点步进器上限按当前最大节次钳制（slots 未加载完时回退 12）
    final maxSection = slots.isEmpty ? 12 : slots.length;

    return Scaffold(
      appBar: AppBar(title: const Text('作息时间')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 一键套用
          Card(
            child: ListTile(
              leading: const Icon(Icons.flash_on_outlined),
              title: const Text('一键套用常用大节时间'),
              subtitle: const Text('第 1-2 节 09:40-12:00，第 3-4 节 14:00-16:20'),
              trailing: FilledButton.tonal(
                onPressed: () => _applyPreset(context, ref),
                child: const Text('套用'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 每日节次总数（可自定义 4~20 节）
          _buildSectionCountCard(context, ref, slots.length, courses),
          const SizedBox(height: 12),
          // 分段设置
          _buildSegmentSettingsCard(context, ref, lunch, dinner, maxSection),
          const SizedBox(height: 12),
          // 休息时段（WB_SPEC_209 第 6 节）：午休/晚间显隐 + 自定义起止时间
          _buildBandSettingsCard(context, ref),
          const SizedBox(height: 12),
          Text('当前共 ${slots.length} 节课，点击时间即可修改：',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          ..._buildGroupedSlots(context, ref, slots, lunch, dinner),
          const SizedBox(height: 16),
          Text(
            '提示：修改即时生效，周视图左侧时间轴会自动同步。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  /// 「每日节次」卡片：步进器增减总节数（4~20 节）。
  /// 增加时在末尾按上一节时长顺延一节；减少时删最后一节，
  /// 若有课程占用将被删掉的节次，先弹窗确认再删。
  Widget _buildSectionCountCard(
      BuildContext context, WidgetRef ref, int count, List<Course> courses) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('每日节次', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('一天一共上多少节课，按自己学校的作息增减',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
            const SizedBox(height: 8),
            _SegmentStepper(
              label: '总节数',
              value: count,
              min: 4,
              max: 20,
              onChanged: (v) =>
                  _changeSectionCount(context, ref, v, count, courses),
            ),
          ],
        ),
      ),
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
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('减少节次'),
            content: Text('第 ${target + 1} 节及之后还有 $affected 门课程，'
                '减少后这些课程将没有对应的上课时间。确定要减少吗？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(d, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('确定减少')),
            ],
          ),
        );
        if (ok != true) return;
      }
      for (var i = current; i > target; i--) {
        await notifier.removeLastSection();
      }
    }
  }

  /// 「分段设置」卡片：两个步进器调整午休/晚餐分段点，改动即时持久化
  Widget _buildSegmentSettingsCard(BuildContext context, WidgetRef ref,
      int lunch, int dinner, int maxSection) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分段设置', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('决定作息时间的上午/下午/晚上分组，以及周视图午休/晚间分隔带位置',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
            const SizedBox(height: 8),
            _SegmentStepper(
              label: '午休在第几节课之后',
              value: lunch,
              min: 1,
              max: dinner - 1,
              onChanged: (v) => ref
                  .read(segmentSettingsProvider.notifier)
                  .setLunchAfterSection(v),
            ),
            _SegmentStepper(
              label: '晚餐在第几节课之后',
              value: dinner,
              min: lunch + 1,
              max: maxSection,
              onChanged: (v) => ref
                  .read(segmentSettingsProvider.notifier)
                  .setDinnerAfterSection(v),
            ),
          ],
        ),
      ),
    );
  }

  /// 「休息时段」卡片：午休/晚间各自显隐开关 + 起止时间选择器。
  /// 时间用系统时间选择器，开始必须早于结束，否则不保存并 SnackBar 提示。
  Widget _buildBandSettingsCard(BuildContext context, WidgetRef ref) {
    final band = ref.watch(bandSettingsProvider).value ?? const BandSettings();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('休息时段', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('决定周视图午休/晚间分隔带的显示与标注时间，关闭后不显示、不占位',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    )),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('午休',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              value: band.lunchVisible,
              onChanged: (v) =>
                  ref.read(bandSettingsProvider.notifier).setLunchVisible(v),
            ),
            _bandTimeRow(context, ref, '午休开始', band.lunchStart,
                lunch: true, isStart: true),
            _bandTimeRow(context, ref, '午休结束', band.lunchEnd,
                lunch: true, isStart: false),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('晚间',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              value: band.dinnerVisible,
              onChanged: (v) =>
                  ref.read(bandSettingsProvider.notifier).setDinnerVisible(v),
            ),
            _bandTimeRow(context, ref, '晚间开始', band.dinnerStart,
                lunch: false, isStart: true),
            _bandTimeRow(context, ref, '晚间结束', band.dinnerEnd,
                lunch: false, isStart: false),
          ],
        ),
      ),
    );
  }

  /// 一条起止时间行：点开系统时间选择器
  Widget _bandTimeRow(
    BuildContext context,
    WidgetRef ref,
    String label,
    String current, {
    required bool lunch,
    required bool isStart,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Text(
        current,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => _pickBandTime(context, ref, lunch: lunch, isStart: isStart),
    );
  }

  /// 选择午休/晚间起止时间：改完校验开始早于结束，否则不保存并提示
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

  /// 按「上午 / 下午 / 晚上」三段分组，段标题 + 各节卡片，段间插入间隔信息行
  List<Widget> _buildGroupedSlots(BuildContext context, WidgetRef ref,
      List<TimeSlot> slots, int lunch, int dinner) {
    final morning =
        slots.where((s) => s.section <= lunch).toList();
    final afternoon = slots
        .where((s) => s.section > lunch && s.section <= dinner)
        .toList();
    final evening = slots.where((s) => s.section > dinner).toList();

    final children = <Widget>[];

    void addHeader(String title) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
      ));
    }

    if (morning.isNotEmpty) {
      addHeader('上午');
      for (final s in morning) {
        children.add(_buildSlotCard(context, ref, s));
      }
    }
    if (morning.isNotEmpty && afternoon.isNotEmpty) {
      children.add(_buildIntervalRow(
          context, '午休', morning.last.endTime, afternoon.first.startTime));
    }
    if (afternoon.isNotEmpty) {
      addHeader('下午');
      for (final s in afternoon) {
        children.add(_buildSlotCard(context, ref, s));
      }
    }
    if (afternoon.isNotEmpty && evening.isNotEmpty) {
      children.add(_buildIntervalRow(
          context, '晚餐', afternoon.last.endTime, evening.first.startTime));
    }
    if (evening.isNotEmpty) {
      addHeader('晚上');
      for (final s in evening) {
        children.add(_buildSlotCard(context, ref, s));
      }
    }

    return children;
  }

  /// 单节课卡片：节次 + 开始/结束时间按钮（点击改时间，交互同原实现）
  Widget _buildSlotCard(BuildContext context, WidgetRef ref, TimeSlot slot) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Text('${slot.section}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickTime(context, ref, slot, true),
                icon: const Icon(Icons.play_arrow_outlined, size: 18),
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
                icon: const Icon(Icons.stop_outlined, size: 18),
                label: Text(slot.endTime),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 段间间隔信息行：由上一段最后一节的 endTime 到下一段第一节的 startTime 自动算出
  Widget _buildIntervalRow(
      BuildContext context, String label, String from, String to) {
    final minutes = _minutesBetween(from, to);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
}

/// 数值步进器：标签 + 减/加按钮 + 当前值，越界自动禁用对应按钮
class _SegmentStepper extends StatelessWidget {
  const _SegmentStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDec = value > min;
    final canInc = value < max;
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: canDec ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        IconButton(
          onPressed: canInc ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
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
