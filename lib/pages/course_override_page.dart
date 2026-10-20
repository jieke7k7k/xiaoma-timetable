import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/course_override.dart';
import '../utils/override_effect.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';

/// 单次调课页（阶段五·节假日调课）
///
/// 从周视图长按某节课 →「调整本次」进入。路由参数：
/// `{'courseId': int, 'week': int}`，week 即 originalWeek（当前浏览周次）。
///
/// 三种用法：
/// - 无已有调整：选择新星期/节次/教室，或勾选「本次停课」，保存后只影响这一次；
/// - 已有调整：回显当前调整内容，可修改后重新保存（等同覆盖）；
/// - 已有调整：点「撤销本次调整」删除记录，课程回到原规律。
///
/// 调整结果落库前做冲突检测：与其他课（含其他课的同周单次调整）时间重叠时
/// 弹中文确认框，用户可选择「仍要保存」或「返回修改」。
class CourseOverridePage extends ConsumerStatefulWidget {
  const CourseOverridePage({super.key});

  @override
  ConsumerState<CourseOverridePage> createState() =>
      _CourseOverridePageState();
}

class _CourseOverridePageState extends ConsumerState<CourseOverridePage> {
  bool _loading = true;
  bool _saving = false;

  /// 加载失败（课程被删/参数错误/读库异常）时给中文兜底，不闪退
  String? _loadError;

  Course? _course; // 要调整的课程
  CourseOverride? _existing; // 该课该周已有的调整记录（null 表示还没有）
  int _week = 1; // originalWeek：当前浏览周次

