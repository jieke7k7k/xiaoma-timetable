import '../database/dao.dart';
import '../models/course.dart';
import '../models/note.dart';
import '../models/operation_log.dart';

/// 操作记录 + 撤回服务（2.0.5 第 4 节）
///
/// 记录由 [CommandExecutor] 在执行成功且带来源时写入；本服务负责：
/// - 列全部记录（按时间倒序）；
/// - 按记录里的「执行前快照」把数据还原回去，并把记录标记为已撤回。
///
/// 撤回**不走**执行器、不落新记录（防套娃）；还原是「尽力而为」——数据已被
/// 后续操作改动时，能还原的还原、还原不了的给中文提示，绝不抛异常崩掉。
class OperationLogService {
  OperationLogService._();

  static final OperationLogService instance = OperationLogService._();

  Future<List<OperationLog>> list() => Dao.instance.getAllOperationLogs();

  /// 撤回一条操作。成功返回 null；失败/部分失败返回中文原因（可展示）。
  /// 兜底 try/catch：还原过程任何异常都不上抛，返回中文原因让界面提示，绝不崩掉。
  Future<String?> undo(OperationLog log) async {
    try {
      final snapshot = log.snapshot;
      final kind = snapshot['kind'];
      if (kind is! String || kind.isEmpty) {
        return '这条记录没有可用的快照，无法撤回';
      }

      String? partial;
      switch (kind) {
        case 'add_course':
          partial = await _undoAddCourse(snapshot);
          break;
        case 'add_note':
          partial = await _undoAddNote(snapshot);
          break;
        case 'delete_note':
          partial = await _undoDeleteNote(snapshot);
          break;
        case 'set_course_color':
          partial = await _undoCourseFields(snapshot, 'oldColorValue');
          break;
        case 'set_course_remark':
          partial = await _undoCourseFields(snapshot, 'oldNote');
          break;
        case 'add_exam':
          partial = await _undoCourseFields(snapshot, 'oldExamDate');
          break;
        default:
          return '不认识的操作类型「$kind」，无法撤回';
      }

      // 尝试过就算撤回过：标记已撤回，避免同一张卡片永远等着被点
      await Dao.instance.markOperationLogUndone(log.id!);
      return partial;
    } catch (e) {
      return '撤回失败：$e';
    }
  }

  // ---------- 各快照类型的还原 ----------

  /// add_course：撤 = 把新增的课删掉。
  Future<String?> _undoAddCourse(Map<String, dynamic> s) async {
    final id = _intAt(s, 'courseId');
    if (id == null) return '快照缺少课程 id，无法撤回';
    final rows = await Dao.instance.deleteCourse(id);
    return rows == 0 ? '该课程已不存在（可能已被后续操作删除），无需撤回' : null;
  }

  /// add_note：撤 = 把新增的备注删掉。
  Future<String?> _undoAddNote(Map<String, dynamic> s) async {
    final id = _intAt(s, 'noteId');
    if (id == null) return '快照缺少备注 id，无法撤回';
    final rows = await Dao.instance.deleteNote(id);
    return rows == 0 ? '该备注已不存在（可能已被后续操作删除），无需撤回' : null;
  }

  /// delete_note：撤 = 把被删的备注按原样加回来（含原 id）。
  Future<String?> _undoDeleteNote(Map<String, dynamic> s) async {
    final list = s['notes'];
    if (list is! List || list.isEmpty) return '快照缺少被删备注的内容，无法撤回';
    final existingIds = {
      for (final n in await Dao.instance.getAllNotes()) n.id,
    };
    var restored = 0;
    for (final raw in list) {
      if (raw is! Map<String, dynamic>) continue;
      final note = Note.fromMap(raw);
      if (note.id != null && existingIds.contains(note.id)) continue;
      await Dao.instance.insertNote(note);
      restored++;
    }
    return restored == 0 ? '这些备注当前都已存在，无需再恢复' : null;
  }

  /// set_course_color / set_course_remark / add_exam：撤 = 把课程对应字段改回旧值。
  ///
  /// [field] 是快照里课程条目里存的旧值键名。按课程 id 定位当前课程，找到就改回，
  /// 找不到记一条「已不存在」的提示；多门里部分找不到时返回聚合的中文提示。
  Future<String?> _undoCourseFields(
    Map<String, dynamic> s,
    String field,
  ) async {
    final list = s['courses'];
    if (list is! List || list.isEmpty) return '快照缺少课程旧值，无法撤回';
    final all = await Dao.instance.getAllCourses();
    final byId = {for (final c in all) c.id: c};
    final missing = <int>[];
    for (final raw in list) {
      if (raw is! Map<String, dynamic>) continue;
      final courseId = _intAt(raw, 'courseId');
      if (courseId == null) continue;
      final current = byId[courseId];
      if (current == null) {
        missing.add(courseId);
        continue;
      }
      await Dao.instance.updateCourse(_restoreField(current, field, raw));
    }
    if (missing.isEmpty) return null;
    return '有 ${missing.length} 门课程已不存在（id：${missing.join('、')}），其余已还原';
  }

  /// 按旧值重建课程（只覆盖 field 对应的那个字段，其余保持当前值）。
  Course _restoreField(Course c, String field, Map<String, dynamic> raw) {
    switch (field) {
      case 'oldColorValue':
        return c.withMutableFields(
          colorValue: raw['oldColorValue'] as int? ?? c.colorValue,
          note: c.note,
          examDate: c.examDate,
        );
      case 'oldNote':
        return c.withMutableFields(
          colorValue: c.colorValue,
          note: raw['oldNote'] as String?,
          examDate: c.examDate,
        );
      case 'oldExamDate':
        return c.withMutableFields(
          colorValue: c.colorValue,
          note: c.note,
          examDate: raw['oldExamDate'] as int?,
        );
      default:
        return c;
    }
  }

  static int? _intAt(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
