import 'dart:convert';

import '../models/course.dart';
import '../models/note.dart';
import 'morandi_palette.dart';

/// Supabase 云同步的纯函数编解码（2.1.0，WB_SPEC_211）。
///
/// 远程三张表（courses / notes / exams）与本地模型之间的映射、冲突判定、
/// 水位过滤、首次迁移去重，全部是无副作用的纯函数，方便单元测试直接断言。
///
/// **远程 id 规则（第 1 节）**：
/// - courses：`course:<semesterId>:<localId>`
/// - notes：`note:<localId>`
/// - exams：`exam:<semesterId>:<localId>`（一门课最多一行考试镜像）
///
/// 远程表列名是 Supabase 的蛇形命名（semester_id / weeks_json / exam_date_ms…），
/// 本地 SQLite 是驼峰（semesterId / weeksJson / examDate…），映射在下面各自收敛。

/// 课程远程 id：`course:<semesterId>:<localId>`
String courseRemoteId(int semesterId, int localId) =>
    'course:$semesterId:$localId';

/// 备注远程 id：`note:<localId>`
String noteRemoteId(int localId) => 'note:$localId';

/// 考试镜像远程 id：`exam:<semesterId>:<localId>`
String examRemoteId(int semesterId, int localId) =>
    'exam:$semesterId:$localId';

/// 解析 courses 远程 id → (semesterId, localId)；非法返回 null。
(int, int)? parseCourseRemoteId(String id) {
  final parts = id.split(':');
  if (parts.length != 3 || parts[0] != 'course') return null;
  final semesterId = int.tryParse(parts[1]);
  final localId = int.tryParse(parts[2]);
  if (semesterId == null || localId == null) return null;
  return (semesterId, localId);
}

/// 解析 notes 远程 id → localId；非法返回 null。
int? parseNoteRemoteId(String id) {
  final parts = id.split(':');
  if (parts.length != 2 || parts[0] != 'note') return null;
  return int.tryParse(parts[1]);
}

/// Course → 云端 courses 行（蛇形命名）。要求课程已入库（id 非空）。
///
/// 含考试字段：exam_date_ms / exam_end_time / exam_place 与课程一一对应。
Map<String, dynamic> courseToRemoteRow(Course c) => {
      'id': courseRemoteId(c.semesterId, c.id!),
      'semester_id': c.semesterId,
      'name': c.name,
      'teacher': c.teacher,
      'classroom': c.classroom,
      'color_value': c.colorValue,
      'day_of_week': c.dayOfWeek,
      'start_section': c.startSection,
      'end_section': c.endSection,
      'weeks_json': jsonEncode(c.weeks),
      'week_type': c.weekType,
      'note': c.note,
      'exam_date_ms': c.examDate,
      'exam_end_time': c.examEndTime,
      'exam_place': c.examPlace,
    };

/// 云端 courses 行 → Course。
///
/// 本地 id 取远程 id 里的 localId（保证「同 id」幂等），semesterId 同步取远程
/// id 里的学期号；列名从蛇形转回模型字段。行缺 id 或 id 非法时返回 null（跳过）。
Course? courseFromRemoteRow(Map<String, dynamic> row) {
  final id = row['id'];
  if (id is! String) return null;
  final parsed = parseCourseRemoteId(id);
  if (parsed == null) return null;
  final (semesterId, localId) = parsed;
  return Course(
    id: localId,
    semesterId: semesterId,
    name: row['name'] as String? ?? '',
    teacher: row['teacher'] as String?,
    classroom: row['classroom'] as String?,
    colorValue: row['color_value'] as int? ?? MorandiPalette.defaultColor,
    dayOfWeek: row['day_of_week'] as int? ?? 1,
    startSection: row['start_section'] as int? ?? 1,
    endSection: row['end_section'] as int? ?? 1,
    weeks: _parseWeeks(row['weeks_json']),
    weekType: row['week_type'] as int? ?? 0,
    note: row['note'] as String?,
    examDate: row['exam_date_ms'] as int?,
    examEndTime: row['exam_end_time'] as String?,
    examPlace: row['exam_place'] as String?,
  );
}

/// Note → 云端 notes 行（蛇形命名）。要求备注已入库（id 非空）。
Map<String, dynamic> noteToRemoteRow(Note n) => {
      'id': noteRemoteId(n.id!),
      'date': n.date,
      'content': n.content,
      'created_at_ms': n.createdAt,
    };

/// 云端 notes 行 → Note（本地 id 取远程 id 里的 localId）。id 非法返回 null。
Note? noteFromRemoteRow(Map<String, dynamic> row) {
  final id = row['id'];
  if (id is! String) return null;
  final localId = parseNoteRemoteId(id);
  if (localId == null) return null;
  return Note(
    id: localId,
    date: row['date'] as String? ?? '',
    content: row['content'] as String? ?? '',
    createdAt: row['created_at_ms'] as int? ?? 0,
  );
}

