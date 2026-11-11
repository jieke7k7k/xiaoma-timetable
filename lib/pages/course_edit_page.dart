import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/course.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/conflict_detector.dart';
import '../utils/morandi_palette.dart';
import '../utils/week_parser.dart';
import '../widgets/app_dialog.dart';
import '../widgets/week_picker.dart';

/// 课程新建/编辑页（阶段二完整版，WB_SPEC_231 第 10 节：多时段一起编辑）
///
/// 三种进入方式：
/// - 点击周视图空白格：arguments = {'dayOfWeek': x, 'startSection': y}（自动带入）
/// - 编辑已有课程：arguments = course.id
/// - 同名快捷录入：arguments = {'name': 课程名, 'teacher': 老师, 'colorValue': 颜色}
///
/// 一门课在库里是「同学期、同名」的多行，一行一个时段。编辑其中任意一行时：
/// - 页面列出它的其他时段（「其他时段」区），点一条原地切过去编辑；
/// - 保存时把 5 个共享字段（课程名/老师/教室/颜色/备注）一次同步到本课全部时段，
///   时间与周次只改当前这一条（详见 [_buildSiblingsToSync] 与 [CoursesNotifier]）。
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
  String? _examEndTime; // 考试结束时间 HH:mm（云同步 2.1.0，小马直连写入，编辑页透传不丢）
  String? _examPlace; // 考试地点（云同步 2.1.0，小马直连写入，编辑页透传不丢）
  int _semesterId = 0; // 编辑时记录原学期 id，避免更新时被清零
  int? _editId; // 编辑模式下的课程 id（来自路由参数或构造参数）
  bool _loading = true;
  bool _saving = false;

  // —— 多时段一起编辑（WB_SPEC_231 第 10 节）——
  /// 进页面时锁死的原课程名：查兄弟时段**永远**用它，绝不用改名后的输入框文本
  /// （否则把「药理学」改成「临床药理学」再保存，新名字查出 0 条兄弟，一门课被拆成两门）
  String _originalCourseName = '';

  /// 当前时段的库里原值：未保存改动的判定基准 + 教室/备注异构保护的比对基准
  Course? _initialCourse;

  /// 本课的其他时段（不含正在编辑的这条），按星期 + 开始节次排序
  List<Course> _siblings = const [];

  /// 正在切换时段（防连点）
  bool _switching = false;

  /// 只跑一次加载（[didChangeDependencies] 可能被多次调用）
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 读路由参数要用 ModalRoute.of(context)，它在 initState 里取会踩
    // 「initState 期间依赖 InheritedWidget」的断言；放到这里才是正确时机
    if (_loadStarted) return;
    _loadStarted = true;
    _load();
  }

  Future<void> _load() async {
    // 从路由参数读取：int 表示编辑指定课程，Map 表示新建并带入星期/节次
    final args = ModalRoute.of(context)?.settings.arguments;
    _editId = widget.courseId ?? (args is int ? args : null);
    if (_editId != null) {
      // 编辑：加载已有课程。
      // 安全查找（防御性）：课程可能刚被删除或属于别的学期，
      // firstWhere 找不到会抛 StateError 直接崩页，这里改为找不到就提示并退出。
      final courses = await ref.read(coursesProvider.future);
      Course? course;
      for (final c in courses) {
        if (c.id == _editId) {
          course = c;
          break;
        }
      }
      if (course == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('课程已不存在')));
          Navigator.pop(context);
        }
        return;
      }
      _applyCourseToForm(course);
      _initialCourse = course;
      _originalCourseName = course.name;
      await _reloadSiblings();
    } else if (args is Map) {
      // 新建：带入点击格子的星期与节次；
      // 同名快捷录入（详情页「新增本课其他时段」）时额外带入名称/老师/莫兰迪颜色
      _dayOfWeek = args['dayOfWeek'] as int? ?? 1;
      _startSection = args['startSection'] as int? ?? 1;
      // 长按高亮建课会带入结束节次（拖动选了多节）；没有时与起始节相同
      final presetEnd = args['endSection'] as int?;
      _endSection =
          (presetEnd != null && presetEnd > _startSection) ? presetEnd : _startSection;
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

  /// 把一条课程的全部字段灌进表单（首次加载、切换时段、放弃改动后重置都用它）
  void _applyCourseToForm(Course course) {
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
    _examEndTime = course.examEndTime;
    _examPlace = course.examPlace;
    _semesterId = course.semesterId;
  }

  /// 重新拉一份「其他时段」：同学期、同名（用锁死的 [_originalCourseName]）、
  /// 排除正在编辑的这条；按星期再按开始节次排序
  Future<void> _reloadSiblings() async {
    final all = ref.read(coursesProvider).value ?? const <Course>[];
    final list = <Course>[
      for (final c in all)
        if (c.name == _originalCourseName && c.id != null && c.id != _editId) c,
    ];
    list.sort((a, b) {
      final byDay = a.dayOfWeek.compareTo(b.dayOfWeek);
      return byDay != 0 ? byDay : a.startSection.compareTo(b.startSection);
    });
    if (!mounted) return;
    setState(() => _siblings = list);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _classroomController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// 当前表单相对「这条时段在库里的原值」有没有未保存改动
  ///
  /// 归一化口径（规格第 10.2 节）：字符串统一 trim、空串与 null 等价，
  /// weeks 用 listEquals。进页面没动任何东西时点切换**不该**弹框。
  bool get _isDirty {
    final b = _initialCourse;
    if (b == null) return false;
    String norm(String? v) => (v ?? '').trim();
    if (_nameController.text.trim() != norm(b.name)) return true;
    if (_teacherController.text.trim() != norm(b.teacher)) return true;
    if (_classroomController.text.trim() != norm(b.classroom)) return true;
    if (_noteController.text.trim() != norm(b.note)) return true;
    if (_colorValue != b.colorValue) return true;
    if (_dayOfWeek != b.dayOfWeek) return true;
    if (_startSection != b.startSection) return true;
    if (_endSection != b.endSection) return true;
    if (_weekType != b.weekType) return true;
    if (!listEquals(_weeks, b.weeks)) return true;
    return false;
  }

  /// 当前学期里是否已经存在另一门叫 [name] 的课（不含本课现有全部时段）
  bool _hasOtherCourseNamed(String name) {
    final all = ref.read(coursesProvider).value ?? const <Course>[];
    final ownIds = <int?>{_editId, for (final s in _siblings) s.id};
    for (final c in all) {
      if (c.name != name) continue;
      if (ownIds.contains(c.id)) continue;
      return true;
    }
    return false;
  }

  /// 保存。返回 true 表示真正写库成功（切换时段前要用它决定是否继续切）。
  Future<bool> _save({bool popOnSuccess = true}) async {
    if (!_formKey.currentState!.validate()) return false;
    if (_startSection > _endSection) {
      _showError('开始节次不能大于结束节次哦');
      return false;
    }
    if (_weeks.isEmpty) {
      _showError('至少选择一周上课哦');
      return false;
    }
    final newName = _nameController.text.trim();
    // 改名撞车：保存前先确认要不要把两门课合并管理（规格第 10.1 节）
    if (_editId != null &&
        newName != _originalCourseName &&
        _hasOtherCourseNamed(newName)) {
      if (!mounted) return false;
      final go = await showAppConfirmDialog(
        context,
        title: '合并同名课程？',
        message: '当前学期已存在同名课程「$newName」，保存后它们的时段将合并管理'
            '并同步共享属性，是否继续？',
        confirmLabel: '继续',
        cancelLabel: '取消',
      );
      if (go != true) return false;
      if (!mounted) return false;
    }
    final course = Course(
      id: _editId,
      // 新建时占位，addCourse 会替换为当前学期 id；编辑时保留原学期
      semesterId: _semesterId,
      name: newName,
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
      // 考试结束时间/地点：编辑页不直接改这两个字段（小马直连写入），
      // 重建课程时原样透传原值，避免「编辑课程」把云端已写入的考试信息清空
      examEndTime: _examEndTime,
      examPlace: _examPlace,
    );

    // 保存前先做时间冲突预检：只算**当前这一个时段**（规格第 10.4 节）——
    // 兄弟时段本次只改文本/颜色字段、不动时间，对它们重算会拦住「改个备注都不让存」。
    // 冲突池仍取同学期课程，排除自身但包含本课其他时段（防止把当前时段改到与
    // 兄弟时段完全重叠）。语义与导入链路一致（同星期 + 周次有交集 + 节次重叠）。
    final conflicts = _findConflicts(course);
    if (conflicts.isNotEmpty) {
      final keepSaving = await _showConflictDialog(conflicts);
      if (keepSaving != true) return false;
      if (!mounted) return false;
    }

    setState(() => _saving = true);
    try {
      if (_editId == null) {
        await ref.read(coursesProvider.notifier).addCourse(course);
        if (mounted && popOnSuccess) {
          // 先取 messenger 再 pop：pop 之后 context 已失效，不能再往上找祖先
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(const SnackBar(content: Text('课程添加成功')));
        }
        return true;
      }
      final siblings = _buildSiblingsToSync(course);
      // 一次事务写多行：当前时段整行 + 每个兄弟时段只覆盖 5 个共享字段
      await ref
          .read(coursesProvider.notifier)
          .updateCourseWithSiblings(course, siblings);
      // 保存成功后把「原课程名」更新为保存后的名字，后续切换/再保存都以它为准
      _originalCourseName = course.name;
      final total = siblings.length + 1;
      if (mounted && popOnSuccess) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(total > 1 ? '已同步到本课共 $total 个时段' : '课程已更新'),
          ),
        );
      }
      return true;
    } catch (e) {
      // 写库失败整批回滚（事务保证），兄弟时段保持原值；原始异常只进日志
      debugPrint('保存课程失败：$e');
      if (mounted) _showError('保存失败，请重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 把 5 个共享字段（课程名/老师/教室/颜色/备注）铺到每个兄弟时段上。
  ///
  /// 关键点（规格第 10.3 节）：
  /// - 兄弟行以**库里的原对象**为底，只覆盖共享字段——时间/周次/考试日期原样保留；
  /// - 教室/备注异构保护：用户本次没亲手改教室（或备注）时，兄弟时段里本来就
  ///   不同的那个值保留不动（周二理论课 302、周四实验课 105 不会被一起改成 302）。
  List<Course> _buildSiblingsToSync(Course updated) {
    final base = _initialCourse;
    if (base == null || _siblings.isEmpty) return const [];
    String norm(String? v) => (v ?? '').trim();
    final classroomTouched =
        _classroomController.text.trim() != norm(base.classroom);
    final noteTouched = _noteController.text.trim() != norm(base.note);
    return [
      for (final s in _siblings)
        Course(
          id: s.id,
          semesterId: s.semesterId,
          name: updated.name,
          teacher: updated.teacher,
          colorValue: updated.colorValue,
          dayOfWeek: s.dayOfWeek,
          startSection: s.startSection,
          endSection: s.endSection,
          weeks: s.weeks,
          weekType: s.weekType,
          // 教室：本次亲手改过 → 跟着变；没碰过且兄弟时段自己另有一个非空教室 → 保留
          classroom: _keepOwnValue(
            touched: classroomTouched,
            own: s.classroom,
            baseValue: base.classroom,
            incoming: updated.classroom,
          ),
          note: _keepOwnValue(
            touched: noteTouched,
            own: s.note,
            baseValue: base.note,
            incoming: updated.note,
          ),
          examDate: s.examDate,
          examEndTime: s.examEndTime,
          examPlace: s.examPlace,
        ),
    ];
  }

  /// 异构保护判定：没被用户本次改动过、且兄弟时段自己的值与基准不同且非空 → 保留自己的
  String? _keepOwnValue({
    required bool touched,
    required String? own,
    required String? baseValue,
    required String? incoming,
  }) {
    String norm(String? v) => (v ?? '').trim();
    if (!touched && norm(own).isNotEmpty && norm(own) != norm(baseValue)) {
      return own;
    }
    return incoming;
  }

  /// 切到同课的另一条时段（同一页换 courseId，不新开路由）
  Future<void> _switchTo(Course target) async {
    if (_switching || _saving) return;
    if (_editId == null || target.id == null) return;
    if (_isDirty) {
      final choice = await _askUnsavedChoice();
      if (choice == null) return; // 取消：留在当前时段
      if (choice == 'save') {
        // 保存必须整条流程走完（校验 → 冲突 → 事务）才允许切换
        final ok = await _save(popOnSuccess: false);
        if (!ok) return;
      }
    }
    if (!mounted) return;
    // 切前先收软键盘，避免切换后键盘浮在别的字段上
    FocusScope.of(context).unfocus();
    setState(() => _switching = true);
    final all = ref.read(coursesProvider).value ?? const <Course>[];
    Course? fresh;
    for (final c in all) {
      if (c.id == target.id) {
        fresh = c;
        break;
      }
    }
    if (fresh == null) {
      setState(() => _switching = false);
      _showError('这个时段已不存在');
      return;
    }
    setState(() {
      _editId = fresh!.id;
      _initialCourse = fresh;
      _originalCourseName = fresh.name;
      _applyCourseToForm(fresh);
      _switching = false;
    });
    await _reloadSiblings();
  }

  /// 三选确认框（左一右二：最左「取消」，右侧「放弃」红字 + 「保存」实心）
  Future<String?> _askUnsavedChoice() {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AppDialog(
          title: '当前时段有未保存的改动',
          content: const AppDialogText('切换到这个时段前，要先保存这些改动吗？'),
          actions: [
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'discard'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: const Text('放弃'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 候选课程与同学期已有课程的时间冲突列表（编辑时排除自身）
  ///
  /// 冲突池取 `coursesProvider`（恒为当前学期的课程）：新建的课程由
  /// `addCourse` 盖上学期的 id，编辑的课程本就来自这份列表，两边都对得上。
  List<CourseConflict> _findConflicts(Course candidate) {
    final existing = ref.read(coursesProvider).value ?? const <Course>[];
    return ConflictDetector.detect(
      candidate,
      existing,
      ignoreCourseId: _editId,
    );
  }

  /// 冲突确认框：列出冲突课程名与时间，返回 true 表示用户仍要保存
  ///
  /// WB_SPEC_230 第 4.2 节第 4 类：直接嵌 [AppDialog]，原本的
  /// SingleChildScrollView 原样传入 content（不拆）。
  Future<bool?> _showConflictDialog(List<CourseConflict> conflicts) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '检测到时间冲突',
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('这门课与已有课程有 ${conflicts.length} 处冲突：'),
              const SizedBox(height: AppSpacing.s),
              for (final c in conflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '· ${c.describe()}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍要保存'),
          ),
        ],
      ),
    );
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

  /// 一条「其他时段」的展示文案：周X 第 a-b 节 · 1-16 周（格式与详情/搜索页一致）
  String _slotText(Course c) {
    final weeks = WeekParser.toText(c.weeks, c.weekType);
    return '周${'一二三四五六日'[c.dayOfWeek - 1]} '
        '第${c.startSection}-${c.endSection}节'
        '${weeks.isEmpty ? '' : ' · $weeks 周'}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    final sectionCount = slots.isNotEmpty ? slots.length : 12;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editId == null ? '新建课程' : '编辑课程'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(),
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
                    // DropdownButtonFormField 只在首帧读 initialValue，切换时段后
                    // 靠 ValueKey 重建来跟上新值（表单其余字段靠控制器刷新）
                    key: ValueKey('day-$_editId-$_dayOfWeek'),
                    onChanged: (v) =>
                        setState(() => _dayOfWeek = v ?? _dayOfWeek),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _startSection,
                    key: ValueKey('start-$_editId-$_startSection'),
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
                    key: ValueKey('end-$_editId-$_endSection'),
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
            // 其他时段（WB_SPEC_231 第 10.2 节）：放在「星期与节次」与「课程颜色」之间。
            // 只有 1 个时段的课不显示该区，页面与改前一致。
            if (_siblings.isNotEmpty) ...[
              // 上间距 14：上方星期/节次框的浮动标签会向上凸出约 7dp，别压住它
              const SizedBox(height: 14),
              Text('其他时段（同一门课）',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              for (final s in _siblings)
                InkWell(
                  onTap: _switching ? null : () => _switchTo(s),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.schedule_outlined,
                            size: 18, color: scheme.outline),
                        const SizedBox(width: AppSpacing.s),
                        Expanded(
                          child: Text(
                            _slotText(s),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          '去编辑',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.primary,
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: scheme.outline),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              Text(
                '改课程名、老师、教室、颜色、备注会同步到本课全部时段；'
                '时间与周次只改这一条。',
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
              // 下间距 18：保证与下方输入框（浮动标签会向上凸出）之间留足空
              const SizedBox(height: 18),
            ] else
              const SizedBox(height: 20),
            // 课程颜色：显示当前配色方案的颜色，选中后仍存「莫兰迪色位」的
            // 标准值（见 color_schemes.dart 的映射原理），以后切方案能整表换色
            Text(
                '课程颜色（${(ref.watch(uiSettingsProvider).value ?? const UiSettings()).colorScheme.name}）',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              children: [
                for (var i = 0; i < MorandiPalette.colors.length; i++)
                  _ColorDot(
                    color: (ref.watch(uiSettingsProvider).value ??
                            const UiSettings())
                        .colorScheme
                        .colors[i],
                    selected: MorandiPalette.colors[i] == _colorValue,
                    onTap: () =>
                        setState(() => _colorValue = MorandiPalette.colors[i]),
                  ),
                // 课程存了非色板色（历史自定义色）时，把它也列出来保持可选
                if (!MorandiPalette.colors.contains(_colorValue))
                  _ColorDot(
                    color: _colorValue,
                    selected: true,
                    onTap: () {},
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // 周次选择器
            Text('上课周次', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            WeekPicker(
              // 切换时段要重置内部选中态：按 courseId 换 key 让组件整体重建
              key: ValueKey('week-picker-$_editId'),
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
              onPressed: _saving ? null : () => _save(),
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
