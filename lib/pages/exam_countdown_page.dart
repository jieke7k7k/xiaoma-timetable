import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/course.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/exam_countdown.dart';
import '../utils/morandi_palette.dart';
import '../widgets/empty_state.dart';

/// 星期几的中文简称（weekday 1=周一 … 7=周日）
String _weekdayText(int d) {
  const names = ['', '一', '二', '三', '四', '五', '六', '日'];
  return names[d];
}

/// 考试倒计时页（阶段五）
///
/// 读取当前学期全部课程，筛出设置了「考试日期」的课程，
/// 按考试日期升序排列，逐行显示课程名、日期与倒计时天数。
/// 天数计算全部走 [ExamCountdown] 纯函数（含单元测试）。
class ExamCountdownPage extends ConsumerWidget {
  const ExamCountdownPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('考试倒计时'), centerTitle: true),
      body: coursesAsync.when(
        data: (courses) {
          final now = DateTime.now();
          // 只保留设置了考试日期的课程，按考试日期升序（越近的越靠前）
          final exams = courses
              .where((c) => c.examDate != null)
              .toList()
            ..sort((a, b) => a.examDate!.compareTo(b.examDate!));
          if (exams.isEmpty) {
            // 统一空状态占位（阶段五·视觉打磨）
            return const EmptyState(
              icon: Icons.event_note_outlined,
              title: '还没有设置考试日期',
              message: '编辑课程时打开「考试日期」即可在这里看到倒计时',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.l),
            itemCount: exams.length,
            itemBuilder: (context, i) =>
                _ExamCard(course: exams[i], now: now),
          );
        },
        // 数据库异常等兜底：图标 + 中文提示 + 重试，不闪退不白屏
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '加载失败',
          message: '$e',
          actionLabel: '重试',
          onAction: () => ref.read(coursesProvider.notifier).reload(),
        ),
      ),
    );
  }
}

/// 单条考试倒计时卡片
class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.course, required this.now});

  final Course course;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 课程色点与周视图保持同源；深色下降饱和，避免亮色块刺眼（同 course_card 逻辑）
    final dotColor = isDark
        ? MorandiPalette.desaturateForDark(Color(course.colorValue))
        : Color(course.colorValue);

    final examDate =
        DateTime.fromMillisecondsSinceEpoch(course.examDate!);
    final days = ExamCountdown.daysUntil(examDate, now);

    // 倒计时配色：临近用主题色强调，当天用错误色（红）警示，已结束置灰
    final Color countdownColor;
    if (days == 0) {
      countdownColor = Theme.of(context).colorScheme.error;
    } else if (days > 0) {
      countdownColor = Theme.of(context).colorScheme.primary;
    } else {
      countdownColor = Theme.of(context).colorScheme.outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                // 12px 考试色点近似正圆的微圆角，属微小装饰元素，不归入 AppRadii
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('yyyy年M月d日').format(examDate)}'
                    ' · 周${_weekdayText(examDate.weekday)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
            Text(
              ExamCountdown.countdownText(days),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: countdownColor, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
