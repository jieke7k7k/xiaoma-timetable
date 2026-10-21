import '../models/course.dart';
import 'morandi_palette.dart';
import 'week_parser.dart';

/// 网页课表解析结果（教务导入 1.3.0）
class WebScheduleResult {
  final List<Course> courses;
  final List<String> errors;

  /// 页面里找到的表格数与扫描过的非空单元格数（失败时给用户定位用）
  final int tablesFound;
  final int cellsScanned;

  const WebScheduleResult(
    this.courses,
    this.errors, {
    this.tablesFound = 0,
    this.cellsScanned = 0,
  });
}

/// 教务网页课表解析器
///
/// 输入是 WebView 注入脚本回传的页面表格结构（见 web_import_page 的抓取脚本）：
/// `{tables: [{rows: [[{t, rs, cs}, ...], ...]}]}`。
/// 思路与 WakeUp 等主流课表软件一致：定位含「星期一…星期日」表头的表格，
/// 列→星期、行→节次，结合单元格文本里的「(3-4节)1-16周 地点 教师」解析课程。
/// 单元格文本按行状态机切分多门课；解析不准的条目交给核对页人工修正，
/// 这里只保证「认得出的尽量认对，认不出的明确计数」。
class WebScheduleParser {
  WebScheduleParser._();

  static final _weekdayNames = <String, int>{
    '星期一': 1,
    '周一': 1,
    '星期二': 2,
    '周二': 2,
    '星期三': 3,
    '周三': 3,
    '星期四': 4,
    '周四': 4,
    '星期五': 5,
    '周五': 5,
    '星期六': 6,
    '周六': 6,
    '星期日': 7,
    '周日': 7,
    '星期天': 7,
    '周天': 7,
  };

  static final _weekRangeRe = RegExp(r'(\d+)\s*[-~–—]\s*(\d+)\s*周');
  static final _weekSingleRe = RegExp(r'(?<![-\d])(\d+)\s*周');
  static final _sectionRe = RegExp(
    r'[（(]?\s*(\d+)\s*[-~–—]\s*(\d+)\s*节\s*[)）]?',
  );
  static final _sectionSingleRe = RegExp(r'第\s*(\d+)\s*节');
  static final _teacherRe = RegExp(
    r'([\u4e00-\u9fa5]{2,4})\s*(?:[（(][^）)]*[)）])?\s*$',
  );

  static WebScheduleResult parse(
    Map<String, dynamic> payload, {
    required int semesterId,
    int totalWeeks = 30,
  }) {
    final tables = (payload['tables'] as List?) ?? const [];
    final courses = <Course>[];
    final errors = <String>[];
    var cellsScanned = 0;
    final seen = <String>{};

    for (final t in tables) {
      final rowsRaw = (t as Map)['rows'] as List?;
      if (rowsRaw == null || rowsRaw.length < 3) continue;
      final grid = _expand(rowsRaw);
      if (grid.isEmpty) continue;

      // 定位表头行：含 ≥4 个星期名的行
      var headerRow = -1;
      var colWeekday = <int, int>{};
      for (var r = 0; r < grid.length && r < 4; r++) {
        final map = <int, int>{};
        for (var c = 0; c < grid[r].length; c++) {
          final wd = _weekdayNames[grid[r][c].trim()];
          if (wd != null) map[c] = wd;
        }
        if (map.length >= 4) {
          headerRow = r;
          colWeekday = map;
          break;
        }
      }
      if (headerRow < 0) continue;

      // 逐行推进节次：行首标签给出显式节次时优先，否则顺序递增
      var nextSection = 1;
      for (var r = headerRow + 1; r < grid.length; r++) {
        final row = grid[r];
        var rowStart = nextSection;
        // 行首（星期列之前）的标签：如「1」「1-2」「第3节」「08:00-08:40」
        final labelText = <String>[
          for (var c = 0; c < row.length; c++)
            if (!colWeekday.containsKey(c)) row[c],
        ].join(' ');
        final lm = RegExp(r'(\d+)\s*[-~–—]\s*(\d+)').firstMatch(labelText);
        final ls = RegExp(r'^\s*(\d+)\s*$').firstMatch(labelText.trim());
        if (lm != null &&
            !labelText.contains(':') &&
            !labelText.contains('：')) {
          rowStart = int.parse(lm.group(1)!);
          nextSection = int.parse(lm.group(2)!) + 1;
        } else if (ls != null) {
          rowStart = int.parse(ls.group(1)!);
          nextSection = rowStart + 1;
        } else {
          nextSection = rowStart + 1;
        }

        colWeekday.forEach((col, weekday) {
          if (col >= row.length) return;
          final cell = row[col];
          if (cell.trim().isEmpty) return;
          cellsScanned++;
          final blocks = _splitBlocks(cell);
          for (final b in blocks) {
            final course = _blockToCourse(
              b,
              weekday: weekday,
              rowStart: rowStart,
              semesterId: semesterId,
              totalWeeks: totalWeeks,
              colorIndex: courses.length,
            );
            if (course == null) {
              if (b.name.isNotEmpty) {
                errors.add('「${b.name}」缺少周次信息，已跳过');
              }
              continue;
            }
            final key =
                '${course.name}|${course.dayOfWeek}|${course.startSection}|${course.endSection}|${course.weeks}';
            if (seen.add(key)) courses.add(course);
          }
        });
      }
    }
    return WebScheduleResult(
      courses,
      errors,
      tablesFound: tables.length,
      cellsScanned: cellsScanned,
    );
  }

