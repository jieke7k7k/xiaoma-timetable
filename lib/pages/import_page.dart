import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/course.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../providers/providers.dart';
import '../services/ocr_service.dart';
import '../services/pdf_import.dart';
import '../ui/app_select_field.dart';
import '../ui/app_styles.dart';
import '../utils/app_haptics.dart';
import '../utils/ics_parser.dart';
import '../utils/morandi_palette.dart';
import '../database/dao.dart';
import '../widgets/app_dialog.dart';
import '../widgets/semester_form_dialog.dart';
import '../widgets/semester_start_dialog.dart';
import '../utils/web_schedule_parser.dart';
import 'import_review_page.dart';
import 'school_picker_page.dart';

/// 课程导入入口页
///
/// 1.2.0 起导入先定「目标学期」：页面顶部明示课程将导入到哪个学期，
/// 可更改到已有学期、也可当场新建（新建后自动切换为当前学期）。
/// 目标学期显式贯穿解析（ICS 按目标学期开学日算周次）、核对与入库——
/// 不再中途偷读全局状态，杜绝「以为导进新学期、实际撞上旧学期课程」的误报。
/// 三种导入方式：ICS 文件、图片 OCR、PDF 文件；结果先进核对页，不直接入库。
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  /// 已确认过开学日期的目标学期 id（1.2.1）：同一次导入只弹一次确认，
  /// 切换目标学期后 id 不同会自动重新确认
  int? _startConfirmedForId;

  /// 用户在本页选定的目标学期；为空时用当前激活学期
  Semester? _target;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentSemesterProvider).value;
    final target = _target ?? current;
    return Scaffold(
      appBar: AppBar(title: const Text('导入课表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (target != null) _targetCard(context, target, current),
          const SizedBox(height: 12),
          Text(
            '选择导入方式；解析结果将先进入核对页，确认后写入课表。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          _ImportTile(
            icon: Icons.cloud_download_outlined,
            color: const Color(0xFFB8BFC7),
            title: '从教务官网导入',
            subtitle: '内置浏览器登录教务系统，打开课表页后抓取',
            onTap: () => _guardedImport(target, (t) => _importWeb(context, t)),
          ),
          _ImportTile(
            icon: Icons.photo_camera_outlined,
            color: const Color(0xFFAFC3BB),
            title: '拍照 / 相册识别课表',
            subtitle: '本地 OCR 识别课表截图（中文），可手动核对修正',
            onTap: () =>
                _guardedImport(target, (t) => _importImage(context, t)),
          ),
          _ImportTile(
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF8FA3B0),
            title: '导入 ICS 日历文件',
            subtitle: '导入教务系统导出的 .ics 文件，自动匹配星期、节次与周次',
            onTap: () => _guardedImport(target, (t) => _importIcs(context, t)),
          ),
          _ImportTile(
            icon: Icons.picture_as_pdf_outlined,
            color: const Color(0xFFC4B8A8),
            title: '导入 PDF 课表文件',
            subtitle: '提取 PDF 文本后按相同流程解析',
            onTap: () => _guardedImport(target, (t) => _importPdf(context, t)),
          ),
        ],
      ),
    );
  }

  /// 目标学期卡：明示导入去向 + 「更改」入口（是否新学期在这里回答）
  Widget _targetCard(BuildContext context, Semester target, Semester? current) {
    final isCurrent = current != null && target.id == current.id;
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.school_outlined),
        title: Text(
          '导入到：${target.name}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '开学 ${target.startDate} · 共 ${target.totalWeeks} 周'
          '${isCurrent ? " · 当前学期" : ""}',
        ),
        trailing: TextButton(
          // WB_SPEC_235 跟进 §1-2：目标学期卡的「更改」入口 = 轻点档
          style: TextButton.styleFrom(enableFeedback: false),
          onPressed: () {
            AppHaptics.tap();
            _pickTarget(context);
          },
          child: const Text('更改'),
        ),
      ),
    );
  }

  /// 当前学期 id：优先从已加载的学期列表取 isCurrent 项（复审 L1）——
  /// 只 await 学期列表 provider 不能保证 current provider 已加载，
  /// 直进导入页立刻点「更改」时后者可能仍是 loading。
  int? _currentIdFrom(List<Semester> semesters) {
    for (final s in semesters) {
      if (s.isCurrent) return s.id;
    }
    return null;
  }

  /// 选目标学期（WB_SPEC_256 §3.3 / §3.5 / §7）：
  /// 统一复用 showAppSelectSheet 承载已有学期枚举；「新建学期」改为弹层底部
  /// footer 按钮（48dp 高），点击先关闭底部弹层再弹出 showSemesterFormDialog。
  Future<void> _pickTarget(BuildContext context) async {
    // 先等学期列表加载完再开弹层：首读可能是 loading，直接读 .value 会是空列表
    // （生产里主页一般已预热过，但导入页直进时不能依赖这一点）。
    List<Semester> semesters;
    try {
      semesters = await ref.read(semestersProvider.future);
    } catch (_) {
      semesters = ref.read(semestersProvider).value ?? const <Semester>[];
    }
    if (!context.mounted) return;
    final currentId = _currentIdFrom(semesters) ??
        ref.read(currentSemesterProvider).value?.id;
    // WB_SPEC_256 复审优化（#53）：首次打开不预勾任何学期，恢复
    // WB_SPEC_220「引导新建」语义——用户首次导入通常是新学期课表，
    // 默认勾当前学期会误导；选过之后 _target 保持为上次选择。
    // 当前学期仍以「当前使用中」标注在行文案里（见 shortLabel）。
    final selectedTarget = _target;
    // WB_SPEC_256 §7 落盘修正：Semester 未重写 ==，showAppSelectSheet 内部用 ==
    // 判当前项；currentValue 必须传列表里同一个实例，否则当前行永远不打勾。
    Semester? currentValue = selectedTarget;
    for (final s in semesters) {
      if (s.id == selectedTarget?.id) {
        currentValue = s;
        break;
      }
    }
    final picked = await showAppSelectSheet<Semester>(
      context: context,
      title: '导入至哪个学期',
      currentValue: currentValue,
      options: [
        for (final s in semesters)
          AppSelectOption<Semester>(
            value: s,
            shortLabel: '${s.name}${s.id == currentId ? " · 当前使用中" : ""}',
          ),
      ],
      footer: Builder(
        builder: (sheetContext) => SizedBox(
          width: double.infinity,
          child: FilledButton(
            // WB_SPEC_256 §6.3 / §7：底部操作栏「继续（新建学期）」升至 48dp 高
            style: appBottomBarFilledButtonStyle().copyWith(
              enableFeedback: false,
            ),
            onPressed: () {
              AppHaptics.tap();
              // WB_SPEC_256 §3.5：先关闭底部弹层，再打开新建学期 AppDialog
              Navigator.pop(sheetContext);
              _createNewSemester();
            },
            child: const Text('继续（新建学期）'),
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    setState(() => _target = picked);
  }

  /// 新建学期表单（WB_SPEC_256 §3.5）：在目标选择弹层关闭后弹出，
  /// 建好后写入并切换为当前学期，设为本次目标并给 SnackBar 反馈。
  Future<void> _createNewSemester() async {
    if (!mounted) return;
    final created = await showSemesterFormDialog(context);
    if (created == null || !mounted) return;
    try {
      final id =
          await ref.read(semestersProvider.notifier).addSemester(created);
      await ref.read(semestersProvider.notifier).switchTo(id);
      if (!mounted) return;
      final target = created.copyWith(id: id, isCurrent: true);
      setState(() => _target = target);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已新建并切换至「${created.name}」，课表将导入该学期')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新建学期失败：$e')),
      );
    }
  }

  /// 导入前确认目标学期的开学日期（1.2.1）：未确认先弹窗，
  /// 弹窗里改了日期就直更数据库并同步本地目标；确认过直接放行
  Future<void> _guardedImport(
    Semester? target,
    Future<void> Function(Semester?) action,
  ) async {
    if (target == null) {
      await action(null);
      return;
    }
    if (_startConfirmedForId != target.id) {
      final res = await showSemesterStartConfirmDialog(
        context,
        semesterName: target.name,
        initialStart: target.startDateParsed,
        totalWeeks: target.totalWeeks,
      );
      if (res == null || !mounted) return;
      final iso = DateFormat('yyyy-MM-dd').format(res);
      if (iso != target.startDate) {
        final updated = target.copyWith(startDate: iso);
        await Dao.instance.updateSemester(updated);
        if (!mounted) return;
        // 当前学期被改到时同步内存状态，今日周次立即按新日期重算
        if (ref.read(currentSemesterProvider).value?.id == updated.id) {
          ref.read(currentSemesterProvider.notifier).setDirectly(updated);
        }
        ref.invalidate(semestersProvider);
        setState(() => _target = updated);
        target = updated;
      }
      _startConfirmedForId = target.id;
    }
    // 注意：动作必须用（可能已改开学日期的）最新 target，不能用点击时捕获的旧对象
    await action(target);
  }

  Future<void> _importIcs(BuildContext context, Semester? target) async {
    if (target == null) {
      _showError(context, source: 'ICS 文件导入', message: '学期数据尚未加载完成，请稍候重试');
      return;
    }
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );
      if (files.isEmpty || files.first.path == null) return;
      final content = await File(files.first.path!).readAsString();
      final slots = ref.read(timeSlotsProvider).value ?? [];
      final parsed = IcsParser.parse(
        content,
        semesterStart: target.startDateParsed,
        slots: slots,
      );
      if (!context.mounted) return;
      _openReview(
        context,
        parsed.courses,
        parsed.errors,
        target: target,
        timeBlocks: parsed.timeBlocks,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: 'ICS 文件导入', message: '$e');
    }
  }

  Future<void> _importImage(BuildContext context, Semester? target) async {
    if (target == null) {
      _showError(context, source: '图片 OCR 导入', message: '学期数据尚未加载完成，请稍候重试');
      return;
    }
    // 让用户选择拍照还是相册
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              // WB_SPEC_235 跟进 §1-2：拍照 / 相册两个选择项 = 轻点档
              onTap: () {
                AppHaptics.tap();
                Navigator.pop(ctx, ImageSource.camera);
              },
              enableFeedback: false,
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () {
                AppHaptics.tap();
                Navigator.pop(ctx, ImageSource.gallery);
              },
              enableFeedback: false,
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final ocrResult = await OcrService.recognizeAndParse(picked.path);
      if (!context.mounted) return;
      if (ocrResult.courses.isEmpty) {
        _showError(
          context,
          source: '图片 OCR 导入',
          message: '未识别出课程，请更换更清晰的课表截图',
        );
        return;
      }
      _openReview(
        context,
        ocrResult.courses,
        const [],
        target: target,
        ocrTimeSlots: ocrResult.timeSlots,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: '图片 OCR 导入', message: '$e');
    }
  }

  Future<void> _importPdf(BuildContext context, Semester? target) async {
    if (target == null) {
      _showError(context, source: 'PDF 文件导入', message: '学期数据尚未加载完成，请稍候重试');
      return;
    }
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (files.isEmpty || files.first.path == null) return;
      final courses = await PdfImport.extractAndParse(files.first.path!);
      if (!context.mounted) return;
      if (courses.isEmpty) {
        _showError(
          context,
          source: 'PDF 文件导入',
          message: '未从 PDF 中提取到课程，请确认文件为文本型 PDF',
        );
        return;
      }
      _openReview(context, courses, const [], target: target);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: 'PDF 文件导入', message: '$e');
    }
  }

  /// 教务网页导入：先进入选校器（WB_SPEC_249 方案 A 链式 push：
  /// ImportPage → SchoolPickerPage → WebImportPage），抓到课程后进核对页。
  /// 选校器回传的学校预设作息（§8 兜底）与确认的开学日期（§9）一并透传给复核页。
  Future<void> _importWeb(BuildContext context, Semester? target) async {
    if (target == null || target.id == null) {
      _showError(context, source: '教务官网导入', message: '学期数据尚未加载完成，请稍候重试');
      return;
    }
    final picked = await Navigator.push<SchoolWebImportResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SchoolPickerPage(semesterId: target.id!),
      ),
    );
    if (picked == null || !context.mounted) return;
    final result = picked.scheduleResult;
    // WB_SPEC_231 第 5.4 节：抓取成功不再静默跳走，核对页顶部常驻汇总横幅
    // 「已从当前页面识别出 N 门课程（共 M 个排课节次）」；其它导入来源不传
    final sections = WebScheduleParser.countWeeklySections(result.courses);
    _openReview(
      context,
      result.courses,
      result.errors,
      target: target,
      summary: '已从当前页面识别出 ${result.courses.length} 门课程'
          '（共 $sections 个排课节次）',
      webTimeSlots: result.extractedTimeSlots,
      detectedCurrentWeek: result.detectedCurrentWeek,
      schoolPresetTimeSlots: picked.school?.timeSlots,
      confirmedStartDate: picked.confirmedStartDate,
    );
  }

  void _openReview(
    BuildContext context,
    List<Course> courses,
    List<String> errors, {
    required Semester target,
    List<IcsTimeBlock> timeBlocks = const [],
    String? summary,
    // WB_SPEC_249 §8/§9：导入后作息与周数检查的输入，缺省为 null 表示该来源无数据
    List<TimeSlot>? webTimeSlots,
    List<TimeSlot>? schoolPresetTimeSlots,
    List<TimeSlot>? ocrTimeSlots,
    DateTime? confirmedStartDate,
    int? detectedCurrentWeek,
  }) {
    // 先提示解析失败条目
    if (errors.isNotEmpty && context.mounted) {
      // WB_SPEC_230 第 4.2 节第 4 类：纯信息提示，走统一信息弹窗
      showAppInfoDialog(
        context,
        title: '部分条目解析失败',
        message: errors.take(5).join('\n'),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportReviewPage(
          drafts: courses,
          targetSemester: target,
          timeBlocks: timeBlocks,
          webImportSummary: summary,
          webTimeSlots: webTimeSlots,
          schoolPresetTimeSlots: schoolPresetTimeSlots,
          ocrTimeSlots: ocrTimeSlots,
          confirmedStartDate: confirmedStartDate,
          detectedCurrentWeek: detectedCurrentWeek,
        ),
      ),
    );
  }

  /// 导入失败对话框：失败不是死胡同，提供「复制错误报告 / 重新选择 / 返回」
  ///
  /// 错误报告可复制后发给他人帮忙排查（参考 fkwakeup 的失败闭环）。
  void _showError(
    BuildContext context, {
    required String source,
    required String message,
  }) {
    final report =
        '小马课表导入错误报告\n'
        '时间：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}\n'
        '导入方式：$source\n'
        '错误信息：$message';
    showDialog(
      context: context,
      // WB_SPEC_230 第 4.2 节第 4 类：多按钮展示弹窗嵌 AppDialog，
      // 原本的 SingleChildScrollView 原样传入 content
      builder: (ctx) => AppDialog(
        title: '导入失败',
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          // WB_SPEC_235 跟进 §1-3 / §4：三个按钮走标准 action 构造（轻点档）
          AppDialogAction(
            label: '复制错误报告',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('错误报告已复制，可发送他人协助排查')),
                );
              }
            },
          ),
          AppDialogAction(label: '重新选择', onPressed: () => Navigator.pop(ctx)),
          AppDialogAction(
            label: '返回',
            primary: true,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}

class _ImportTile extends StatelessWidget {
  const _ImportTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 深色模式下入口图标做同款降饱和（与课程卡片一致），
    // 避免中等亮度色块在深底上形成刺眼对比
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileColor = isDark ? MorandiPalette.desaturateForDark(color) : color;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.l,
          vertical: AppSpacing.s,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tileColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Icon(icon, color: tileColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        // WB_SPEC_235 跟进 §1-1：四个导入入口（ICS / 拍照 OCR / PDF / 教务官网）
        // = 轻点档；`enableFeedback: false` 关掉 ListTile 自带反馈防双震
        onTap: () {
          AppHaptics.tap();
          onTap();
        },
        enableFeedback: false,
      ),
    );
  }
}
