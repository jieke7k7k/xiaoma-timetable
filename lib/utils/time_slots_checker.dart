import '../models/time_slot.dart';

/// 午间/晚间分隔带推算结果
/// 仅在存在明显空档时有值；无明显空档（如晚上没课）时对应字段为 null，表示保持原样
class BreakBandSuggestion {
  /// 午间带子：位于 [lunchAfterSection] 节之后，起止为 [lunchStart] ~ [lunchEnd]
  final int? lunchAfterSection;
  final String? lunchStart;
  final String? lunchEnd;

  /// 晚间带子：位于 [dinnerAfterSection] 节之后，起止为 [dinnerStart] ~ [dinnerEnd]
  final int? dinnerAfterSection;
  final String? dinnerStart;
  final String? dinnerEnd;

  const BreakBandSuggestion({
    this.lunchAfterSection,
    this.lunchStart,
    this.lunchEnd,
    this.dinnerAfterSection,
    this.dinnerStart,
    this.dinnerEnd,
  });

  bool get hasLunch => lunchAfterSection != null;
  bool get hasDinner => dinnerAfterSection != null;
}

/// 单节作息差异项（用于弹窗展示）
class TimeSlotDiff {
  final int section;
  final String currentRange;
  final String incomingRange;

  const TimeSlotDiff({
    required this.section,
    required this.currentRange,
    required this.incomingRange,
  });
}

/// 作息时间比对结果
class TimeSlotCompareResult {
  final bool hasDifference;
  final List<TimeSlotDiff> diffs;

  /// 按「仅覆盖已读到的节次、保留其余原节次」合并后的完整目标作息
  final List<TimeSlot> mergedSlots;
  final BreakBandSuggestion breakBands;

  const TimeSlotCompareResult({
    required this.hasDifference,
    required this.diffs,
    required this.mergedSlots,
    required this.breakBands,
  });
}

/// §8 导入时作息时间解析、比对与午间/晚间带子推算工具（纯函数）
class TimeSlotsChecker {
  /// 匹配常见时间段写法：08:00-08:45 / 8:00~8:45 / 08:00–08:45 / 08:00—08:45 / 08:00至08:45
  static final RegExp _timeRangeReg = RegExp(
    r'(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~～–—至]\s*(\d{1,2})\s*[:：]\s*(\d{2})',
  );

  /// 匹配节次编号：第1节 / 1节 / 01 / 1
  static final RegExp _sectionReg = RegExp(r'第?\s*(\d{1,2})\s*节?');

  /// 裸节次标签：整行只有节次号或节次区间（如「3」「第3节」「1-2」），不含时间
  static final RegExp _bareSectionReg = RegExp(r'^\s*第?\s*(\d{1,2})\s*节?\s*$');
  static final RegExp _bareRangeReg =
      RegExp(r'^\s*(\d{1,2})\s*[-~–—]\s*(\d{1,2})\s*$');

  /// 按优先级选择第一份非空作息来源：
  /// 1. 教务网页节次栏直接读到的时间
  /// 2. schools.json 预设 timeSlots（兜底）
  /// 3. OCR 图片识别出的节次栏时间
  /// 返回 null 表示全空；永不返回空列表（调用方用 `== null` 判断即可，
  /// 再加 `isEmpty` 只是防御性判断）。
  static List<TimeSlot>? pickPreferredSlots({
    List<TimeSlot>? fromWebPage,
    List<TimeSlot>? fromSchoolPreset,
    List<TimeSlot>? fromOcr,
  }) {
    if (fromWebPage != null && fromWebPage.isNotEmpty) return fromWebPage;
    if (fromSchoolPreset != null && fromSchoolPreset.isNotEmpty) {
      return fromSchoolPreset;
    }
    if (fromOcr != null && fromOcr.isNotEmpty) return fromOcr;
    return null;
  }

