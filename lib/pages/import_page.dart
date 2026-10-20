import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/course.dart';
import '../providers/providers.dart';
import '../services/ocr_service.dart';
import '../services/pdf_import.dart';
import '../ui/app_styles.dart';
import '../utils/ics_parser.dart';
import '../utils/morandi_palette.dart';
import 'import_review_page.dart';

/// 课程导入入口页（阶段三）
///
/// 三种导入方式：ICS 文件、图片 OCR、PDF 文件；教务官网导入预留入口。
/// 所有导入结果均先进入人工核对页，不直接入库。
class ImportPage extends ConsumerWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入课表')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '选择导入方式，解析结果都会先进入核对页，确认后才写入课表。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 16),
          _ImportTile(
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFF8FA3B0),
            title: '导入 ICS 日历文件',
            subtitle: '从教务系统导出的 .ics 文件，自动匹配星期/节次/周次',
            onTap: () => _importIcs(context, ref),
          ),
          _ImportTile(
            icon: Icons.photo_camera_outlined,
            color: const Color(0xFFAFC3BB),
            title: '拍照 / 相册识别课表',
            subtitle: '本地 OCR 识别课表截图（中文），支持手动核对修正',
            onTap: () => _importImage(context, ref),
          ),
          _ImportTile(
            icon: Icons.picture_as_pdf_outlined,
            color: const Color(0xFFC4B8A8),
            title: '导入 PDF 课表文件',
            subtitle: '提取 PDF 文本后复用相同解析流程',
            onTap: () => _importPdf(context, ref),
          ),
          _ImportTile(
            icon: Icons.cloud_download_outlined,
            color: const Color(0xFFB8BFC7),
            title: '从教务官网导入',
            subtitle: '即将上线，敬请期待',
            onTap: () => _comingSoon(context),
          ),
        ],
      ),
    );
  }

  Future<void> _importIcs(BuildContext context, WidgetRef ref) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
      );
      if (files.isEmpty || files.first.path == null) return;
      final content = await File(files.first.path!).readAsString();
      final semester = ref.read(currentSemesterProvider).value!;
      final slots = ref.read(timeSlotsProvider).value ?? [];
      final parsed = IcsParser.parse(
        content,
        semesterStart: DateTime.parse(semester.startDate),
        slots: slots,
      );
      if (!context.mounted) return;
      _openReview(context, parsed.courses, parsed.errors,
          timeBlocks: parsed.timeBlocks);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: 'ICS 文件导入', message: '$e');
    }
  }

  Future<void> _importImage(BuildContext context, WidgetRef ref) async {
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
            message: '未识别出课程，请换一张更清晰的课表截图试试');
        return;
      }
      _openReview(context, courses, const []);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: '图片 OCR 导入', message: '$e');
    }
  }

  Future<void> _importPdf(BuildContext context, WidgetRef ref) async {
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
            message: '未从 PDF 中提取到课程，请确认文件是文本型 PDF');
        return;
      }
      _openReview(context, courses, const []);
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, source: 'PDF 文件导入', message: '$e');
    }
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('教务官网导入即将上线，敬请期待')));
  }

  void _openReview(
    BuildContext context,
    List<Course> courses,
    List<String> errors, {
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
                onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportReviewPage(
          drafts: courses,
          timeBlocks: timeBlocks,
        ),
      ),
    );
  }

  /// 导入失败对话框：失败不是死胡同，提供「复制错误报告 / 重新选择 / 返回」
  ///
  /// 错误报告可复制后发给 AI，请它重新生成导入内容（参考 fkwakeup 的失败闭环）。
  void _showError(BuildContext context,
      {required String source, required String message}) {
    final report = '小马课表导入错误报告\n'
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
                    const SnackBar(content: Text('错误报告已复制，可发给 AI 重新生成')));
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
    final tileColor = isDark
        ? MorandiPalette.desaturateForDark(color)
        : color;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.l, vertical: AppSpacing.s),
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
