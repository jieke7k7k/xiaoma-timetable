import '../database/dao.dart';
import '../models/course.dart';
import '../models/note.dart';
import '../models/operation_log.dart';
import '../utils/conflict_detector.dart';
import '../utils/morandi_palette.dart';
import '../utils/note_notice.dart';
import '../utils/week_parser.dart';

/// 指令来源（2.0.5 第 4 节·撤回）：AI 与 AI 桥都走同一份执行器，
/// 执行成功且带来源时才落操作记录（供「撤回」用）。不传来源的调用
/// （如旧单测、纯计算）只执行不记录，行为与之前完全一致。
enum CommandSource { ai, bridge }

/// 结构化指令执行器（地基层：本轮不接网络、不接 AI）
///
/// 输入是结构化指令 Map（含 `type` 字段），逐条执行并返回每条的结果——
/// 后续「AI 桥」（外部模型返回指令串）与「内置 AI」都落在这同一份执行器上，
/// 两侧共用一套参数校验、冲突检测与 destructive 标记，避免语义漂移。
///
/// **调用方约定（重要）**：本类只依赖数据层（Dao），**不依赖 Riverpod /
/// BuildContext**，也不做任何 UI 动作。执行完成后：
/// - Provider 刷新（如 ref.invalidate(coursesProvider)）；
/// - 通知重排（NotificationService.instance.rescheduleAll()）；
/// - 备注常驻通知刷新（NotificationService.instance.refreshNoteNotice()）；
/// - 桌面小部件刷新（WidgetService.instance.refreshWidgets()）；
/// 全部由调用方负责。这样本类可以在纯 Dart 环境（单测、后台 isolate、AI 桥）
/// 里直接用，也让「一次批量指令只刷新一遍」成为可能。
///
/// 一期指令集见 [CommandRegistry]：add_course / set_course_color /
/// add_note / delete_note / add_exam。每条指令的 destructive 标记集中登记
/// 在注册表里，供后续桥的确认策略读取（删除类为 true，其余 false）。
///
/// 容错口径：单条指令参数缺失/非法时**该条失败并给出中文原因**，
/// 绝不抛异常中断整批——批里第 3 条出错不影响第 4 条继续执行，
/// 与「导入有冲突不阻断」是一致的产品口径。
class CommandExecutor {
  CommandExecutor();

  final Dao _dao = Dao.instance;

  /// 指令执行结果
  ///
  /// [success] 为 false 时 [message] 是可直接展示给用户/模型的中文原因。
  CommandResult _failure(String type, String message) => CommandResult(
        type: type,
        success: false,
        message: message,
        destructive: CommandRegistry.destructiveOf(type),
      );

  /// 执行一批指令，逐条返回结果（顺序与入参一致）。
  /// [source] 非空时，每条成功执行的改数据指令会落一条操作记录（可撤回）。
  Future<List<CommandResult>> executeAll(
    List<Map<String, dynamic>> commands, {
    CommandSource? source,
  }) async {
    final results = <CommandResult>[];
    for (final command in commands) {
      results.add(await execute(command, source: source));
    }
    return results;
  }

  /// 执行单条指令。任何异常都在这里被兜成失败结果，不会向上抛。
  /// [source] 非空时，成功执行的改数据指令会落一条操作记录（可撤回）。
  Future<CommandResult> execute(
    Map<String, dynamic> command, {
    CommandSource? source,
  }) async {
    final rawType = command['type'];
    if (rawType is! String || rawType.trim().isEmpty) {
      return const CommandResult(
        type: '未知指令',
        success: false,
        message: '缺少指令类型（type）',
        destructive: false,
      );
    }
    final type = rawType.trim();
    if (!CommandRegistry.contains(type)) {
      return CommandResult(
        type: type,
        success: false,
        message: '不支持的指令类型：$type'
            '（当前支持：${CommandRegistry.supportedTypes.join('、')}）',
        destructive: false,
      );
    }

    try {
      switch (type) {
        case 'add_course':
          return await _addCourse(command, source);
        case 'set_course_color':
          return await _setCourseColor(command, source);
        case 'set_course_remark':
          return await _setCourseRemark(command, source);
        case 'add_note':
          return await _addNote(command, source);
        case 'delete_note':
          return await _deleteNote(command, source);
        case 'add_exam':
          return await _addExam(command, source);
        default:
          return _failure(type, '不支持的指令类型：$type');
      }
    } on _CommandError catch (e) {
      return _failure(type, e.message);
    } catch (e) {
      // 兜住一切例外（含 Dao 抛的中文异常），保证整批不被中断
      return _failure(type, '执行失败：$e');
    }
  }

