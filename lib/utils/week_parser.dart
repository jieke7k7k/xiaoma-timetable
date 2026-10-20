/// 周次文本解析工具
///
/// 支持解析用户输入的简写周次文本，生成周次数组与单双周标记。
/// 输入示例：
///   "1-8, 10-16单周"   -> weeks=[1..8,10,12,14,16], weekType=单周
///   "1-16"             -> weeks=[1..16], weekType=全部
///   "1,3,5,7"          -> weeks=[1,3,5,7], weekType=全部
///   "2-14双周"         -> weeks=[2,4,...,14], weekType=双周
class WeekParser {
  WeekParser._();

  /// weekType 常量（与 Course.weekType 一致）
  static const int allWeeks = 0;
  static const int oddWeek = 1;
  static const int evenWeek = 2;

  /// 解析周次文本
  ///
  /// 返回 [ParsedWeeks]，其中 [weeks] 为排序去重后的周次列表，
  /// [weekType] 恒为全部（0）——单双周语义直接通过区间后缀过滤落到
  /// weeks 数组中（如「1-8, 10-16单周」解析为 [1..8, 10, 12, 14, 16]），
  /// 避免全局单双周标记误伤不带后缀的区间。
  /// 格式非法时抛出 [WeekParseException]（含中文原因，由 UI 层友好提示）。
  static ParsedWeeks parse(String input, {int maxWeeks = 30}) {
    final text = input.trim();
    if (text.isEmpty) {
      throw const WeekParseException('请输入周次，例如 1-16');
    }
    // 统一中文符号，避免用户输入中文逗号/波浪号导致解析失败
    final normalized = text
        .replaceAll('，', ',')
        .replaceAll('~', '-')
        .replaceAll('—', '-')
        .replaceAll('－', '-');

    final weeks = <int>{};
    // 单双周语义直接落到 weeks 数组，不设全局 weekType
    const weekType = allWeeks;

    for (final rawPart in normalized.split(',')) {
      final part = rawPart.trim();
      if (part.isEmpty) continue;

      // 提取区间部分与可选后缀（单周/双周）
      var rangeStr = part;
      var partType = allWeeks;
      if (part.endsWith('单周') || part.endsWith('单')) {
        partType = oddWeek;
        rangeStr = part.substring(0, part.lastIndexOf('单'));
      } else if (part.endsWith('双周') || part.endsWith('双')) {
        partType = evenWeek;
        rangeStr = part.substring(0, part.lastIndexOf('双'));
      }

      rangeStr = rangeStr.trim();
      if (rangeStr.isEmpty) {
        throw WeekParseException('「$part」格式不对，正确写法如 1-16 或 3 或 1-8单周');
      }

      if (rangeStr.contains('-')) {
        // 区间形式：1-8
        final bounds = rangeStr.split('-');
        if (bounds.length != 2) {
          throw WeekParseException('「$rangeStr」不是有效的区间，正确写法如 1-16');
        }
        final start = int.tryParse(bounds[0].trim());
        final end = int.tryParse(bounds[1].trim());
        if (start == null || end == null) {
          throw WeekParseException('「$rangeStr」里只能填数字哦');
        }
        if (start > end) {
          throw WeekParseException('「$rangeStr」起始周比分周还大，写反啦');
        }
        if (start < 1 || end > maxWeeks) {
          throw WeekParseException('周次要在 1~$maxWeeks 之间，「$rangeStr」超范围了');
        }
        for (var w = start; w <= end; w++) {
          if (partType == oddWeek && w.isEven) continue;
          if (partType == evenWeek && w.isOdd) continue;
          weeks.add(w);
        }
      } else {
        // 单周形式：3
        final w = int.tryParse(rangeStr);
        if (w == null) {
          throw WeekParseException('「$rangeStr」不是有效周次，正确写法如 1-16 或 3');
        }
        if (w < 1 || w > maxWeeks) {
          throw WeekParseException('周次要在 1~$maxWeeks 之间，「$rangeStr」超范围了');
        }
        weeks.add(w);
      }
    }

    if (weeks.isEmpty) {
      throw WeekParseException('没解析出任何周次，检查下输入？');
    }
    final sorted = weeks.toList()..sort();
    return ParsedWeeks(weeks: sorted, weekType: weekType);
  }

  /// 把周次数组反向序列化为文本（编辑表单回显用）
  /// 连续区间会合并成 1-16 形式；单双周课程追加「单周/双周」后缀。
  static String toText(List<int> weeks, int weekType) {
    if (weeks.isEmpty) return '';
    final sorted = weeks.toList()..sort();
    final parts = <String>[];
    var start = sorted.first;
    var prev = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final w = sorted[i];
      if (w == prev + 1) {
        prev = w;
        continue;
      }
      parts.add(start == prev ? '$start' : '$start-$prev');
      start = w;
      prev = w;
    }
    parts.add(start == prev ? '$start' : '$start-$prev');
    final body = parts.join(', ');
    if (weekType == oddWeek) return '$body 单周';
    if (weekType == evenWeek) return '$body 双周';
    return body;
  }
}

/// 解析结果
class ParsedWeeks {
  const ParsedWeeks({required this.weeks, required this.weekType});
  final List<int> weeks;
  final int weekType;
}

/// 周次解析异常（message 为可直接展示给用户的中文原因）
class WeekParseException implements Exception {
  const WeekParseException(this.message);
  final String message;

  @override
  String toString() => 'WeekParseException: $message';
}
