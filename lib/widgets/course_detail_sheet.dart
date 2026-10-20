import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/course.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/exam_countdown.dart';
import '../utils/week_parser.dart';

/// 课程详情底部弹窗：完整展示课程信息，提供编辑/删除入口
class CourseDetailSheet extends ConsumerWidget {
  const CourseDetailSheet({super.key, required this.course});

  final Course course;

  /// 展示课程详情 BottomSheet
  static Future<void> show(BuildContext context, Course course) {
    return showModalBottomSheet(
      context: context,
      // 弹层圆角统一走全局常量（与 main.dart 的 bottomSheetTheme 一致）
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
      ),
      builder: (_) => CourseDetailSheet(course: course),
    );
  }

  static String _weekdayText(int d) {
    const names = ['', '一', '二', '三', '四', '五', '六', '日'];
    return names[d];
  }

  /// 考试日期展示文本：「yyyy年M月d日（还有 X 天 / 今天考试 / 已结束）」
  static String _examText(int millis) {
    final examDate = DateTime.fromMillisecondsSinceEpoch(millis);
    final days = ExamCountdown.daysUntil(examDate, DateTime.now());
    return '${DateFormat('yyyy年M月d日').format(examDate)}'
        '（${ExamCountdown.countdownText(days)}）';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  // 弹层顶部拖动条是微小装饰元素，2px 微圆角不归入 AppRadii
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(course.colorValue),
                    // 12px 考试色点近似正圆的微圆角，属微小装饰元素，不归入 AppRadii
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    course.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.schedule_outlined,
              label: '时间',
              value: '周${_weekdayText(course.dayOfWeek)} 第${course.startSection}'
                  '${course.endSection > course.startSection ? "-${course.endSection}" : ""}节',
            ),
            _InfoRow(
              icon: Icons.date_range_outlined,
              label: '周次',
              value: course.weeks.isEmpty
                  ? '未设置'
                  : WeekParser.toText(course.weeks, course.weekType),
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: '老师',
              value: (course.teacher == null || course.teacher!.isEmpty)
                  ? '未填写'
                  : course.teacher!,
            ),
            _InfoRow(
              icon: Icons.place_outlined,
              label: '教室',
              value: (course.classroom == null || course.classroom!.isEmpty)
                  ? '未填写'
                  : course.classroom!,
            ),
            // 考试日期（阶段五·倒计时）：设置了才显示，附当天倒计时文案
            if (course.examDate != null)
              _InfoRow(
                icon: Icons.event_note_outlined,
                label: '考试',
                value: _examText(course.examDate!),
              ),
            _InfoRow(
              icon: Icons.edit_note_outlined,
              label: '备注',
              value: (course.note == null || course.note!.isEmpty)
                  ? '无'
                  : course.note!,
            ),
            const SizedBox(height: 16),
            // 同名课程快捷录入：一周多节 / 实验课不用重复填名称老师颜色
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // 先关弹窗
                  Navigator.pushNamed(context, '/course-edit', arguments: {
                    'name': course.name,
                    'teacher': course.teacher,
                    'colorValue': course.colorValue,
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('新增本课其他时段'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // 先关弹窗
                    Navigator.pushNamed(context, '/course-edit',
                        arguments: course.id);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _confirmDelete(context, ref),
                  icon: const Icon(Icons.delete_outline),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除《${course.name}》吗？删除后不可恢复哦。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(coursesProvider.notifier).deleteCourse(course.id!);
      if (context.mounted) {
        Navigator.pop(context); // 关闭 BottomSheet
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除《${course.name}》')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