  // ---------- 各指令实现 ----------

  /// add_course：按课程全字段新增到当前学期。
  /// 落库前做冲突检测，**冲突只作为结果提示，不拦截入库**（与手动建课同口径）。
  Future<CommandResult> _addCourse(
    Map<String, dynamic> cmd,
    CommandSource? source,
  ) async {
    const type = 'add_course';
    final semester = await _dao.getCurrentSemester();
    if (semester == null || semester.id == null) {
      throw const _CommandError('还没有当前学期，无法新增课程');
    }
    final name = _requireString(cmd, 'name');
    final dayOfWeek = _requireInt(cmd, 'dayOfWeek');
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      throw const _CommandError('dayOfWeek 要在 1~7 之间（周一是 1）');
    }
    final startSection = _requireInt(cmd, 'startSection');
    final endSection = _optionalInt(cmd, 'endSection') ?? startSection;
    if (startSection < 1 || endSection < startSection) {
      throw const _CommandError('节次范围不对，需要满足 1 ≤ startSection ≤ endSection');
    }
    // 周次语义与导入链路一致：字符串走 WeekParser（支持「1-8, 10-16单周」），
    // 数组则直接当周次列表；单双周过滤会被落到 weeks 数组里
    final weeks = _parseWeeksField(cmd['weeks']);
    if (weeks.isEmpty) {
      throw const _CommandError('缺少参数 weeks（周次不能为空）');
    }
    final weekType = _optionalInt(cmd, 'weekType') ?? 0;
    if (weekType < 0 || weekType > 2) {
      throw const _CommandError('weekType 只能是 0（全部）/ 1（单周）/ 2（双周）');
    }
    final colorValue =
        cmd.containsKey('colorValue') || cmd.containsKey('color')
            ? _parseColor(cmd['colorValue'] ?? cmd['color'])
            : MorandiPalette.defaultColor;

    final candidate = Course(
      semesterId: semester.id!,
      name: name,
      teacher: _optionalString(cmd, 'teacher'),
      classroom: _optionalString(cmd, 'classroom'),
      colorValue: colorValue,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
      weekType: weekType,
      note: _optionalString(cmd, 'note'),
    );

    String? warning;
    try {
      final existing = await _dao.getCoursesBySemester(semester.id!);
      final conflicts = ConflictDetector.detect(candidate, existing);
      if (conflicts.isNotEmpty) {
        warning = '注意：与已有课程时间冲突——'
            '${conflicts.map((c) => c.describe()).join('；')}';
      }
    } catch (_) {
      // 冲突检测是「锦上添花」，读库失败不应拦下这次新增
    }

