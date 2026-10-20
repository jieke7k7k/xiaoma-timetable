import '../models/course.dart';
import 'morandi_palette.dart';
import 'week_parser.dart';

/// 课表文本启发式解析器（OCR 与 PDF 导入共用）
///
/// 输入按阅读顺序排列的文本行列表（每行来自 OCR 的 TextBlock 或 PDF 的一行），
/// 通过正则提取课程名、星期、节次、周次、教室号，生成草稿课程。
///
/// 设计说明：真实课表格式千差万别，启发式解析只能「尽力而为」——
/// 解析结果绝不直接入库，必须经过人工核对页确认。
/// 课程名与其时间信息可能分行（OCR 常见），因此用「最近一次出现」的
/// 星期/节次/周次/教室来填充后续识别出的课程。
class HeuristicParser {
  HeuristicParser._();

  /// 常见课程名特征字（用于判断某行是否为课程名）
  static const _courseKeywords = [
    '学', '论', '理', '术', '语', '数', '英', '体', '政', '史', '地', '生', '化',
    '物', '医', '药', '护', '概论', '导论', '基础', '原理', '技术', '设计', '分析',
    '实验', '实习', '实践', '金融', '管理', '计算机', '工程', '哲学', '心理', '教育',
    '法学', '经济', '文学', '翻译', '写作', '口语', '听力', '阅读', '美术', '音乐',
    '思政', '军事', '形势', '就业', '创业', '劳动', '安全', '健康', '环境', '文化',
  ];

  /// 解析文本行列表为草稿课程
  static List<Course> parse(List<String> lines) {
    final drafts = <Course>[];
    var lastWeekday = 1;
    var lastStartSection = 1;
    var lastEndSection = 2;
    var lastWeeks = <int>[];
    String? lastClassroom;

    for (final raw in lines) {
      final text = raw.trim();
      if (text.isEmpty) continue;

      final weekday = _extractWeekday(text);
      final sections = _extractSections(text);
      final weeks = _extractWeeks(text);
      final classroom = _extractClassroom(text);
      final name = _extractCourseName(text);

      if (weekday != null) lastWeekday = weekday;
      if (sections != null) {
        lastStartSection = sections.$1;
        lastEndSection = sections.$2;
      }
      if (weeks != null && weeks.isNotEmpty) lastWeeks = weeks;
      if (classroom != null) lastClassroom = classroom;

      if (name != null) {
        drafts.add(Course(
          semesterId: 0,
          name: name,
          classroom: lastClassroom,
          colorValue: MorandiPalette.colors[drafts.length % MorandiPalette.colors.length],
          dayOfWeek: lastWeekday,
          startSection: lastStartSection,
          endSection: lastEndSection,
          // 默认 1~16 周，核对页可改
          weeks: lastWeeks.isEmpty
              ? [for (var w = 1; w <= 16; w++) w]
              : lastWeeks,
        ));
      }
    }
    return drafts;
  }

  /// 提取星期（1~7），支持「周一」「星期3」「周1」等
  static int? _extractWeekday(String text) {
    const names = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6,
      '日': 7, '天': 7, '七': 7,
    };
    final m = RegExp(r'(?:星期|周|礼拜)\s*([一二三四五六日天1-7])').firstMatch(text);
    if (m == null) return null;
    final g = m.group(1)!;
    final asInt = int.tryParse(g);
    if (asInt != null) return asInt >= 1 && asInt <= 7 ? asInt : null;
    return names[g];
  }

  /// 提取节次区间，如「第3-4节」「3-4节」「第3节」
  static (int, int)? _extractSections(String text) {
    final range = RegExp(r'第?\s*(\d{1,2})\s*[-—~至]\s*(\d{1,2})\s*节')
        .firstMatch(text);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      return (a, b);
    }
    final single = RegExp(r'第?\s*(\d{1,2})\s*节').firstMatch(text);
    if (single != null) {
      final a = int.parse(single.group(1)!);
      return (a, a);
    }
    return null;
  }

  /// 提取周次，如「1-16周」「1-16」「1,3,5周」
  static List<int>? _extractWeeks(String text) {
    final range =
        RegExp(r'(\d{1,2})\s*[-—~至]\s*(\d{1,2})\s*周?').firstMatch(text);
    if (range != null) {
      final a = int.parse(range.group(1)!);
      final b = int.parse(range.group(2)!);
      if (a <= b && a >= 1 && b <= 30) {
        return [for (var w = a; w <= b; w++) w];
      }
    }
    // 列表形式：1,3,5周
    final list = RegExp(r'([\d,，\s]+)\s*周').firstMatch(text);
    if (list != null) {
      try {
        final parsed = WeekParser.parse(list.group(1)!.replaceAll('，', ','));
        return parsed.weeks;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 提取教室号，如「16-222」「A301」「16号楼222」
  static String? _extractClassroom(String text) {
    final m = RegExp(r'([A-Za-z]?\d{1,3}\s*[-—]\s*\d{2,4})').firstMatch(text);
    if (m != null) {
      final v = m.group(1)!.replaceAll(' ', '');
      // 排除明显是节次/周次区间的（如 1-16 后面跟"周"，3-4 后面跟"节"）
      final after = text.substring(m.end).trim();
      if (after.startsWith('周') || after.startsWith('节')) return null;
      return v;
    }
    // 单段教室：A301 / 16#222
    final single = RegExp(r'([A-Za-z]{1,2}\d{3})').firstMatch(text);
    if (single != null) return single.group(1);
    return null;
  }

  /// 提取课程名：含课程特征字的行，去掉时间/教室/节次/周次/星期/数字后的剩余文本
  static String? _extractCourseName(String text) {
    if (!_hasCourseKeyword(text)) return null;
    var t = text;
    t = t.replaceAll(RegExp(r'第\s*\d{1,2}\s*[-—~至]?\s*\d{0,2}\s*节'), ' ');
    t = t.replaceAll(RegExp(r'\d{1,2}\s*[-—~至]\s*\d{1,2}\s*周?'), ' ');
    t = t.replaceAll(RegExp(r'周\s*[一二三四五六日天]'), ' ');
    t = t.replaceAll(RegExp(r'星期\s*[一二三四五六日天]'), ' ');
    t = t.replaceAll(RegExp(r'[A-Za-z]?\d{1,3}\s*[-—]\s*\d{2,4}'), ' ');
    t = t.replaceAll(RegExp(r'[A-Za-z]{1,2}\d{3}'), ' ');
    t = t.replaceAll(RegExp(r'\d{1,2}:\d{2}'), ' ');
    t = t.replaceAll(RegExp(r'\d+'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length >= 2) return t;
    return null;
  }

  static bool _hasCourseKeyword(String text) {
    return _courseKeywords.any(text.contains);
  }
}
