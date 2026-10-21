import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/course.dart';
import '../models/semester.dart';
import '../providers/providers.dart';
import '../services/ocr_service.dart';
import '../services/pdf_import.dart';
import '../ui/app_styles.dart';
import '../utils/ics_parser.dart';
import '../utils/morandi_palette.dart';
import '../database/dao.dart';
import '../widgets/semester_form_dialog.dart';
import '../widgets/semester_start_dialog.dart';
import '../utils/web_schedule_parser.dart';
import 'import_review_page.dart';
import 'web_import_page.dart';

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
            '选择导入方式，解析结果都会先进入核对页，确认后才写入课表。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 16),
          _ImportTile(
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF8FA3B0),
            title: '导入 ICS 日历文件',
            subtitle: '从教务系统导出的 .ics 文件，自动匹配星期/节次/周次',
            onTap: () => _guardedImport(target, (t) => _importIcs(context, t)),
          ),
          _ImportTile(
            icon: Icons.photo_camera_outlined,
            color: const Color(0xFFAFC3BB),
            title: '拍照 / 相册识别课表',
            subtitle: '本地 OCR 识别课表截图（中文），支持手动核对修正',
            onTap: () =>
                _guardedImport(target, (t) => _importImage(context, t)),
          ),
          _ImportTile(
            icon: Icons.picture_as_pdf_outlined,
            color: const Color(0xFFC4B8A8),
            title: '导入 PDF 课表文件',
            subtitle: '提取 PDF 文本后复用相同解析流程',
            onTap: () => _guardedImport(target, (t) => _importPdf(context, t)),
          ),
          _ImportTile(
            icon: Icons.cloud_download_outlined,
            color: const Color(0xFFB8BFC7),
            title: '从教务官网导入',
            subtitle: '内置浏览器登录学校教务系统，打开课表页后一键抓取',
            onTap: () => _guardedImport(target, (t) => _importWeb(context, t)),
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
          onPressed: () => _pickTarget(context),
          child: const Text('更改'),
        ),
      ),
    );
  }

  /// 选目标学期：已有学期列表 + 当场新建（新建即切换为当前学期并设为目标）
  Future<void> _pickTarget(BuildContext context) async {
    final semesters = ref.read(semestersProvider).value ?? const <Semester>[];
    final picked = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                '这次导入到哪个学期？',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final s in semesters)
              ListTile(
                leading: Icon(
                  (_target?.id ??
                              ref.read(currentSemesterProvider).value?.id) ==
                          s.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(s.name),
                subtitle: Text('开学 ${s.startDate} · 共 ${s.totalWeeks} 周'),
                onTap: () => Navigator.pop(ctx, s),
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('新建学期（新学期的课表选这个）'),
              onTap: () => Navigator.pop(ctx, #createNew),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (picked is Semester) {
      setState(() => _target = picked);
      return;
    }
    // 新建学期：建好 → 切换为当前学期 → 设为本次目标
    final created = await showSemesterFormDialog(context);
    if (created == null || !context.mounted) return;
    try {
      final id = await ref
          .read(semestersProvider.notifier)
          .addSemester(created);
      await ref.read(semestersProvider.notifier).switchTo(id);
      setState(() => _target = created.copyWith(id: id, isCurrent: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已新建并切换到「${created.name}」，课表将导入到这里')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('新建学期失败：$e')));
      }
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
        initialStart: DateTime.parse(target.startDate),
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
        semesterStart: DateTime.parse(target.startDate),
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
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(source: source);
      if (picked == null) return;
      final courses = await OcrService.recognizeAndParse(picked.path);
      if (!context.mounted) return;
      if (courses.isEmpty) {
        _showError(
          context,
          source: '图片 OCR 导入',
          message: '未识别出课程，请换一张更清晰的课表截图试试',
        );
        return;
      }
      _openReview(context, courses, const [], target: target);
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
          message: '未从 PDF 中提取到课程，请确认文件是文本型 PDF',
        );
        return;
      }
      _openReview(context, courses, const [], target: target);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: 'PDF 文件导入', message: '$e');
    }
  }

  /// 教务网页导入（1.3.0）：打开内置浏览器页，抓到课程后进核对页
  Future<void> _importWeb(BuildContext context, Semester? target) async {
    if (target == null || target.id == null) {
      _showError(context, source: '教务官网导入', message: '学期数据尚未加载完成，请稍候重试');
      return;
    }
    final result = await Navigator.push<WebScheduleResult>(
      context,
      MaterialPageRoute(builder: (_) => WebImportPage(semesterId: target.id!)),
    );
    if (result == null || !context.mounted) return;
    _openReview(context, result.courses, result.errors, target: target);
  }

  void _openReview(
    BuildContext context,
    List<Course> courses,
    List<String> errors, {
    required Semester target,
    List<IcsTimeBlock> timeBlocks = const [],
  }) {
    // 先提示解析失败条目
    if (errors.isNotEmpty && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('部分条目解析失败'),
          content: Text(errors.take(5).join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportReviewPage(
          drafts: courses,
          targetSemester: target,
          timeBlocks: timeBlocks,
        ),
      ),
    );
  }

  /// 导入失败对话框：失败不是死胡同，提供「复制错误报告 / 重新选择 / 返回」
  ///
  /// 错误报告可复制后发给 AI，请它重新生成导入内容（参考 fkwakeup 的失败闭环）。
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
      builder: (ctx) => AlertDialog(
        title: const Text('导入失败'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('错误报告已复制，可发给 AI 重新生成')),
                );
              }
            },
            child: const Text('复制错误报告'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('重新选择'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('返回'),
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
        onTap: onTap,
      ),
    );
  }
}