/// Course → exams 镜像行；课程没有考试日期时返回 null（无需镜像）。
///
/// 映射口径（差异说明 1）：App 无独立考试模型，考试挂在 Course.examDate，
/// 镜像行供小马直接读写考试用。date 取考试日期、start_time 取考试时刻（非零点
/// 才有）、end_time 取课程 examEndTime、place 取课程 examPlace。
Map<String, dynamic>? examMirrorRow(Course c) {
  if (c.id == null || c.examDate == null) return null;
  final t = DateTime.fromMillisecondsSinceEpoch(c.examDate!);
  String two(int v) => v.toString().padLeft(2, '0');
  final date =
      '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
  final String? startTime =
      (t.hour == 0 && t.minute == 0) ? null : '${two(t.hour)}:${two(t.minute)}';
  return {
    'id': examRemoteId(c.semesterId, c.id!),
    'course_remote_id': courseRemoteId(c.semesterId, c.id!),
    'date': date,
    'start_time': startTime,
    'end_time': c.examEndTime,
    'place': c.examPlace,
  };
}

/// 把 Supabase 返回的 updated_at（ISO 字符串或毫秒）解析成毫秒；非法返回 null。
int? parseCloudUpdatedAt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  final t = DateTime.tryParse(raw.toString());
  return t?.millisecondsSinceEpoch;
}

/// 一行数据的同步方向判定结果。
enum SyncWinner {
  /// 本地赢（本地更新，上传覆盖云端）
  local,

  /// 云端赢（云端更新，下载覆盖本地）
  cloud,

  /// 双方一致或都没动，不做任何覆盖
  none,
}

/// 冲突取新：本地与云端都动过时取 updatedAt 较大的一方。
///
/// - 云端没有时间（null）→ 不动；
/// - 本地没有时间（旧数据，null）→ 云端赢；
/// - 谁的时间更新谁赢；
/// - 相等 → 不动。
SyncWinner resolveConflict(int? localUpdatedAtMs, int? cloudUpdatedAtMs) {
  if (cloudUpdatedAtMs == null) return SyncWinner.none;
  if (localUpdatedAtMs == null) return SyncWinner.cloud;
  if (cloudUpdatedAtMs > localUpdatedAtMs) return SyncWinner.cloud;
  if (localUpdatedAtMs > cloudUpdatedAtMs) return SyncWinner.local;
  return SyncWinner.none;
}

/// 上传过滤：水位为 0（首次迁移）全量上传；否则只传 updatedAt 晚于水位的行。
///
/// 旧数据 updatedAt 为 null（v5 之前落库的行），只在首次迁移（水位 0）上传，
/// 之后不再参与（避免把「没动过」的旧行反复推上云端）。
bool shouldUpload(int? localUpdatedAtMs, int watermarkMs) {
  if (watermarkMs <= 0) return true;
  if (localUpdatedAtMs == null) return false;
  return localUpdatedAtMs > watermarkMs;
}

/// 云端行是否晚于水位（下载过滤：早于/等于水位的行不下载，孤儿行天然被跳过）。
bool cloudRowAfterWatermark(int? cloudUpdatedAtMs, int watermarkMs) {
  if (cloudUpdatedAtMs == null) return false;
  return cloudUpdatedAtMs > watermarkMs;
}

/// 日期备注去重（第 4 节）：按 (date, content) 完全相同只留 createdAt 最早的一条。
///
/// 返回「去重后保留的列表」与「被去掉条目的清单描述」；清单供发版汇总用。
({List<Note> kept, List<String> removed}) dedupeNotes(List<Note> notes) {
  final seen = <String, Note>{};
  final removed = <String>[];
  for (final n in notes) {
    final key = '${n.date}\u0000${n.content}';
    final existing = seen[key];
    if (existing == null) {
      seen[key] = n;
    } else if (n.createdAt < existing.createdAt) {
      // 新条目更早，改保留新的、旧的进清单
      removed.add('${existing.date} ${existing.content}（id=${existing.id}）');
      seen[key] = n;
    } else {
      removed.add('${n.date} ${n.content}（id=${n.id}）');
    }
  }
  return (kept: seen.values.toList(), removed: removed);
}

/// 周次 JSON 容错解析：损坏时按空列表处理（与 Course.fromMap 同口径）。
List<int> _parseWeeks(Object? json) {
  if (json is! String || json.isEmpty) return const [];
  try {
    return (jsonDecode(json) as List).map((e) => e as int).toList();
  } catch (_) {
    return const [];
  }
}
