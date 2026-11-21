import '../models/time_slot.dart';

/// 课名、地点与格子内时间的纯函数展示格式化工具（WB_SPEC_253 §2 & §3）
/// 供 CourseCard 与整学期导出图（SemesterSingleImageSheet / _SingleMasterCard）
/// 共同调用，确保两处同口径；只改显示文本，不改库里的 Course.name / classroom。
///
/// 注意：全角方括号（U+3010/U+3011）与全角圆括号（U+FF08/U+FF09）在正则里
/// 一律写 \u 转义，不直接写字面量——直接写会被写入链路吞掉（2026-11-22 实测）。
class CourseDisplayFormatter {
  /// 匹配开头的方括号前缀标记，例如：[通识] / [选修]（全角方括号同理）。
  /// 只去方括号，圆括号不动（（上）、（实验）是正常课名成分）。
  /// 字符类里的 [ / ] 一律写 \[ / \]，别写裸 [（易读错，见 P0-1 复审误读）。
  static final RegExp _leadingBracketPrefixReg = RegExp(
    '^(?:\\s*[\\[\\u3010][^\\]\\u3011]+[\\]\\u3011])+\\s*',
  );

  /// 匹配尾部的「N周」后缀（WB_SPEC_253 §2 写死）：
  /// 16周 / 1-16周 / （16周）/ [1-16周] / 第16周。
  static final RegExp _trailingWeeksReg = RegExp(
    '\\s*[\\[\\u3010\\uFF08(]?\\u7B2C?\\d+(-\\d+)?\\u5468[\\]\\u3011\\uFF09)]?\\s*\$',
  );

  /// 匹配课名尾部的源系统符号（与 web_schedule_parser §1 同一套）：
  /// 显示层过滤，老数据不用重新导入就立即干净。
  static final RegExp _trailingSymbolsReg = RegExp(r'[▲△☆★⊙◎○●◆■□※\s]+$');

  /// 匹配地点开头的「…校区」前缀（含常见分隔符），例如：
  /// 「黑石礁校区獐314」→「獐314」。只去开头第一处。
  /// 分隔符按 WB_SPEC_253 §2：空格、-、–、—、:、：、、、，、,（另有 /、·
  /// 是教务常见写法，顺手清；校区在末尾如「獐314校区」时整串被匹配，
  /// 走去空兜底保留原地点）。
  static final RegExp _leadingCampusReg = RegExp(
    r'^.*?校区[\s\-–—:：/·、，,]*',
  );

  /// 格式化课名：仅改变显示文本，不修改库中 Course.name。
  /// 去掉标记后若为空，则回退保留原课名。
  static String formatCourseName(
    String rawName, {
    required bool hideNameMarks,
  }) {
    final trimmed = rawName.trim();
    if (!hideNameMarks || trimmed.isEmpty) return trimmed;

    var result = trimmed;
    result = result.replaceFirst(_leadingBracketPrefixReg, '');
    // 两处叠加要按「符号 → 周 → 符号」的顺序清两遍，缺一不可：
    // 「16周⊙」靠第一次清符号（周回到末尾）再清周；
    // 「课名⊙16周」第一次清不到（⊙ 不在末尾），先清周得到「课名⊙」，
    // 再靠第二次清符号。单测已锁定两种顺序（DeepSeek 复审 P1-4）。
    result = result.replaceAll(_trailingSymbolsReg, '');
    result = result.replaceFirst(_trailingWeeksReg, '');
    result = result.replaceAll(_trailingSymbolsReg, '');
    result = result.trim();

    return result.isEmpty ? trimmed : result;
  }

  /// 格式化上课地点：
  /// 1. [hideCampus] 为 true 时去掉开头的「…校区」前缀；去掉后为空时保留原地点
  /// 2. [showLocationAt] 为 true 且结果非空时，在地点前补上 `@`（避免重复添加）
  static String formatClassroom(
    String? rawClassroom, {
    required bool hideCampus,
    required bool showLocationAt,
  }) {
    final trimmed = rawClassroom?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    var result = trimmed;
    if (hideCampus) {
      final stripped = result.replaceFirst(_leadingCampusReg, '').trim();
      if (stripped.isNotEmpty) {
        result = stripped;
      }
    }

    if (showLocationAt && !result.startsWith('@')) {
      result = '@$result';
    }
    return result;
  }

  /// 根据课程起止节次与目标学期作息列表 [timeSlots]，格式化格子内时间
  /// （如「09:50–10:35」）；多节连堂取首节开始–末节结束。
  /// 作息缺失或任一节次越界时返回空字符串（静默不显示，不崩溃）。
  static String formatCellTime({
    required int startSection,
    required int endSection,
    required List<TimeSlot> timeSlots,
  }) {
    if (timeSlots.isEmpty) return '';

    TimeSlot? startSlot;
    TimeSlot? endSlot;
    for (final slot in timeSlots) {
      if (slot.section == startSection) startSlot = slot;
      if (slot.section == endSection) endSlot = slot;
    }

    if (startSlot == null || endSlot == null) return '';
    return '${startSlot.startTime}–${endSlot.endTime}';
  }
}
