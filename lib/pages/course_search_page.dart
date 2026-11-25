import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../providers/providers.dart';
import '../utils/app_haptics.dart';
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
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
    // WB_SPEC_235 跟进：顺手修掉一个既有崩溃——级联 `..sort()` 的优先级比
    // 条件表达式高，原写法等价于 `(q.isEmpty ? const <Course>[] : ...)..sort()`，
    // 空查询时那是个 **const 列表**，sort 直接抛
    // UnsupportedError(Cannot modify an unmodifiable list)，页面首帧就红屏。
    // 加一层括号把级联圈在 else 分支里，语义不变（空查询结果仍为空表）。
    final results = q.isEmpty
        ? const <Course>[]
        : (courses
                .where((c) =>
                    c.name.toLowerCase().contains(q) ||
                    (c.teacher?.toLowerCase().contains(q) ?? false) ||
                    (c.classroom?.toLowerCase().contains(q) ?? false))
                .toList()
              ..sort((a, b) => a.dayOfWeek != b.dayOfWeek
                  ? a.dayOfWeek.compareTo(b.dayOfWeek)
                  : a.startSection.compareTo(b.startSection)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('课程搜索'),
      ),
      body: Column(
        children: [
          // WB_SPEC_261 §8：搜索框从 AppBar.title 移到 body 顶部，与选校器同款
          // 写法（prefixIcon + suffixIcon 清空 + isDense，边框与内边距全走主题，
          // 不再手写 border / filled / contentPadding）。旧写法的问题：只写了
          // border: InputBorder.none，没写 enabledBorder / focusedBorder，
          // InputDecorator 用主题补了 focusedBorder（CleanGap 主色 1.5dp），
          // autofocus 让它进页面就常驻聚焦态，于是出现棕色粗边框；主题
          // contentPadding 上下 28dp 又把框顶满 AppBar，提示文字贴边像被裁。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索课名、老师或教室',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: '清空',
                        // WB_SPEC_235 §7：清空输入 = 轻点档
                        onPressed: () {
                          AppHaptics.tap();
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: q.isEmpty
          ? const EmptyState(
              icon: Icons.search_outlined,
              title: '搜索当前学期的课程',
              message: '输入课名、老师或教室，如「药理」「教3-201」',
            )
          : results.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_outlined,
                  title: '没有找到「$_query」',
                  message: '请更换关键词，或确认课程属于当前学期',
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
                      // WB_SPEC_235 跟进 §1-10：搜索结果项 = 轻点档
                      // （与同页 77 行「清空」一致）
                      onTap: () {
                        AppHaptics.tap();
                        if (semester != null) {
                          ref.read(displayWeekProvider.notifier).setWeek(
                              _targetWeek(
                                  c, todayWeek, semester.totalWeeks));
                        }
                        Navigator.popUntil(context, (r) => r.isFirst);
                      },
                      enableFeedback: false,
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
