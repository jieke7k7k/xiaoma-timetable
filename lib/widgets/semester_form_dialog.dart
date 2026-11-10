import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/semester.dart';
import '../providers/providers.dart';
import '../utils/week_calc.dart';
import 'app_dialog.dart';
import 'semester_start_dialog.dart';

/// 开学日期日历的可选区间（与 [SemesterFormDialog] 里的日期选择器同一份口径）。
final DateTime kSemesterFirstDate = DateTime(2020, 1, 1);
final DateTime kSemesterLastDate = DateTime(2035, 12, 31);

/// 把日期夹进开学日期的可选区间（复审 Bug 2/4：回落值与编辑回填的脏数据都可能越界）。
DateTime _clampSemesterDate(DateTime date) {
  if (date.isBefore(kSemesterFirstDate)) return kSemesterFirstDate;
  if (date.isAfter(kSemesterLastDate)) return kSemesterLastDate;
  return date;
}

/// 弹出学期表单；确认返回填好的学期，取消返回 null。
/// 学期管理页、导入页（选目标学期时当场新建）与主页 ＋ 菜单（WB_SPEC_224）共用。
///
/// 传 [initial] 即进入编辑模式：回填该学期的名称 / 开学日期 / 总周数，
/// 返回时保留原 id 与 isCurrent；不传就是原来的新建模式（返回无 id 的学期）。
Future<Semester?> showSemesterFormDialog(
  BuildContext context, {
  Semester? initial,
}) {
  return showDialog<Semester>(
    context: context,
    builder: (ctx) => SemesterFormDialog(initial: initial),
  );
}

/// 学期表单校验（新建与编辑共用同一套，不要另写一份）。
///
/// 通过返回 null，否则返回中文提示文案，调用方直接拿去弹 SnackBar。
/// 抽成纯函数是为了可单测（页面里的对话框不好测）。
String? validateSemesterForm({
  required String name,
  required String weeks,
}) {
  if (name.trim().isEmpty) return '请填写学期名称';
  final v = int.tryParse(weeks.trim());
  if (v == null || v < 1 || v > 30) return '请输入 1~30 之间的周数';
  return null;
}

/// 新建学期时总周数的默认值（WB_SPEC_224 第 3.2 节）
///
/// 跟随当前课表的总周数（换学期多半沿用同一套周数习惯），读不到或脏数据才回落 20。
/// 有效区间与 [validateSemesterForm] 一致（1~30），越界一律当「读不到」。
int defaultWeeksForNewSemester(int? currentTotalWeeks) {
  final w = currentTotalWeeks;
  if (w == null || w < 1 || w > 30) return 20;
  return w;
}

/// 推测下学期开学月（WB_SPEC_224 第 3.3 节 / 第 8 节第 4 条）：只到月份，不猜具体哪天。
///
/// - 有当前学期开学日：1–6 月算春季 → 当年 9 月 1 日；7–12 月算秋季 → 次年 3 月 1 日。
/// - 没有当前学期（读不到）：按今天推——1 月 → 当年 3 月 1 日；2–7 月 → 当年 9 月 1 日；
///   8–12 月 → 次年 3 月 1 日。
///
/// 返回值只用于把日历翻到那一页（[showDatePicker] 的 initialDate），
/// **绝不写入表单的开学日期**（`_startDate` 保持 null，直到用户自己点了一天）。
/// 推测结果超出生效区间（[kSemesterFirstDate]~[kSemesterLastDate]）时回落到
/// 区间内最近的一天（先回今天、再夹到区间里——今天本身也可能越界）。
DateTime guessNextSemesterStartMonth(DateTime? currentStart, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final int year;
  final int month;
  if (currentStart != null) {
    if (currentStart.month <= 6) {
      year = currentStart.year;
      month = 9;
    } else {
      year = currentStart.year + 1;
      month = 3;
    }
  } else if (today.month == 1) {
    year = today.year;
    month = 3;
  } else if (today.month <= 7) {
    year = today.year;
    month = 9;
  } else {
    year = today.year + 1;
    month = 3;
  }
  final guess = DateTime(year, month, 1);
  if (guess.isBefore(kSemesterFirstDate) || guess.isAfter(kSemesterLastDate)) {
    return _clampSemesterDate(DateTime(today.year, today.month, today.day));
  }
  return guess;
}

/// 学期表单对话框（新建 / 编辑共用）
class SemesterFormDialog extends ConsumerStatefulWidget {
  const SemesterFormDialog({this.initial});

  /// 非 null 即编辑模式：回填该学期并在返回时保留 id / isCurrent
  final Semester? initial;

  @override
  ConsumerState<SemesterFormDialog> createState() =>
      SemesterFormDialogState();
}

