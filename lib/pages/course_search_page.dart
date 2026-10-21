import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../providers/providers.dart';
import '../utils/week_parser.dart';
import '../widgets/empty_state.dart';

/// 课程搜索页（1.2.0）
///
/// 在当前学期全部课程里按课名 / 老师 / 教室模糊搜索，
/// 点结果直接跳到那门课所在的周（本周有课跳本周，否则跳最近的一次）。
class CourseSearchPage extends ConsumerStatefulWidget {
  const CourseSearchPage({super.key});

  @override
  ConsumerState<CourseSearchPage> createState() => _CourseSearchPageState();
}

class _CourseSearchPageState extends ConsumerState<CourseSearchPage> {
  String _query = '';

  static const _weekNames = ['', '一', '二', '三', '四', '五', '六', '日'];

  /// 点结果要跳的周：本周有这门课就停本周；否则最近的未来周；再否则最后一个上课周
  int _targetWeek(Course c, int todayWeek, int totalWeeks) {
    if (todayWeek >= 1 && c.isActiveInWeek(todayWeek)) return todayWeek;
    int? firstFuture;
    int? lastActive;
    for (var w = 1; w <= totalWeeks; w++) {
      if (!c.isActiveInWeek(w)) continue;
      lastActive = w;
      if (w >= todayWeek && firstFuture == null) firstFuture = w;
    }
    return firstFuture ?? lastActive ?? (todayWeek < 1 ? 1 : todayWeek);
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesProvider).value ?? const <Course>[];
    final semester = ref.watch(currentSemesterProvider).value;
    final todayWeek = ref.watch(todayWeekProvider);
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? const <Course>[]
        : courses
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                (c.teacher?.toLowerCase().contains(q) ?? false) ||
                (c.classroom?.toLowerCase().contains(q) ?? false))
            .toList()
      ..sort((a, b) => a.dayOfWeek != b.dayOfWeek
          ? a.dayOfWeek.compareTo(b.dayOfWeek)
          : a.startSection.compareTo(b.startSection));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜课名 / 老师 / 教室',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清空',
              onPressed: () => setState(() => _query = ''),
            ),
        ],
      ),
      body: q.isEmpty
          ? const EmptyState(
              icon: Icons.search_outlined,
              title: '搜索当前学期的课程',
              message: '输入课名、老师或教室，如「药理」「教3-201」',
            )
          : results.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_outlined,
                  title: '没有找到「$_query」',
                  message: '换个关键词试试，或确认课程在当前学期里',
                )
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = results[i];
                    return ListTile(
                      leading: Container(
                        width: 12,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c.colorValue),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      title: Text(c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '周${_weekNames[c.dayOfWeek]} 第${c.startSection}'
                        '${c.endSection > c.startSection ? "-${c.endSection}" : ""}节'
                        ' · ${c.classroom?.isNotEmpty == true ? c.classroom : "未填教室"}'
                        '${c.teacher?.isNotEmpty == true ? " · ${c.teacher}" : ""}'
                        ' · ${WeekParser.toText(c.weeks, c.weekType)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        if (semester != null) {
                          ref.read(displayWeekProvider.notifier).setWeek(
                              _targetWeek(
                                  c, todayWeek, semester.totalWeeks));
                        }
                        Navigator.popUntil(context, (r) => r.isFirst);
                      },
                    );
                  },
                ),
    );
  }
}