  /// 展开 rowspan/colspan 为逻辑网格（每个逻辑格都是文本）
  static List<List<String>> _expand(List rowsRaw) {
    final grid = <List<String>>[];
    final carry = <int, Map<int, String>>{}; // row -> col -> text（跨行占用）
    for (var r = 0; r < rowsRaw.length; r++) {
      final row = <String>[];
      final cells = rowsRaw[r] as List;
      var c = 0;
      void fillCarried() {
        while (carry[r]?.containsKey(c) ?? false) {
          row.add(carry[r]![c]!);
          c++;
        }
      }

      for (final cellRaw in cells) {
        fillCarried();
        final m = cellRaw as Map;
        final text = (m['t'] as String?) ?? '';
        final rs = (m['rs'] as num?)?.toInt() ?? 1;
        final cs = (m['cs'] as num?)?.toInt() ?? 1;
        for (var k = 0; k < cs; k++) {
          row.add(text);
          if (rs > 1) {
            for (var dr = 1; dr < rs; dr++) {
              carry.putIfAbsent(r + dr, () => {})[c] = text;
            }
          }
          c++;
        }
      }
      fillCarried();
      grid.add(row);
    }
    // 对齐列数
    final width = grid.fold<int>(0, (a, r) => r.length > a ? r.length : a);
    for (final row in grid) {
      while (row.length < width) {
        row.add('');
      }
    }
    return grid;
  }

  /// 单元格文本 → 课程块：行状态机切分（一格多课时按「课名行+详情行」分组）
  static List<_Block> _splitBlocks(String cellText) {
    final lines = cellText
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final blocks = <_Block>[];
    _Block? cur;
    final pendingFields = <String>[];

    void flush() {
      if (cur != null) {
        cur!.fields.addAll(pendingFields);
        pendingFields.clear();
        blocks.add(cur!);
        cur = null;
      }
    }

    for (final line in lines) {
      final isDetail =
          _weekRangeRe.hasMatch(line) || _weekSingleRe.hasMatch(line);
      final isSectionOnly = !isDetail && _sectionRe.hasMatch(line);
      if (isDetail || isSectionOnly) {
        if (cur != null && cur!.hasDetail && pendingFields.isNotEmpty) {
          // 上一门课已完整：pending 的最后一行是新课名，其余归上一门课
          final name = pendingFields.removeLast();
          cur!.fields.addAll(pendingFields);
          pendingFields.clear();
          blocks.add(cur!);
          cur = _Block(name)..details.add(line);
        } else {
          cur ??= _Block('');
          cur!.details.add(line);
        }
      } else {
        // 字段行：可能是课名、地点或教师
        if (cur == null) {
          cur = _Block(line);
        } else if (!cur!.hasDetail && cur!.name.isEmpty) {
          cur!.name = line;
        } else if (!cur!.hasDetail) {
          cur!.fields.add(line);
        } else {
          pendingFields.add(line);
        }
      }
    }
    flush();
    return blocks;
  }