  /// 从教务页节次栏单元格文本列表（或 OCR 节次栏行文本列表）中抽取每节起止时间
  /// 兼容正方 / 强智 / 金智常见写法，如：
  /// - "1\n08:00-08:45"
  /// - "第1节 08:00~08:45"
  /// - "08:00-08:45"（无节次号时按行序顺延）
  ///
  /// 落盘补记（Neon 原文没有）：无时间的行若本身就是裸节次标签（「3」「第3节」
  /// 「1-2」），把顺延基准推到它之后——否则后一行只有时间没编号时会顺延错位
  /// （与 web_schedule_parser 里行首标签定 rowStart 的口径对齐）。
  static List<TimeSlot> extractFromSectionTexts(List<String> rawTexts) {
    final bySection = <int, TimeSlot>{};
    var fallbackSection = 1;

    for (final raw in rawTexts) {
      final text = raw.trim();
      if (text.isEmpty) continue;

      final timeMatch = _timeRangeReg.firstMatch(text);
      if (timeMatch == null) {
        final bare = _bareSectionReg.firstMatch(text);
        if (bare != null) {
          final n = int.tryParse(bare.group(1)!);
          if (n != null && n >= fallbackSection) fallbackSection = n + 1;
          continue;
        }
        final range = _bareRangeReg.firstMatch(text);
        if (range != null) {
          final n = int.tryParse(range.group(2)!);
          if (n != null && n >= fallbackSection) fallbackSection = n + 1;
        }
        continue;
      }

      final start = _normalizeTime(timeMatch.group(1)!, timeMatch.group(2)!);
      final end = _normalizeTime(timeMatch.group(3)!, timeMatch.group(4)!);
      if (start == null || end == null) continue;
      if (_toMinutes(start) >= _toMinutes(end)) continue;

      // 在时间段之前的文本里优先找节次号，避免把时间里的数字当节次
      final prefix = text.substring(0, timeMatch.start);
      final secMatch = _sectionReg.firstMatch(prefix);
      final section = secMatch != null
          ? int.tryParse(secMatch.group(1)!) ?? fallbackSection
          : fallbackSection;

      if (section > 0 && section <= 20) {
        bySection[section] = TimeSlot(
          section: section,
          startTime: start,
          endTime: end,
        );
        fallbackSection = section + 1;
      }
    }

    final result = bySection.values.toList()
      ..sort((a, b) => a.section.compareTo(b.section));
    return result;
  }

  /// 松散文本里的节次时间行：行首就是节次标记，其后跟时间段。
  /// 区间形式必须带「节」字（第1节 / 1节 / 1-2节）：裸「1-2 08:00-09:35」
  /// 很可能是周次范围行，误认成第 1 节；裸数字（1 08:00-08:45）是独立
  /// 节次表常见的「编号 时间」行，保留，且数字与时间之间必须有空白分隔——
  /// 否则「08:00-08:45」会被拆成「0 号 + 8:00」误认成显式行。
  /// 带「节」字的标记与时间段之间允许没有空格（单元格 innerText 常丢空格）。
  static final RegExp _looseSectionTimeReg = RegExp(
    r'^\s*(?:第?\s*(\d{1,2})\s*(?:[-~–—]\s*(\d{1,2})\s*)?节\s*|(\d{1,2})\s+)'
    r'(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~～–—至]\s*(\d{1,2})\s*[:：]\s*(\d{2})',
  );

  /// 松散文本里整行只有一个时间段的行。
  static final RegExp _looseBareTimeReg = RegExp(
    r'^\s*(\d{1,2})\s*[:：]\s*(\d{2})\s*[-~～–—至]\s*(\d{1,2})\s*[:：]\s*(\d{2})\s*$',
  );

  /// 从松散文本（独立节次时间表、页面全文）里抽节次时间。
  ///
  /// 只认两种行：(1) 行首就是节次标记（第 X 节 / X / X-Y节）其后跟时间段；
  /// (2) 整行只有一个时间段。其余含时间的行一律不要，如「办公时间
  /// 08:00-12:00」、课程条目「高等数学 1-2节 08:00-09:35 周一」——行首
  /// 不是节次标记的含时间行很可能是课程或通知，把它的时间段当成某节
  /// 作息会认错。无「节」字的周次范围行「1-2 08:00-09:35」也不要。
  ///
  /// 「X-Y节 时间段」只按现有口径记到 X 节（与主表节次栏同一口径，不展开）。
  ///
  /// 显式行与裸时间段行分开处理：裸行按出现顺序填入显式行未占用的最小
  /// 节次，两类行不再共用顺延计数器——否则跨表/跨段落混排时，裸行会被
  /// 显式行推到错误节次。取舍规则：显式行同一节次以后出现的为准；裸行
  /// 先到先得（填最低空闲节次）。
  static List<TimeSlot> extractFromLooseTexts(List<String> rawTexts) {
    final explicit = <String>[];
    final bare = <String>[];
    for (final raw in rawTexts) {
      if (raw.trim().isEmpty) continue;
      if (_looseSectionTimeReg.hasMatch(raw)) {
        explicit.add(raw);
      } else if (_looseBareTimeReg.hasMatch(raw)) {
        bare.add(raw);
      }
    }
    final bySection = <int, TimeSlot>{
      for (final s in extractFromSectionTexts(explicit)) s.section: s,
    };
    // 裸时间段行：按出现顺序填入显式行未占用的最小节次。
    final bareSlots = extractFromSectionTexts(bare)
      ..sort((a, b) => a.section.compareTo(b.section));
    var next = 1;
    for (final s in bareSlots) {
      while (bySection.containsKey(next)) {
        next++;
      }
      if (next > 20) break;
      bySection[next] = TimeSlot(
        section: next,
        startTime: s.startTime,
        endTime: s.endTime,
      );
      next++;
    }
    final result = bySection.values.toList()
      ..sort((a, b) => a.section.compareTo(b.section));
    return result;
  }

