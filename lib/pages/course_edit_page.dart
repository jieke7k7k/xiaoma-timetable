import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/morandi_palette.dart';
import '../utils/week_parser.dart';
import '../widgets/week_picker.dart';

/// 课程新建/编辑页（阶段二完整版）
///
/// 三种进入方式：
/// - 点击周视图空白格：arguments = {'dayOfWeek': x, 'startSection': y}（自动带入）
/// - 编辑已有课程：arguments = course.id
/// - 同名快捷录入：arguments = {'name': 课程名, 'teacher': 老师, 'colorValue': 颜色}
class CourseEditPage extends ConsumerStatefulWidget {
  const CourseEditPage({super.key, this.courseId});

  /// 非空表示编辑该课程；空表示新建
  final int? courseId;

  @override
  ConsumerState<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends ConsumerState<CourseEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _teacherController = TextEditingController();
  final _classroomController = TextEditingController();
  final _noteController = TextEditingController();

  int _dayOfWeek = 1;
  int _startSection = 1;
  int _endSection = 2;
  int _colorValue = MorandiPalette.defaultColor;
  List<int> _weeks = [];
  int _weekType = WeekParser.allWeeks;
  int? _examDate; // 考试日期毫秒时间戳，null 表示未设置（阶段五·倒计时）
  int _semesterId = 0; // 编辑时记录原学期 id，避免更新时被清零
  int? _editId; // 编辑模式下的课程 id（来自路由参数或构造参数）
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 从路由参数读取：int 表示编辑指定课程，Map 表示新建并带入星期/节次
    final args = ModalRoute.of(context)?.settings.arguments;
    _editId = widget.courseId ?? (args is int ? args : null);
    if (_editId != null) {
      // 编辑：加载已有课程
      final courses = await ref.read(coursesProvider.future);
      final course = courses.firstWhere((c) => c.id == _editId);
      _nameController.text = course.name;
      _teacherController.text = course.teacher ?? '';
      _classroomController.text = course.classroom ?? '';
      _noteController.text = course.note ?? '';
      _dayOfWeek = course.dayOfWeek;
      _startSection = course.startSection;
      _endSection = course.endSection;
      _colorValue = course.colorValue;
      _weeks = course.weeks;
      _weekType = course.weekType;
      _examDate = course.examDate;
      _semesterId = course.semesterId;
    } else if (args is Map) {
      // 新建：带入点击格子的星期与节次；
      // 同名快捷录入（详情页「新增本课其他时段」）时额外带入名称/老师/莫兰迪颜色
      _dayOfWeek = args['dayOfWeek'] as int? ?? 1;
      _startSection = args['startSection'] as int? ?? 1;
      _endSection = _startSection;
      final presetName = args['name'] as String?;
      if (presetName != null && presetName.isNotEmpty) {
        _nameController.text = presetName;
      }
      final presetTeacher = args['teacher'] as String?;
      if (presetTeacher != null && presetTeacher.isNotEmpty) {
        _teacherController.text = presetTeacher;
      }
      final presetColor = args['colorValue'] as int?;
      if (presetColor != null && MorandiPalette.colors.contains(presetColor)) {
        _colorValue = presetColor;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _classroomController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startSection > _endSection) {
      _showError('开始节次不能大于结束节次哦');
      return;
    }
    if (_weeks.isEmpty) {
      _showError('至少选择一周上课哦');
      return;
    }
    setState(() => _saving = true);
    try {
      final course = Course(
        id: _editId,
        // 新建时占位，addCourse 会替换为当前学期 id；编辑时保留原学期
        semesterId: _semesterId,
        name: _nameController.text.trim(),
        teacher: _teacherController.text.trim().isEmpty
            ? null
            : _teacherController.text.trim(),
        classroom: _classroomController.text.trim().isEmpty
            ? null
            : _classroomController.text.trim(),
        colorValue: _colorValue,
        dayOfWeek: _dayOfWeek,
        startSection: _startSection,
        endSection: _endSection,
        weeks: _weeks,
        weekType: _weekType,
        note:
            _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        // 考试日期：null 即未设置/已清除，updateCourse 直接整对象落库可正常清空
        examDate: _examDate,
      );
      if (_editId == null) {
        await ref.read(coursesProvider.notifier).addCourse(course);
      } else {
        await ref.read(coursesProvider.notifier).updateCourse(course);
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_editId == null ? '课程添加成功' : '课程已更新')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError('保存失败：$e');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 毫秒时间戳 → 「yyyy年M月d日」展示文本（数字占位符不依赖 intl locale 数据）
  String _examDateText(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year}年${d.month}月${d.day}日';
  }

  /// 选择考试日期（可反复改，也可通过右侧按钮清除）
  Future<void> _pickExamDate() async {
    final initial = _examDate != null
        ? DateTime.fromMillisecondsSinceEpoch(_examDate!)
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择考试日期',
    );
    // 用户取消（返回 null）不动现有值
    if (picked != null) {
      setState(() => _examDate = picked.millisecondsSinceEpoch);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    final sectionCount = slots.isNotEmpty ? slots.length : 12;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editId == null ? '新建课程' : '编辑课程'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 课程名（必填）
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '课程名 *',
                hintText: '如 药物分析',
                prefixIcon: Icon(Icons.book_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '课程名不能为空' : null,
            ),
            const SizedBox(height: 12),
            // 老师
            TextFormField(
              controller: _teacherController,
              decoration: const InputDecoration(
                labelText: '老师（可空）',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            // 教室
            TextFormField(
              controller: _classroomController,
              decoration: const InputDecoration(
                labelText: '教室（可空）',
                hintText: '如 16-222',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 16),
            // 星期与节次
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
                          child: Text('周${'一二三四五六日'[d - 1]}'),
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
                        DropdownMenuItem(value: s, child: Text('第 $s 节')),
                    ],
                    onChanged: (v) => setState(() {
                      _startSection = v ?? _startSection;
                      if (_endSection < _startSection) _endSection = _startSection;
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
                        DropdownMenuItem(value: s, child: Text('第 $s 节')),
                    ],
                    onChanged: (v) => setState(() {
                      _endSection = v ?? _endSection;
                      if (_startSection > _endSection) _startSection = _endSection;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 莫兰迪色板
            Text('课程颜色（莫兰迪色系）',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                for (final c in MorandiPalette.colors)
                  _ColorDot(
                    color: c,
                    selected: c == _colorValue,
                    onTap: () => setState(() => _colorValue = c),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // 周次选择器
            Text('上课周次', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            WeekPicker(
              initialWeeks: _weeks,
              initialWeekType: _weekType,
              onChanged: (weeks, weekType) {
                _weeks = weeks;
                _weekType = weekType;
              },
            ),
            const SizedBox(height: 16),
            // 备注
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: '备注（可空）',
                prefixIcon: Icon(Icons.edit_note_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            // 考试日期（阶段五·倒计时）：设置后在「考试倒计时」页按时间排序展示
            Text('考试日期', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_note_outlined),
              title: Text(_examDate == null
                  ? '未设置'
                  : _examDateText(_examDate!)),
              subtitle:
                  _examDate == null ? const Text('设置后可在考试倒计时页查看') : null,
              trailing: _examDate == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      icon: const Icon(Icons.close_outlined),
                      tooltip: '清除考试日期',
                      onPressed: () => setState(() => _examDate = null),
                    ),
              onTap: _pickExamDate,
            ),
            const SizedBox(height: 24),
            // 保存按钮（底部大按钮）
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(_editId == null ? '添加课程' : '保存修改'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 色板小圆点
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 深色模式下色板圆点直接展示降饱和后的实际卡片效果（所见即所得），
    // 勾选图标随之换浅色才看得清
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dotColor = isDark
        ? MorandiPalette.desaturateForDark(Color(color))
        : Color(color);
    final checkColor = isDark
        ? const Color(MorandiPalette.darkTextColor)
        : const Color(MorandiPalette.textColor);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: dotColor,
          // 色板圆点是正圆（半径=宽高一半），不属于 AppRadii 圆角体系
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected ? Icon(Icons.check, size: 18, color: checkColor) : null,
      ),
    );
  }
}