class SemesterFormDialogState extends ConsumerState<SemesterFormDialog> {
  final _nameController = TextEditingController();
  // 初始值只是占位：initState 里编辑/新建两个分支都会立即覆盖（复审优化 2）
  final _weeksController = TextEditingController();
  DateTime? _startDate;

  /// 新建时日历的定位日（推测月份的 1 号，WB_SPEC_224 第 3.3 节）。
  ///
  /// 只用来决定日历打开时停在哪个月，**不是已选日期**：`_startDate` 仍为 null，
  /// 直到用户自己点了一天。编辑模式不使用它（日历停在原日期所在月）。
  DateTime? _suggestedStart;

  /// 编辑中的原学期（新建为 null）
  Semester? get _initial => widget.initial;

  @override
  void initState() {
    super.initState();
    final initial = _initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _weeksController.text = '${initial.totalWeeks}';
      // 库里的开学日期恒为周一；脏数据（未对齐）也在回填时就归一化
      _startDate = WeekCalc.alignToMonday(initial.startDateParsed);
    } else {
      // 新建（WB_SPEC_224）：总周数跟当前课表走，读不到才回落 20；
      // 日历定位到推测月份，但表单里不预填任何日期。
      // 本表单是学期管理页 / 导入页 / 主页 ＋ 菜单三处共用，新建默认值同步生效（有意为之）。
      // currentSemesterProvider 可能是 AsyncError（没有当前学期）：用 valueOrNull，
      // 别用 .value——后者在 AsyncError 下会直接抛出
      final current = ref.read(currentSemesterProvider).valueOrNull;
      _weeksController.text =
          '${defaultWeeksForNewSemester(current?.totalWeeks)}';
      _suggestedStart = guessNextSemesterStartMonth(current?.startDateParsed);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weeksController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      // 已选过就停在已选日期那月；没选过则停在推测月份那页（新建）；
      // 都没有才退回今天——推测月只是翻页定位，不写入 _startDate。
      // initialDate 越界会触发 showDatePicker 断言：统一夹一次（复审 Bug 2/4，
      // 编辑回填的脏数据也一样，基线同款边界问题顺带兜住）。
      initialDate:
          _clampSemesterDate(_startDate ?? _suggestedStart ?? DateTime.now()),
      firstDate: kSemesterFirstDate,
      lastDate: kSemesterLastDate,
      helpText: '选择开学日期',
    );
    if (picked == null) return;
    // 与全局约定一致：开学日期自动对齐到所在周的周一
    setState(() => _startDate = WeekCalc.alignToMonday(picked));
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final weeksText = _weeksController.text.trim();
    final error = validateSemesterForm(name: name, weeks: weeksText);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final weeks = int.parse(weeksText);
    // 默认开学日期：今天对齐到周一（用户没选就给一个合理初值）
    final start = WeekCalc.alignToMonday(_startDate ?? DateTime.now());
    // 1.2.1：落库前强制过目确认开学日期（错一位全表周次错位），弹窗内可改。
    // 编辑模式下只有真的换了日期才弹——只改名/改周数不该反复打扰。
    DateTime confirmed = start;
    final initial = _initial;
    if (initial == null || DateFormat('yyyy-MM-dd').format(start) != initial.startDate) {
      final res = await showSemesterStartConfirmDialog(
        context,
        semesterName: name,
        initialStart: start,
        totalWeeks: weeks,
      );
      if (res == null || !mounted) return;
      confirmed = res;
    }
    final iso = DateFormat('yyyy-MM-dd').format(confirmed);
    Navigator.pop(
      context,
      // 编辑模式保留 id 与 isCurrent（落库按 id 更新同一行）
      initial == null
          ? Semester(
              name: name,
              startDate: iso,
              totalWeeks: weeks,
            )
          : initial.copyWith(
              name: name,
              startDate: iso,
              totalWeeks: weeks,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = _initial != null;
    final dateText = _startDate == null
        ? '默认从本周开始'
        : '${DateFormat('yyyy-MM-dd').format(_startDate!)}（周一）';
    // WB_SPEC_230 第 4.2 节第 5 类：含表单的弹窗只换外层壳；content 的 Column
    // 外包 SingleChildScrollView，避免小屏软键盘顶起时 autofocus 输入框溢出。
    return AppDialog(
      title: editing ? '编辑学期' : '新建学期',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '学期名称',
              hintText: '如：大三下学期',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('开学日期'),
            subtitle: Text(dateText),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
          // WB_SPEC_224 第 3.4 节：把「自动对齐到周一」这条既有行为说清楚（行为不变）
          // left: 40 对齐上方 ListTile 的 leading 图标缩进（复审优化 1：魔法数留口径说明）
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '提示：点选任意日期，将自动对齐至当周周一',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
          ),
          TextField(
            controller: _weeksController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '总周数',
              suffixText: '周',
            ),
          ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: _submit, child: Text(editing ? '保存' : '创建')),
      ],
    );
  }
}