  static Course? _blockToCourse(
    _Block b, {
    required int weekday,
    required int rowStart,
    required int semesterId,
    required int totalWeeks,
    required int colorIndex,
  }) {
    final detailText = b.details.join(' ');
    if (detailText.isEmpty) return null;

    // 节次：文本里的 (N-M节) 优先，其次行位置推断
    int? start, end;
    final sm = _sectionRe.firstMatch(detailText.replaceAll('周', ''));
    if (sm != null && detailText.contains('节')) {
      start = int.parse(sm.group(1)!);
      end = int.parse(sm.group(2)!);
    } else {
      final ss = _sectionSingleRe.firstMatch(detailText);
      if (ss != null) {
        start = end = int.parse(ss.group(1)!);
      }
    }
    start ??= rowStart;
    end ??= start;

    // 周次：所有「N-M周」与单周，带单/双后缀
    final weekParts = <String>[];
    final parityOdd =
        detailText.contains('单周') ||
        detailText.contains('(单)') ||
        detailText.contains('（单）');
    final parityEven =
        detailText.contains('双周') ||
        detailText.contains('(双)') ||
        detailText.contains('（双）');
    for (final m in _weekRangeRe.allMatches(detailText)) {
      var p = '${m.group(1)}-${m.group(2)}';
      if (parityOdd) p += '单';
      if (parityEven) p += '双';
      weekParts.add(p);
    }
    if (weekParts.isEmpty) {
      for (final m in _weekSingleRe.allMatches(detailText)) {
        weekParts.add(m.group(1)!);
      }
    }
    if (weekParts.isEmpty) return null;
    List<int> weeks;
    try {
      weeks = WeekParser.parse(weekParts.join(','), maxWeeks: totalWeeks).weeks;
    } catch (_) {
      return null;
    }
    if (weeks.isEmpty) return null;

    // 课名：清掉尾部符号与课程代码
    var name = b.name
        .replaceAll(RegExp(r'[▲△☆★\s]+$'), '')
        .replaceAll(RegExp(r'[-—]\d{4,}$'), '')
        .trim();
    if (name.isEmpty) {
      // 课名可能和详情挤在同一行：取详情行里周次之前的部分兜底
      final head = detailText.split(_weekRangeRe).first;
      name = head
          .replaceAll(_sectionRe, '')
          .replaceAll(RegExp(r'[▲△☆★\s]+$'), '')
          .trim();
    }
    if (name.isEmpty) return null;

    // 地点/教师：详情行周次之后的残余 + 独立字段行
    final restParts = <String>[];
    final after = detailText.split(_weekRangeRe).skip(1).join(' ');
    final afterClean = after
        .replaceAll(_sectionRe, '')
        .replaceAll(RegExp(r'[（(]?(?:单|双)[)）]?'), '')
        .trim();
    if (afterClean.isNotEmpty) restParts.add(afterClean);
    restParts.addAll(b.fields);
    var rest = restParts.join(' ').trim();

    String? teacher;
    final tm = _teacherRe.firstMatch(rest);
    if (tm != null && rest.length > tm.group(1)!.length) {
      final candidate = tm.group(1)!;
      // 地点类词尾不是人名（如「音乐教室」「化学实验室」）
      const placeTails = ['教室', '实验室', '机房', '操场', '体育馆', '报告厅'];
      if (!placeTails.any(candidate.endsWith)) {
        teacher = candidate;
        rest = rest.substring(0, tm.start).trim();
      }
    }
    final classroom = rest.isEmpty ? null : rest;

    return Course(
      semesterId: semesterId,
      name: name,
      teacher: teacher,
      classroom: classroom,
      colorValue:
          MorandiPalette.colors[colorIndex % MorandiPalette.colors.length],
      dayOfWeek: weekday,
      startSection: start,
      endSection: end,
      weeks: weeks,
    );
  }
}

class _Block {
  String name;
  final List<String> details = [];
  final List<String> fields = [];
  _Block(this.name);
  bool get hasDetail => details.isNotEmpty;
}
