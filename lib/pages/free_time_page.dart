import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../utils/free_time.dart';
import '../utils/override_effect.dart';
import '../utils/week_calc.dart';
import '../widgets/empty_state.dart';

/// 空闲时段页（1.2.0）
///
/// 按周列出每天没课的时段（节次区间 + 起止时间 + 时长），
/// 排实验、约自习、约见面之前不用再对着格子一段段数。
/// 数据口径与课表一致：先应用单次调课，再按周次/单双周过滤。
class FreeTimePage extends ConsumerStatefulWidget {
  const FreeTimePage({super.key});

  @override
  ConsumerState<FreeTimePage> createState() => _FreeTimePageState();
}

class _FreeTimePageState extends ConsumerState<FreeTimePage> {
  int? _week;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(currentSemesterProvider).value;
    final courses = ref.watch(coursesProvider).value ?? const [];
    final overrides = ref.watch(courseOverridesProvider).value ?? const [];
    final slots = ref.watch(timeSlotsProvider).value ?? const [];
    final todayWeek = ref.watch(todayWeekProvider);
    if (semester == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final week = (_week ?? (todayWeek < 1 ? 1 : todayWeek))
        .clamp(1, semester.totalWeeks);
    final dates =
        WeekCalc.weekDatesOf(DateTime.parse(semester.startDate), week);
    final effective = effectiveCoursesForWeek(
            courses: courses, overrides: overrides, week: week)
        .where((c) => c.isActiveInWeek(week))
        .toList();
    final blocks = freeBlocksForWeek(effective, slots);
    final totalSections = slots.isEmpty ? 0 : slots.length;

    return Scaffold(
      appBar: AppBar(title: const Text('空闲时段'), centerTitle: true),
      body: Column(
        children: [
          // 周次切换条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一周',
                  onPressed: week > 1
                      ? () => setState(() => _week = week - 1)
                      : null,
                ),
                Column(
                  children: [
                    Text('第 $week 周',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      '${dates.first.month}月${dates.first.day}日 - '
                      '${dates.last.month}月${dates.last.day}日',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一周',
                  onPressed: week < semester.totalWeeks
                      ? () => setState(() => _week = week + 1)
                      : null,
                ),
              ],
            ),
          ),
          if (week != todayWeek)
            TextButton.icon(
              onPressed: () =>
                  setState(() => _week = todayWeek < 1 ? 1 : todayWeek),
              icon: const Icon(Icons.today_outlined, size: 16),
              label: const Text('回到本周'),
            ),
          const Divider(height: 1),
          Expanded(
            child: slots.isEmpty
                ? const EmptyState(
                    icon: Icons.schedule_outlined,
                    title: '还没有作息时间',
                    message: '先在设置里配置作息，才能算出空闲时段',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: 7,
                    itemBuilder: (context, i) {
                      final day = i + 1;
                      final date = dates[i];
                      final dayBlocks =
                          blocks.where((b) => b.dayOfWeek == day).toList();
                      final isToday = _isSameDay(date, DateTime.now());
                      final allFree = dayBlocks.length == 1 &&
                          dayBlocks.single.sectionCount >= totalSections &&
                          totalSections > 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '周${_weekNames[i]} ${date.month}月${date.day}日',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15),
                                  ),
                                  if (isToday) ...[
                                    const SizedBox(width: 8),
                                    const Chip(
                                      label: Text('今天',
                                          style: TextStyle(fontSize: 11)),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                  const Spacer(),
                                  if (allFree)
                                    Text('全天没课',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w600))
                                  else if (dayBlocks.isEmpty)
                                    Text('全天有课',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline)),
                                ],
                              ),
                              if (!allFree && dayBlocks.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                for (final b in dayBlocks)
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.free_breakfast_outlined,
                                            size: 15),
                                        const SizedBox(width: 6),
                                        Text(
                                          '第 ${b.startSection}'
                                          '${b.endSection > b.startSection ? "–${b.endSection}" : ""} 节'
                                          ' · ${b.startTime}–${b.endTime}',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          b.durationText,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
