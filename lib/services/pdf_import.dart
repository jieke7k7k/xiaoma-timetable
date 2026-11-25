import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../utils/heuristic_parser.dart';
import '../utils/time_slots_checker.dart';

/// PDF 课表导入服务（阶段三）
///
/// 提取 PDF 文本后，复用与图片导入相同的启发式解析流程。
/// 使用 syncfusion_flutter_pdf（纯 Dart、无原生编译，避免 pdfrx 的
/// CMake/NDK/PDFium 与 GitHub 下载问题）。
///
/// 注：syncfusion 需要 license key（社区版免费），无 key 时文本提取
/// 仍可用；正式发布前可到 syncfusion.com 注册并在 main() 里调用
/// SyncfusionLicense.registerLicense()。
class PdfImport {
  PdfImport._();

  /// 提取 PDF 全部文本并启发式解析为草稿课程（兼容既有调用方）
  static Future<List<Course>> extractAndParse(String filePath) async {
    final res = await extractAndParseWithSlots(filePath);
    return res.courses;
  }

  /// 提取 PDF 全部文本并启发式解析为草稿课程，同时像 OcrService 一样
  /// 顺带提取左侧节次时间（读不到时 timeSlots 为空列表，S4-8）
  static Future<({List<Course> courses, List<TimeSlot> timeSlots})>
      extractAndParseWithSlots(String filePath) async {
    final lines = await extractLines(filePath);
    final courses = HeuristicParser.parse(lines);
    final timeSlots = TimeSlotsChecker.extractFromSectionTexts(lines);
    return (courses: courses, timeSlots: timeSlots);
  }

  /// 提取 PDF 全部文本，按行返回
  static Future<List<String>> extractLines(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final text = PdfTextExtractor(doc).extractText();
      return text.split(RegExp(r'\r?\n'));
    } finally {
      doc.dispose();
    }
  }
}