  // 表单状态
  bool _cancel = false; // 是否本次停课
  int _dayOfWeek = 1;
  int _startSection = 1;
  int _endSection = 2;
  final _classroomController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _classroomController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final args = ModalRoute.of(context)?.settings.arguments;
    var courseId = 0;
    if (args is Map) {
      courseId = args['courseId'] as int? ?? 0;
      _week = args['week'] as int? ?? 1;
    }
    try {
      final courses = await ref.read(coursesProvider.future);
      for (final c in courses) {
        if (c.id == courseId) {
          _course = c;
          break;
        }
      }
      if (_course == null) {
        _loadError = '没有找到这门课程，可能已被删除';
      } else {
        final overrides = await ref.read(courseOverridesProvider.future);
        _existing = overrideForCourse(overrides, courseId, _week);
        // 表单默认值：有调整记录时回显调整内容，否则用课程原时间
        _cancel = _existing?.isCancellation ?? false;
        _dayOfWeek =
            _existing?.targetDayOfWeek ?? _course!.dayOfWeek;
        _startSection =
            _existing?.targetStartSection ?? _course!.startSection;
        _endSection = _existing?.targetEndSection ?? _course!.endSection;
        // 教室输入框只放「新教室」：沿用原教室时留空（null 语义见 override_effect）
        _classroomController.text = _existing?.targetClassroom ?? '';
      }
    } catch (e) {
      _loadError = '加载课程信息失败：$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// 组装要落库的调课记录。
  /// 调整类型：星期/节次总是存完整值（没改就存原值），教室留空 = 沿用原教室；
  /// 停课类型：目标字段全空，targetWeek = cancelFlag。
  CourseOverride _buildOverride() {
    final room = _classroomController.text.trim();
    return CourseOverride(
      courseId: _course!.id!,
      originalWeek: _week,
      targetWeek: _cancel ? CourseOverride.cancelFlag : _week,
      targetDayOfWeek: _cancel ? null : _dayOfWeek,
      targetStartSection: _cancel ? null : _startSection,
      targetEndSection: _cancel ? null : _endSection,
      targetClassroom: (_cancel || room.isEmpty) ? null : room,
    );
  }

  Future<void> _save() async {
    final course = _course;
    if (course == null) return;
    if (!_cancel && _startSection > _endSection) {
      _showError('开始节次不能大于结束节次哦');
      return;
    }
    final override = _buildOverride();

    // 冲突检测（阶段五要求）：调课后的单次课与其他课重叠时给中文提示，
    // 由用户决定是否仍然保存（停课不会产生新占用，无需检测）
    if (!_cancel) {
      final conflicts = checkOverrideConflicts(
        course: course,
        override: override,
        allCourses: ref.read(coursesProvider).value ?? const [],
        allOverrides: ref.read(courseOverridesProvider).value ?? const [],
      );
      if (conflicts.isNotEmpty && mounted) {
        final proceed = await _confirmConflicts(conflicts);
        if (!proceed) return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref.read(courseOverridesProvider.notifier).saveOverride(override);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_cancel
            ? '第 $_week 周《${course.name}》已停课'
            : '第 $_week 周《${course.name}》已调整：${describeOverride(override)}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('保存失败：$e');
    }
  }

  /// 冲突确认框：列出冲突明细，返回 true 表示用户选择「仍要保存」
  Future<bool> _confirmConflicts(List<String> conflicts) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('检测到时间冲突'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('调整后的这节课与以下课程时间重叠：'),
            const SizedBox(height: 8),
            for (final c in conflicts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $c'),
              ),
            const SizedBox(height: 8),
            const Text('确定仍要这样调整吗？'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('返回修改')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('仍要保存')),
        ],
      ),
    );
    return result == true;
  }

  /// 撤销本次调整：删除 override 记录，课程回到原规律
  Future<void> _revert() async {
    final existing = _existing;
    final course = _course;
    if (existing?.id == null || course == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('撤销本次调整'),
        content: Text('撤销后《${course.name}》第 $_week 周将恢复原上课时间，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('撤销')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(courseOverridesProvider.notifier)
          .deleteOverride(existing!.id!);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已撤销调整，《${course.name}》恢复原时间')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('撤销失败：$e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null || _course == null) {
      // 加载失败兜底页：统一空状态样式（图标 + 中文说明 + 返回按钮），不闪退
      return Scaffold(
        appBar: AppBar(title: const Text('调整本次课程')),
        body: EmptyState(
          icon: Icons.event_busy_outlined,
          title: _loadError ?? '没有找到这门课程',
          message: '请返回课表后重试',
          actionLabel: '返回',
          onAction: () => Navigator.pop(context),
        ),
      );
    }

    final slots = ref.watch(timeSlotsProvider).value ?? [];
    final sectionCount = slots.isNotEmpty ? slots.length : 12;
    final course = _course!;
    final originalRoom = course.classroom?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? '调整本次课程' : '查看/修改本次调整'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 原课程信息卡
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '原时间：第 $_week 周 · 周${weekdayName(course.dayOfWeek)} · '
                    '${_sectionText(course.startSection, course.endSection)}'
                    '${originalRoom == null || originalRoom.isEmpty ? '' : ' · $originalRoom'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (_existing != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '当前调整：${describeOverride(_existing!)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 本次停课开关：开了就隐藏时间选择（停课记录不存目标时间）
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('本次停课'),
            subtitle: const Text('这一节不上课，也不再提醒；其他周不受影响'),
            value: _cancel,
            onChanged: (v) => setState(() => _cancel = v),
          ),
          if (!_cancel) ...[
            const SizedBox(height: 8),
            Text('调整到', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _dayOfWeek,
                    decoration: const InputDecoration(labelText: '星期'),
                    items: [
                      for (var d = 1; d <= 7; d++)
                        DropdownMenuItem(
                          value: d,
                          child: Text('周${weekdayName(d)}'),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => _dayOfWeek = v ?? _dayOfWeek),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _startSection,
                    decoration: const InputDecoration(labelText: '开始节次'),
                    items: [
                      for (var s = 1; s <= sectionCount; s++)
                        DropdownMenuItem(
                            value: s, child: Text('第 $s 节')),
                    ],
                    onChanged: (v) => setState(() {
                      _startSection = v ?? _startSection;
                      if (_endSection < _startSection) {
                        _endSection = _startSection;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _endSection,
                    decoration: const InputDecoration(labelText: '结束节次'),
                    items: [
                      for (var s = 1; s <= sectionCount; s++)
                        DropdownMenuItem(
                            value: s, child: Text('第 $s 节')),
                    ],
                    onChanged: (v) => setState(() {
                      _endSection = v ?? _endSection;
                      if (_startSection > _endSection) {
                        _startSection = _endSection;
                      }
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 教室：留空沿用原教室（不强制改）
            TextFormField(
              controller: _classroomController,
              decoration: InputDecoration(
                labelText: '新教室（可空）',
                hintText: originalRoom == null || originalRoom.isEmpty
                    ? '留空则不显示教室'
                    : '留空沿用原教室 $originalRoom',
                prefixIcon: const Icon(Icons.place_outlined),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_cancel ? '确认停课' : '保存调整'),
          ),
          // 已有调整时提供撤销入口，回到原规律
          if (_existing != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _saving ? null : _revert,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('撤销本次调整'),
            ),
          ],
        ],
      ),
    );
  }

  static String _sectionText(int start, int end) =>
      start == end ? '第 $start 节' : '第 $start-$end 节';
}
