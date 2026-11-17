import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' as pw_pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/course.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../ui/grid_metrics.dart';
import '../utils/color_schemes.dart';
import '../utils/morandi_palette.dart';
import '../utils/semester_export_helper.dart';
import '../utils/week_calc.dart';
import '../widgets/conflict_block.dart';

/// 整学期多页 PDF 矢量导出服务（WB_SPEC_237 §7）。
///
/// 每周一页（A4 纵向），网格与周视图同构：左侧节次时间轴、顶部星期表头、
/// 午间/晚间分隔带、课程块与冲突块全部矢量重画（不是截图）。
/// 中文字体用 NotoSansSC 嵌入；加载失败抛明确错误，不静默回退成方框。
/// PDF 不做模糊，只画颜色渐变；无水印、无页码；生成后核实 ≤5MB。
class SemesterPdfExport {
  SemesterPdfExport._();

  static const double _margin = 24;
  static const double _titleHeight = 26;
  static const double _dateHeight = 20;
  static const int _maxBytes = 5 * 1024 * 1024;
  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  /// 生成整学期 PDF 并打开系统分享面板，返回实际页数。
  static Future<int> generateAndShare({
    required Semester semester,
    required List<Course> allCourses,
    required List<TimeSlot> slots,
    required List<GridBand> bands,
    required UiSettings ui,
    required int maxWeek,
  }) async {
    final bytes = await generatePdfBytes(
      semester: semester,
      allCourses: allCourses,
      slots: slots,
      bands: bands,
      ui: ui,
      maxWeek: maxWeek,
    );
    await sharePdfBytes(semester: semester, bytes: bytes);
    return maxWeek;
  }

  /// 只生成 PDF 字节（不分享），供测试与 BottomSheet 分步调用。
  /// 生成后核实 ≤5MB，超了抛错。
  static Future<Uint8List> generatePdfBytes({
    required Semester semester,
    required List<Course> allCourses,
    required List<TimeSlot> slots,
    required List<GridBand> bands,
    required UiSettings ui,
    required int maxWeek,
  }) async {
    if (slots.isEmpty) {
      throw StateError('没有可用的节次时间表，无法导出 PDF');
    }
    if (maxWeek <= 0) {
      throw StateError('本学期还没有课，无法导出 PDF');
    }
    final font = await _loadChineseFont();
    final doc = pw.Document();
    for (var week = 1; week <= maxWeek; week++) {
      doc.addPage(
        pw.Page(
          pageFormat: pw_pdf.PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(_margin),
          theme: pw.ThemeData.withFont(base: font),
          build: (_) => _buildWeekPage(
            semester: semester,
            allCourses: allCourses,
            slots: slots,
            bands: bands,
            ui: ui,
            week: week,
            font: font,
          ),
        ),
      );
    }
    final bytes = await doc.save();
    if (bytes.lengthInBytes > _maxBytes) {
      throw StateError(
          'PDF 文件大小超出 5MB 上限（实际 ${(bytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)}MB）');
    }
    return bytes;
  }

