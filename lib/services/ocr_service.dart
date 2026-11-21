import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/course.dart';
import '../models/time_slot.dart';
import '../utils/heuristic_parser.dart';
import '../utils/time_slots_checker.dart';

/// 图片 OCR 识别服务（阶段三）
///
/// 使用 google_mlkit_text_recognition 本地识别中文课表截图。
/// 关键配置：显式传入 [TextRecognitionScript.chinese]（中文脚本），
/// 配合 android/app/build.gradle 的 text-recognition-chinese 模型依赖，
/// 防止中文乱码。
class OcrService {
  OcrService._();

  /// 识别图片并启发式解析为草稿课程
  ///
  /// [imagePath]：本地图片路径（来自 image_picker）
  /// 返回解析出的草稿课程列表与从图片左侧节次栏读到的每节起止时间
  /// （WB_SPEC_249 §8 来源 3：读不到时 timeSlots 为空列表）；
  /// 识别失败抛异常由调用方捕获提示。
  static Future<
    ({List<Course> courses, List<TimeSlot> timeSlots})
  > recognizeAndParse(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);
      // 提取每个 TextBlock 的文本作为一行，按 block 顺序（大致从上到下）
      final lines = recognized.blocks.map((b) => b.text).toList();
      final courses = HeuristicParser.parse(lines);
      // 节次栏时间：把 block 文本按行拆开再抽（一个 block 可能含整列多行）
      final timeSlots = TimeSlotsChecker.extractFromSectionTexts(
        lines.expand((l) => l.split('\n')).toList(),
      );
      return (courses: courses, timeSlots: timeSlots);
    } finally {
      await recognizer.close();
    }
  }
}