  /// 比对读到的学校作息与目标学期现有作息
  /// - [incoming] 不完整时（如只有 1–8 节），只比对已有的节次，其余节次保持原样
  static TimeSlotCompareResult compare({
    required List<TimeSlot> current,
    required List<TimeSlot> incoming,
  }) {
    final currentMap = {for (final s in current) s.section: s};
    final incomingMap = {for (final s in incoming) s.section: s};

    final diffs = <TimeSlotDiff>[];
    final sortedIncomingSections = incomingMap.keys.toList()..sort();

    for (final sec in sortedIncomingSections) {
      final inc = incomingMap[sec]!;
      final cur = currentMap[sec];
      if (cur == null ||
          cur.startTime != inc.startTime ||
          cur.endTime != inc.endTime) {
        diffs.add(
          TimeSlotDiff(
            section: sec,
            currentRange:
                cur == null ? '未设置' : '${cur.startTime}-${cur.endTime}',
            incomingRange: '${inc.startTime}-${inc.endTime}',
          ),
        );
      }
    }

    // 合并：已读到的节次用 incoming 覆盖，未读到的节次保留 current
    final mergedMap = <int, TimeSlot>{...currentMap, ...incomingMap};
    final merged = mergedMap.values.toList()
      ..sort((a, b) => a.section.compareTo(b.section));

    final breakBands = inferBreakBands(merged);

    return TimeSlotCompareResult(
      hasDifference: diffs.isNotEmpty,
      diffs: diffs,
      mergedSlots: merged,
      breakBands: breakBands,
    );
  }

  /// §8 午间/晚间带子推算：
  /// 午间 = 上午最后一节下课（< 13:00）→ 下午第一节上课（>= 13:00），空档 >= 45 分钟
  /// 晚间 = 下午最后一节下课（< 18:30）→ 晚上第一节上课（>= 18:00），空档 >= 45 分钟
  /// 没有明显空档时对应字段为 null（保持原样，用户手动调）
  static BreakBandSuggestion inferBreakBands(List<TimeSlot> slots) {
    if (slots.length < 2) return const BreakBandSuggestion();

    final sorted = [...slots]..sort((a, b) => a.section.compareTo(b.section));

    int? lunchAfter;
    String? lunchStart;
    String? lunchEnd;

    int? dinnerAfter;
    String? dinnerStart;
    String? dinnerEnd;

    const minGapMinutes = 45;

    for (var i = 0; i < sorted.length - 1; i++) {
      final prev = sorted[i];
      final next = sorted[i + 1];
      // 只在连续节次间推算空档
      if (next.section != prev.section + 1) continue;

      final prevEndMin = _toMinutes(prev.endTime);
      final nextStartMin = _toMinutes(next.startTime);
      final gap = nextStartMin - prevEndMin;
      if (gap < minGapMinutes) continue;

      // 午间空档：前一节 11:00~13:00 之间结束，后一节 13:00~15:00 之间开始
      if (lunchAfter == null &&
          prevEndMin >= 11 * 60 &&
          prevEndMin <= 13 * 60 &&
          nextStartMin >= 13 * 60 &&
          nextStartMin <= 15 * 60) {
        lunchAfter = prev.section;
        lunchStart = prev.endTime;
        lunchEnd = next.startTime;
        continue;
      }

      // 晚间空档：前一节 16:00~18:30 之间结束，后一节 18:00~20:30 之间开始
      if (dinnerAfter == null &&
          prevEndMin >= 16 * 60 &&
          prevEndMin <= 18 * 60 + 30 &&
          nextStartMin >= 18 * 60 &&
          nextStartMin <= 20 * 60 + 30) {
        dinnerAfter = prev.section;
        dinnerStart = prev.endTime;
        dinnerEnd = next.startTime;
      }
    }

    return BreakBandSuggestion(
      lunchAfterSection: lunchAfter,
      lunchStart: lunchStart,
      lunchEnd: lunchEnd,
      dinnerAfterSection: dinnerAfter,
      dinnerStart: dinnerStart,
      dinnerEnd: dinnerEnd,
    );
  }

  static String? _normalizeTime(String rawH, String rawM) {
    final h = int.tryParse(rawH);
    final m = int.tryParse(rawM);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static int _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}