  /// 把已生成的 PDF 字节写临时文件、打开系统分享面板，分享后删临时文件。
  static Future<void> sharePdfBytes({
    required Semester semester,
    required Uint8List bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${semester.name}课表.pdf');
    try {
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: '${semester.name}课表.pdf',
              mimeType: 'application/pdf',
            ),
          ],
          text: '这是${semester.name}完整课表，请查收',
        ),
      );
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// 加载中文字体；失败抛明确错误（不要静默回退成 Helvetica 方框）。
  static Future<pw.Font> _loadChineseFont() async {
    try {
      final data = await rootBundle.load('assets/fonts/NotoSansSC.ttf');
      return pw.Font.ttf(data);
    } catch (e) {
      throw StateError('PDF 导出需要中文字体 assets/fonts/NotoSansSC.ttf，'
          '加载失败（$e），请检查字体资源是否随包打包');
    }
  }

  /// 一周一页：标题 + 日期范围 + 网格（与 _ExportSheet 同构）。
  ///
  /// 全部高度固定算死：标题 26 + 间隙 2 + 日期 20 + 间隙 12 = 60，
  /// 网格高 = A4 可用高 − 60；行高 = (网格高 − 表头 46 − 带子总高) / 节数，
  /// 保证 14 节 + 两条带子恰好一页放得下，不溢出、不留空。
  static pw.Widget _buildWeekPage({
    required Semester semester,
    required List<Course> allCourses,
    required List<TimeSlot> slots,
    required List<GridBand> bands,
    required UiSettings ui,
    required int week,
    required pw.Font font,
  }) {
    final a4 = pw_pdf.PdfPageFormat.a4;
    final contentW = a4.width - _margin * 2;
    final contentH = a4.height - _margin * 2;
    const titleBlockH = _titleHeight + 2 + _dateHeight + 12;
    final gridH = contentH - titleBlockH;
    final sectionCount =
        slots.map((s) => s.section).reduce((a, b) => a > b ? a : b);
    final rowH =
        (gridH - kGridHeaderHeight - bands.length * kBandHeight) / sectionCount;
    final colW = (contentW - kTimeAxisWidth) / 7;
    final dates = WeekCalc.weekDatesOf(semester.startDateParsed, week);
    final dateRange =
        '${dates.first.month}月${dates.first.day}日 - ${dates.last.month}月${dates.last.day}日';
    final title = '${semester.name} · 第 $week 周课表';

    double bandsBefore(int section) =>
        bands.where((b) => section > b.after).length.toDouble();
    double topOf(int section) =>
        (section - 1) * rowH + bandsBefore(section) * kBandHeight;
    double bandTop(GridBand b) =>
        b.after * rowH + bandsBefore(b.after) * kBandHeight;

    final vSegments = verticalLineSegments(
      rowHeight: rowH,
      sectionCount: sectionCount,
      activeBands: bands,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          height: _titleHeight,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
              font: font,
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Container(
          height: _dateHeight,
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            dateRange,
            style: pw.TextStyle(
              fontSize: 12,
              color: pw_pdf.PdfColors.grey700,
              font: font,
            ),
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          width: contentW,
          height: gridH,
          child: pw.Stack(
            children: [
              // 表头（与 _ExportSheet 同结构：左月、星期 + 日期）
              pw.Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: pw.Container(
                  height: kGridHeaderHeight,
                  color: pw_pdf.PdfColors.grey200,
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: kTimeAxisWidth,
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          '${dates.first.month}月',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: pw_pdf.PdfColors.grey700,
                            font: font,
                          ),
                        ),
                      ),
                      for (var d = 1; d <= 7; d++)
                        pw.Expanded(
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            children: [
                              pw.Text(
                                '周${_weekNames[d - 1]}',
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  color: pw_pdf.PdfColors.grey700,
                                  font: font,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                '${dates[d - 1].day}',
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  font: font,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // 表头底边
              pw.Positioned(
                top: kGridHeaderHeight,
                left: 0,
                right: 0,
                child: pw.Container(
                  height: 0.5,
                  color: pw_pdf.PdfColors.grey400,
                ),
              ),
              // 横向网格线：每节底边（不含最后一条底边）+ 带子底边
              for (var r = 1; r < sectionCount; r++)
                pw.Positioned(
                  top: kGridHeaderHeight + topOf(r) + rowH,
                  left: 0,
                  right: 0,
                  child: pw.Container(
                    height: 0.5,
                    color: pw_pdf.PdfColors.grey300,
                  ),
                ),
              for (final b in bands)
                pw.Positioned(
                  top: kGridHeaderHeight + topOf(b.after + 1),
                  left: 0,
                  right: 0,
                  child: pw.Container(
                    height: 0.5,
                    color: pw_pdf.PdfColors.grey300,
                  ),
                ),
              // 纵向列线：分段跳过带子（与 _ExportSheet 同口径）；
              // 最右侧 c=7 由外框画，不重复
              for (var c = 0; c < 7; c++)
                for (final seg in vSegments)
                  pw.Positioned(
                    left: kTimeAxisWidth + c * colW,
                    top: kGridHeaderHeight + seg.start,
                    child: pw.Container(
                      width: 0.5,
                      height: seg.end - seg.start,
                      color: pw_pdf.PdfColors.grey300,
                    ),
                  ),
              // 时间轴：节次 + 起止时间（跟随 axisShowTime）
              for (final s in slots)
                pw.Positioned(
                  left: 0,
                  top: kGridHeaderHeight + topOf(s.section),
                  child: pw.Container(
                    width: kTimeAxisWidth,
                    height: rowH,
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          '${s.section}',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: pw_pdf.PdfColors.grey700,
                            font: font,
                          ),
                        ),
                        if (ui.axisShowTime) ...[
                          pw.Text(
                            s.startTime,
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: pw_pdf.PdfColors.grey600,
                              font: font,
                            ),
                          ),
                          pw.Text(
                            s.endTime,
                            style: pw.TextStyle(
                              fontSize: 8,
                              color: pw_pdf.PdfColors.grey600,
                              font: font,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              // 分隔带（通栏：左段名称 + 右段名称与时间段）
              for (final b in bands) ...[
                pw.Positioned(
                  left: 0,
                  top: kGridHeaderHeight + bandTop(b),
                  child: pw.Container(
                    width: kTimeAxisWidth,
                    height: kBandHeight,
                    color: pw_pdf.PdfColors.grey200,
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      b.label,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: pw_pdf.PdfColors.grey700,
                        font: font,
                      ),
                    ),
                  ),
                ),
                pw.Positioned(
                  left: kTimeAxisWidth,
                  top: kGridHeaderHeight + bandTop(b),
                  right: 0,
                  child: pw.Container(
                    height: kBandHeight,
                    color: pw_pdf.PdfColors.grey200,
                    alignment: pw.Alignment.center,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          b.label,
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: pw_pdf.PdfColors.grey700,
                            font: font,
                          ),
                        ),
                        if (b.interval.isNotEmpty) ...[
                          pw.SizedBox(width: 8),
                          pw.Text(
                            b.interval,
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: pw_pdf.PdfColors.grey700,
                              font: font,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              // 课程块 / 冲突块（与 _ExportSheet 同公式定位）
              for (var d = 1; d <= 7; d++)
                for (final block in _blocksForDay(
                  [for (final c in allCourses) if (c.dayOfWeek == d) c],
                  week,
                ))
                  pw.Positioned(
                    left: kTimeAxisWidth + (d - 1) * colW + 1.5,
                    top: kGridHeaderHeight + topOf(block.startSection) + 1.5,
                    child: pw.Container(
                      width: colW - 3,
                      height:
                          (block.endSection - block.startSection + 1) * rowH -
                              3,
                      child: block.pair != null
                          ? _conflictBlockWidget(
                              block.pair!,
                              (block.endSection - block.startSection + 1) *
                                      rowH -
                                  3,
                              ui,
                              font,
                            )
                          : _courseBlockWidget(
                              block.course!,
                              (block.endSection - block.startSection + 1) *
                                      rowH -
                                  3,
                              ui,
                              font,
                              badgeText: block.badgeText,
                            ),
                    ),
                  ),
              // 外框（最后画，压在表头底色之上；块内缩 1.5，不会被框线盖住）
              pw.Positioned.fill(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: pw_pdf.PdfColors.grey400,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 一天内按节次重叠分组（忽略周次过滤——PDF 的冲突块要按 §4.1
  /// 在第 1–16 周每一页都出现；周过滤只在 checkConflict 的门里做）。
  ///
  /// 两门一组且 checkConflict 非空 → 冲突块（覆盖并集）；
  /// 其余画当周生效的第一门（多门时带 +N 角标，与 App 多门卡一致）；
  /// 当周无一门生效 → 不画。
  static List<_PdfBlock> _blocksForDay(List<Course> dayCourses, int week) {
    if (dayCourses.isEmpty) return const [];
    final sorted = [...dayCourses]
      ..sort((a, b) {
        final c = a.startSection.compareTo(b.startSection);
        return c != 0 ? c : a.endSection.compareTo(b.endSection);
      });
    final groups = <List<Course>>[];
    var cur = <Course>[sorted.first];
    var curEnd = sorted.first.endSection;
    for (var i = 1; i < sorted.length; i++) {
      final c = sorted[i];
      if (c.startSection <= curEnd) {
        cur.add(c);
        if (c.endSection > curEnd) curEnd = c.endSection;
      } else {
        groups.add(cur);
        cur = [c];
        curEnd = c.endSection;
      }
    }
    groups.add(cur);

    final blocks = <_PdfBlock>[];
    for (final g in groups) {
      final start =
          g.map((c) => c.startSection).reduce((a, b) => a < b ? a : b);
      final end = g.map((c) => c.endSection).reduce((a, b) => a > b ? a : b);
      // P1-5：三门及以上同组不画冲突块（只画两门）——已统计，测试学期
      // 数据（8 门课，18 周）按节次重叠分组数过，最大一组 2 门，≥3 门
      // 组 0 个，所以这个 fallback 目前走不到；真出现三门同组时按
      // 规格 §14 报他定，不擅自改（见 wb237 测试 §4.1 的统计用例）。
      if (g.length == 2) {
        final pair = SemesterExportHelper.checkConflict(g[0], g[1], week);
        if (pair != null) {
          blocks.add(_PdfBlock.conflict(
            pair: pair,
            startSection: start,
            endSection: end,
          ));
          continue;
        }
      }
      // 非冲突组：只画当周生效的第一门（取该门自己的节次范围，不取并集）
      final active = g.where((c) => c.isActiveInWeek(week)).toList();
      if (active.isEmpty) continue;
      final first = active.first;
      blocks.add(_PdfBlock.course(
        course: first,
        startSection: first.startSection,
        endSection: first.endSection,
        badgeText: active.length > 1 ? '+${active.length - 1}' : null,
      ));
    }
    return blocks;
  }

  /// 课程块（矢量）：底色跟随当前课程配色方案；教室/老师按开关；
  /// 底色偏深时改用浅色文字（与 CourseCard 同口径，阈值亮度 0.42）。
  /// 块太矮（<40pt）时只留课名，不画教室/老师行。
  static pw.Widget _courseBlockWidget(
    Course course,
    double blockHeight,
    UiSettings ui,
    pw.Font font, {
    String? badgeText,
  }) {
    final cardColor = Color(mapCourseColor(course.colorValue, ui.colorScheme));
    final useLightText = cardColor.computeLuminance() < 0.42;
    final nameColor = pw_pdf.PdfColor.fromInt(
      useLightText ? MorandiPalette.darkTextColor : MorandiPalette.textColor,
    );
    final metaColor = pw_pdf.PdfColor.fromInt(
      useLightText
          ? MorandiPalette.darkSubTextColor
          : MorandiPalette.subTextColor,
    );
    final metaParts = <String>[];
    if (ui.showClassroom && (course.classroom ?? '').isNotEmpty) {
      metaParts.add(course.classroom!);
    }
    if (ui.showTeacher && (course.teacher ?? '').isNotEmpty) {
      metaParts.add(course.teacher!);
    }
    final meta = metaParts.join(' · ');
    final showMeta = blockHeight >= 40 && meta.isNotEmpty;
    // 课名 9 字（如「计算机辅助药物设计」）在 10.5pt 下约 94pt，列宽
    // 只有约 59pt，一行放不下会被截成 5 字。块够高（≥60pt，2 节及以上）
    // 时让课名折两行；1 节的短块仍只留一行（与 App 内卡片一致）。
    final nameMaxLines = blockHeight >= 60 ? 2 : 1;
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: pw_pdf.PdfColor.fromInt(cardColor.toARGB32()),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  course.name,
                  maxLines: nameMaxLines,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                    color: nameColor,
                    font: font,
                  ),
                ),
              ),
              if (badgeText != null) ...[
                pw.SizedBox(width: 2),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: pw_pdf.PdfColor.fromInt(
                      useLightText
                          ? MorandiPalette.darkBadgeBackground
                          : MorandiPalette.textColor,
                    ),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  child: pw.Text(
                    badgeText,
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: pw_pdf.PdfColor.fromInt(
                        useLightText
                            ? MorandiPalette.darkBadgeTextColor
                            : 0xFFFFFFFF,
                      ),
                      font: font,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showMeta)
            pw.Text(
              meta,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: 9.5,
                color: metaColor,
                font: font,
              ),
            ),
        ],
      ),
    );
  }

  /// 冲突块（矢量，与 App 内 ConflictBlock 逐项对齐，1sp ≈ 1pt）：
  /// 完整外框 1.5px 实线 #6B7280、圆角 8；整框一个渐变（不做模糊）；
  /// 中间 1.5px 虚线分隔；「前半学期」/「后半学期」标签 pill。
  /// PDF 列宽约 71pt，按小屏档（标签 7 / 课名 8.5 / 教室 8）画。
  /// 半块 <50pt 时藏老师名，只留「课名 · 教室」。
  static pw.Widget _conflictBlockWidget(
    SemesterConflictPair pair,
    double blockHeight,
    UiSettings ui,
    pw.Font font,
  ) {
    final colors = ConflictBlockAppearance.getColors(ui.conflictBlockColorId);
    final darkEnd = ConflictBlockAppearance.darkEnd(
      ui.conflictBlockColorId,
      ui.conflictGradientIntensity,
    );
    final halfHeight = blockHeight / 2;
    final hideTeacher = halfHeight < 50;
    return pw.Container(
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          begin: pw.Alignment.topCenter,
          end: pw.Alignment.bottomCenter,
          colors: [
            pw_pdf.PdfColor.fromInt(colors.light.toARGB32()),
            pw_pdf.PdfColor.fromInt(darkEnd.toARGB32()),
          ],
        ),
        border: pw.Border.all(
          color: pw_pdf.PdfColor.fromInt(0xFF6B7280),
          width: 1.5,
        ),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 2,
              ),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    color: pw_pdf.PdfColor.fromInt(0xFF6B7280),
                    width: 1.5,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
              ),
              child: _conflictHalfWidget(
                pair.topCourse,
                '前半学期',
                hideTeacher,
                halfHeight,
                font,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 2,
              ),
              child: _conflictHalfWidget(
                pair.bottomCourse,
                '后半学期',
                hideTeacher,
                halfHeight,
                font,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 冲突块半块。半块够高（≥38pt）时标签、课名、教室/老师各占一行，
  /// 课名拿满列宽（约 67pt，6 字课名放得下）；半块太矮时标签与课名挤
  /// 一行（与 App 内短块分支一致，课名可能被截断，是既定折中）。
  /// 注意：标签与课名不能同行——标签 pill 约占 32pt，剩下的宽度只够
  /// 3 个字，「天然药物化学」会被截成「天然药」。
  static pw.Widget _conflictHalfWidget(
    Course course,
    String tagText,
    bool hideTeacher,
    double halfHeight,
    pw.Font font,
  ) {
    final meta = hideTeacher
        ? (course.classroom ?? '')
        : '${course.classroom ?? ''}${course.teacher != null ? ' · ${course.teacher}' : ''}';
    final tagPill = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2),
      decoration: pw.BoxDecoration(
        color: pw_pdf.PdfColor.fromInt(0xB3FFFFFF),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        tagText,
        style: pw.TextStyle(
          fontSize: 7,
          fontWeight: pw.FontWeight.bold,
          color: pw_pdf.PdfColor.fromInt(0xFF4B5563),
          font: font,
        ),
      ),
    );
    final nameText = pw.Text(
      course.name,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: pw_pdf.PdfColor.fromInt(0xFF1F2937),
        font: font,
      ),
    );
    final metaText = pw.Text(
      meta,
      maxLines: 1,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(
        fontSize: 8,
        color: pw_pdf.PdfColor.fromInt(0xFF374151),
        font: font,
      ),
    );
    if (halfHeight < 38) {
      // 短块：单行（标签 + 课名 · 教室），与 App 内短块分支一致。
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              tagPill,
              pw.SizedBox(width: 4),
              pw.Expanded(
                child: pw.Text(
                  meta.isEmpty ? course.name : '${course.name} · $meta',
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: pw_pdf.PdfColor.fromInt(0xFF1F2937),
                    font: font,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        tagPill,
        pw.SizedBox(height: 1),
        nameText,
        pw.SizedBox(height: 1),
        metaText,
      ],
    );
  }
}

/// PDF 里一个待画的块（课程块或冲突块）。
class _PdfBlock {
  const _PdfBlock.course({
    required this.course,
    required this.startSection,
    required this.endSection,
    this.badgeText,
  }) : pair = null;

  const _PdfBlock.conflict({
    required this.pair,
    required this.startSection,
    required this.endSection,
  }) : course = null,
       badgeText = null;

  final Course? course;
  final SemesterConflictPair? pair;
  final int startSection;
  final int endSection;
  final String? badgeText;
}