    final id = await _dao.insertCourse(candidate);
    final message = warning == null
        ? '已新增《$name》（周${_weekdayName(dayOfWeek)} 第${_sectionText(startSection, endSection)}节）'
        : '已新增《$name》，但 $warning';
    if (source != null) {
      await _recordOperation(
        source: source,
        summary: message,
        snapshot: {'kind': 'add_course', 'courseId': id},
      );
    }
    return CommandResult(
      type: type,
      success: true,
      message: message,
      destructive: false,
      data: {'courseId': id, 'conflicts': warning != null},
    );
  }

  /// set_course_color：按 courseId 或 courseName 定位（重名多门时批量全改）。
  /// 只改颜色，不动其他字段；找不到目标是失败（避免「静默什么都没做」）。
  Future<CommandResult> _setCourseColor(
    Map<String, dynamic> cmd,
    CommandSource? source,
  ) async {
    const type = 'set_course_color';
    final semester = await _dao.getCurrentSemester();
    if (semester == null || semester.id == null) {
      throw const _CommandError('还没有当前学期，无法修改课程颜色');
    }
    final rawColor = cmd['colorValue'] ?? cmd['color'];
    if (rawColor == null) {
      throw const _CommandError('缺少参数 colorValue（颜色）');
    }
    final colorValue = _parseColor(rawColor);

    final courseId = _optionalInt(cmd, 'courseId');
    final name = _optionalString(cmd, 'courseName');
    if (courseId == null && name == null) {
      throw const _CommandError('缺少定位参数：需要 courseId 或 courseName');
    }
    final all = await _dao.getCoursesBySemester(semester.id!);
    final targets = [
      for (final c in all)
        if (courseId != null && c.id == courseId) c else if (name != null && c.name == name) c,
    ];
    if (targets.isEmpty) {
      throw _CommandError(
        courseId != null
            ? '当前学期没有 id 为 $courseId 的课程'
            : '当前学期没有名为《$name》的课程',
      );
    }
    for (final c in targets) {
      await _dao.updateCourse(c.copyWith(colorValue: colorValue));
    }
    final first = targets.first;
    final message = targets.length == 1
        ? '已把《${first.name}》的颜色改为 ${_colorText(colorValue)}'
        : '已把 ${targets.length} 门同名课程《${first.name}》的颜色'
            '改为 ${_colorText(colorValue)}';
    if (source != null) {
      await _recordOperation(
        source: source,
        summary: message,
        snapshot: {
          'kind': 'set_course_color',
          'courses': [
            for (final c in targets)
              {'courseId': c.id, 'oldColorValue': c.colorValue},
          ],
        },
      );
    }
    return CommandResult(
      type: type,
      success: true,
      message: message,
      destructive: false,
      data: {'changedCount': targets.length},
    );
  }

  /// set_course_remark（2.0.5 第 2 节）：把课程的 `note` 字段（课程备注）设为
  /// remark，空字符串 = 清除备注。定位逻辑与 set_course_color / add_exam 同款：
  /// courseId 优先，否则按 courseName 精确匹配，同名课程批量全改。
  Future<CommandResult> _setCourseRemark(
    Map<String, dynamic> cmd,
    CommandSource? source,
  ) async {
    const type = 'set_course_remark';
    final semester = await _dao.getCurrentSemester();
    if (semester == null || semester.id == null) {
      throw const _CommandError('还没有当前学期，无法修改课程备注');
    }
    // 不能用 _optionalString：空字符串是「清除备注」的合法值，会被它误判成 null
    final rawRemark = cmd['remark'];
    if (rawRemark == null) {
      throw const _CommandError('缺少参数 remark（课程备注内容，空字符串表示清除）');
    }
    final remark = rawRemark.toString().trim();

    final courseId = _optionalInt(cmd, 'courseId');
    final name = _optionalString(cmd, 'courseName');
    if (courseId == null && name == null) {
      throw const _CommandError('缺少定位参数：需要 courseId 或 courseName');
    }
    final all = await _dao.getCoursesBySemester(semester.id!);
    final targets = [
      for (final c in all)
        if (courseId != null && c.id == courseId) c else if (name != null && c.name == name) c,
    ];
    if (targets.isEmpty) {
      throw _CommandError(
        courseId != null
            ? '当前学期没有 id 为 $courseId 的课程'
            : '当前学期没有名为《$name》的课程',
      );
    }
    // copyWith 用 ?? 合并、传 null 清不掉 note，所以用整对象重建（与 _addExam 同口径）
    for (final c in targets) {
      await _dao.updateCourse(
        c.withMutableFields(
          colorValue: c.colorValue,
          note: remark.isEmpty ? null : remark,
          examDate: c.examDate,
        ),
      );
    }
    final first = targets.first;
    final message = targets.length == 1
        ? (remark.isEmpty
            ? '已清除《${first.name}》的课程备注'
            : '已把《${first.name}》的课程备注改为：$remark')
        : (remark.isEmpty
            ? '已清除 ${targets.length} 门同名课程《${first.name}》的课程备注'
            : '已把 ${targets.length} 门同名课程《${first.name}》的课程备注改为：$remark');
    if (source != null) {
      await _recordOperation(
        source: source,
        summary: message,
        snapshot: {
          'kind': 'set_course_remark',
          'courses': [
            for (final c in targets) {'courseId': c.id, 'oldNote': c.note},
          ],
        },
      );
    }
    return CommandResult(
      type: type,
      success: true,
      message: message,
      destructive: false,
      data: {'changedCount': targets.length},
    );
  }

  /// add_note：date（默认今天）+ content 新增备注
  Future<CommandResult> _addNote(
    Map<String, dynamic> cmd,
    CommandSource? source,
  ) async {
    const type = 'add_note';
    final content = _requireString(cmd, 'content');
    final rawDate = _optionalString(cmd, 'date');
    final dateKey = rawDate == null
        ? noteDayKey(DateTime.now())
        : _normalizeDateKey(rawDate);
    final id = await _dao.insertNote(Note(
      date: dateKey,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    final message = '已新增 $dateKey 的备注：$content';
    if (source != null) {
      await _recordOperation(
        source: source,
        summary: message,
        snapshot: {'kind': 'add_note', 'noteId': id},
      );
    }
    return CommandResult(
      type: type,
      success: true,
      message: message,
      destructive: false,
      data: {'noteId': id, 'date': dateKey},
    );
  }

  /// delete_note：按 id，或按 date（+ 可选 content 关键词）删除（destructive=true）。
  ///
  /// 2.0.5 第 2 节扩展：除原有按 id 删除外，支持按日期定位、按「日期 + 内容关键词」
  /// 定位删除当天备注；命中多条时全部删除并在结果里报删了几条；定位不到时给中文
  /// 原因，不再报「缺少参数 id」这种死胡同。
  Future<CommandResult> _deleteNote(
    Map<String, dynamic> cmd,
    CommandSource? source,
  ) async {
    const type = 'delete_note';
    final id = _optionalInt(cmd, 'id') ?? _optionalInt(cmd, 'noteId');
    final rawDate = _optionalString(cmd, 'date');
    final keyword =
        _optionalString(cmd, 'content') ?? _optionalString(cmd, 'keyword');

    final List<Note> targets;
    if (id != null) {
      // 按 id：先读全文（为撤回留快照），读不到才报「找不到」
      final all = await _dao.getAllNotes();
      final found = [for (final n in all) if (n.id == id) n];
      if (found.isEmpty) {
        throw _CommandError('找不到 id 为 $id 的备注，可能已经删除过了');
      }
      targets = found;
    } else if (rawDate != null) {
      final dateKey = _normalizeDateKey(rawDate);
      final dayNotes = await _dao.getNotesByDate(dateKey);
      targets = [
        for (final n in dayNotes)
          if (keyword == null || n.content.contains(keyword)) n,
      ];
      if (targets.isEmpty) {
        throw _CommandError(
          keyword == null
              ? '没有 $dateKey 的备注，无法删除'
              : '没有 $dateKey 里包含「$keyword」的备注，无法删除',
        );
      }
    } else {
      throw const _CommandError('缺少定位参数：需要 id，或 date（可再配 content 关键词）');
    }

    for (final n in targets) {
      await _dao.deleteNote(n.id!);
    }
    final String message;
    if (targets.length == 1) {
      final n = targets.first;
      message = '已删除备注（${n.date} ${n.content}）';
    } else {
      message = '已删除 ${targets.length} 条备注';
    }
    if (source != null) {
      await _recordOperation(
        source: source,
        summary: message,
        snapshot: {
          'kind': 'delete_note',
          'notes': [for (final n in targets) n.toMap()],
        },
      );
    }
    return CommandResult(
      type: type,
      success: true,
      message: message,
      destructive: true,
      data: {
        'deletedCount': targets.length,
        'noteIds': [for (final n in targets) n.id],
      },
    );
  }

  /// add_exam：给指定课程设置考试日期。
  ///
  /// 说明：仓库目前没有独立的 exams 表，考试的载体是 Course.examDate
  /// （毫秒时间戳，课程编辑页与考试倒计时页的数据源），因此本指令的字段
  /// 对齐的就是这个模型——先按 courseId / courseName 定位课程，再写 examDate。
  /// 将来若拆出独立考试表，这里改落库目标即可，指令签名不用动。
  Future<CommandResult> _addExam(
    Map<String, dynamic> cmd,
    CommandSource? source,
  ) async {
    const type = 'add_exam';
    final semester = await _dao.getCurrentSemester();
    if (semester == null || semester.id == null) {
      throw const _CommandError('还没有当前学期，无法设置考试日期');
    }
    final courseId = _optionalInt(cmd, 'courseId');
    final name = _optionalString(cmd, 'courseName');
    if (courseId == null && name == null) {
      throw const _CommandError('缺少定位参数：需要 courseId 或 courseName');
    }
    final all = await _dao.getCoursesBySemester(semester.id!);
    final matches = [
      for (final c in all)
        if (courseId != null && c.id == courseId) c else if (name != null && c.name == name) c,
    ];
    if (matches.isEmpty) {
      throw _CommandError(
        courseId != null
            ? '当前学期没有 id 为 $courseId 的课程'
            : '当前学期没有名为《$name》的课程',
      );
    }

    final rawDate = _optionalString(cmd, 'date');
    final int? examDate;
    if (rawDate == null) {
      if (cmd['examDate'] == null) {
        throw const _CommandError('缺少参数 date（考试日期，yyyy-MM-dd）');
      }
      examDate = _optionalInt(cmd, 'examDate');
    } else {
      final key = _normalizeDateKey(rawDate);
      final parts = key.split('-').map(int.parse).toList();
      final time = _optionalString(cmd, 'time');
      final hhmm = time == null ? null : _parseHhmm(time);
      examDate = DateTime(
        parts[0],
        parts[1],
        parts[2],
        hhmm?.$1 ?? 0,
        hhmm?.$2 ?? 0,
      ).millisecondsSinceEpoch;
    }

    if (examDate == null) {
      throw const _CommandError('考试日期不对：examDate 需要是毫秒时间戳');
    }

    // copyWith 的 examDate 用 ?? 合并、传 null 清不掉字段，
    // 因此整对象重建后 updateCourse（与课程编辑页同一处理口径）
    int count = 0;
    for (final c in matches) {
      await _dao.updateCourse(
        c.withMutableFields(
          colorValue: c.colorValue,
          note: c.note,
          examDate: examDate,
        ),
      );
      count++;
    }
    final first = matches.first;
    final dateText = _formatStamp(examDate);
    final String message;
    if (count > 1) {
      message = '已把 $count 门同名课程《${first.name}》的考试日期设为 $dateText';
    } else {
      message = '已把《${first.name}》的考试日期设为 $dateText';
    }
    if (source != null) {
      await _recordOperation(
        source: source,
        summary: message,
        snapshot: {
          'kind': 'add_exam',
          'courses': [
            for (final c in matches)
              {'courseId': c.id, 'oldExamDate': c.examDate},
          ],
        },
      );
    }
    if (count > 1) {
      return CommandResult(
        type: type,
        success: true,
        message: message,
        destructive: false,
        data: {'changedCount': count, 'examDate': examDate},
      );
    }
    return CommandResult(
      type: type,
      success: true,
      message: message,
      destructive: false,
      data: {'courseId': first.id, 'examDate': examDate},
    );
  }

  /// 落一条操作记录（撤回用）。记录本身失败只打日志、不影响指令结果——
  /// 撤回是「锦上添花」，不该因为写不了记录就让一次成功的改数据报错。
  Future<void> _recordOperation({
    required CommandSource source,
    required String summary,
    required Map<String, dynamic> snapshot,
  }) async {
    try {
      await _dao.insertOperationLog(OperationLog(
        createdAt: DateTime.now().millisecondsSinceEpoch,
        source: source.name,
        summary: summary,
        snapshot: snapshot,
      ));
    } catch (_) {
      // 静默：见方法注释
    }
  }

  // ---------- 参数解析辅助 ----------

  static String _requireString(Map<String, dynamic> cmd, String key) {
    final v = cmd[key];
    if (v == null) throw _CommandError('缺少参数 $key');
    final s = v.toString().trim();
    if (s.isEmpty) throw _CommandError('缺少参数 $key');
    return s;
  }

  static String? _optionalString(Map<String, dynamic> cmd, String key) {
    final v = cmd[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int _requireInt(Map<String, dynamic> cmd, String key) {
    final v = _optionalInt(cmd, key);
    if (v == null) throw _CommandError('缺少参数 $key（需要数字）');
    return v;
  }

  static int? _optionalInt(Map<String, dynamic> cmd, String key) {
    final v = cmd[key];
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// 周次字段：数组直接用；字符串走 WeekParser（支持「1-8, 10-16单周」）
  static List<int> _parseWeeksField(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      final weeks = <int>{
        for (final e in raw)
          if (e is int) e else if (e is num) e.round() else int.tryParse('$e') ?? 0,
      }..remove(0);
      final sorted = weeks.toList()..sort();
      return sorted;
    }
    try {
      // WeekParser 支持「1-8, 10-16单周」，单双周语义与导入链路完全一致；
      // 它抛的异常本就带中文原因，转成内部错误后由 execute 兜成失败结果
      return WeekParser.parse(raw.toString()).weeks;
    } on WeekParseException catch (e) {
      throw _CommandError('周次解析失败：${e.message}');
    }
  }

  /// 颜色字段：接受 int（ARGB），也接受 "#RRGGBB" / "AARRGGBB" / "0xAARRGGBB" 字符串
  static int _parseColor(Object? raw) {
    if (raw is int) return raw;
    var s = raw.toString().trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.length == 6) s = 'FF$s';
    final v = int.tryParse(s, radix: 16);
    if (v == null) throw const _CommandError('颜色格式不对，可用 #RRGGBB 或 0xAARRGGBB');
    return v;
  }

  /// 日期字段归一化成 yyyy-MM-dd（接受 yyyy/MM/dd、yyyy-M-d 等常见写法）
  static String _normalizeDateKey(String raw) {
    final s = raw.trim().replaceAll('/', '-');
    final parsed = DateTime.tryParse(s);
    if (parsed == null) {
      throw _CommandError('日期格式不对：$raw（应为 yyyy-MM-dd）');
    }
    return '${parsed.year.toString().padLeft(4, '0')}'
        '-${parsed.month.toString().padLeft(2, '0')}'
        '-${parsed.day.toString().padLeft(2, '0')}';
  }

  /// "HH:mm" → (时, 分)
  static (int, int)? _parseHhmm(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) throw _CommandError('时间格式不对：$raw（应为 HH:mm）');
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) throw _CommandError('时间超范围：$raw');
    return (h, min);
  }

  /// 毫秒时间戳 → 「yyyy年M月d日」；带时刻时补「 HH:mm」
  static String _formatStamp(int stamp) {
    final t = DateTime.fromMillisecondsSinceEpoch(stamp);
    final date = '${t.year}年${t.month}月${t.day}日';
    if (t.hour == 0 && t.minute == 0) return date;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }

  static String _sectionText(int start, int end) =>
      start == end ? '$start' : '$start-$end';

  static const _weekdayNames = ['', '一', '二', '三', '四', '五', '六', '日'];

  static String _weekdayName(int dayOfWeek) =>
      (dayOfWeek >= 1 && dayOfWeek <= 7) ? _weekdayNames[dayOfWeek] : '$dayOfWeek';

  static String _colorText(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 指令注册表：一期指令集与其 destructive 标记的**唯一登记处**
///
/// 后续 AI 桥在让用户确认之前，先查 [destructiveOf] 决定要不要弹「确认执行」；
/// 新增指令必须在这里登记，否则会被 [CommandExecutor] 判为不支持。
class CommandRegistry {
  CommandRegistry._();

  static const Map<String, bool> _specs = {
    'add_course': false,
    'set_course_color': false,
    'set_course_remark': false,
    'add_note': false,
    'delete_note': true, // 删除类：桥侧必须先确认
    'add_exam': false,
  };

  /// 当前支持的一期指令类型（顺序稳定，用于报错文案）
  static List<String> get supportedTypes => _specs.keys.toList();

  static bool contains(String type) => _specs.containsKey(type);

  /// 该指令是否具有破坏性（删除/覆盖类为 true，其余 false）
  static bool destructiveOf(String type) => _specs[type] ?? false;
}

/// 单条指令的执行结果
class CommandResult {
  const CommandResult({
    required this.type,
    required this.success,
    required this.message,
    required this.destructive,
    this.data,
  });

  final String type;
  final bool success;

  /// 成功摘要 / 失败原因（中文，可直接展示）
  final String message;

  /// 该指令是否具有破坏性（供确认策略读取）
  final bool destructive;

  /// 附加数据（新建记录的 id、批量改动条数等），供调用方做后续联动
  final Map<String, dynamic>? data;
}

/// 指令内部的参数/业务错误：一律被 [CommandExecutor.execute] 兜成失败结果，
/// 不会抛到调用方，也不会中断整批。
class _CommandError implements Exception {
  const _CommandError(this.message);

  final String message;

  @override
  String toString() => message;
}
