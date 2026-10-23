import 'dart:convert';

/// 一条「改数据」操作记录（2.0.5 第 4 节·撤回操作）
///
/// AI 与 AI 桥每次**实际执行**一条改数据指令（add_course / set_course_color /
/// set_course_remark / add_note / delete_note / add_exam）时落一条：
/// - [source]：来源（ai / bridge）
/// - [summary]：指令的中文人话摘要（执行器结果的 message 直接用）
/// - [snapshot]：**执行前**状态快照（足以完整还原：新增类记新对象 id、
///   删除类记被删对象全文、修改类记旧值）
///
/// 撤回本身不落新记录（走 Dao 直接还原），所以不会套娃。
class OperationLog {
  final int? id;
  final int createdAt; // 毫秒时间戳
  final String source; // 'ai' | 'bridge'
  final String summary;
  final Map<String, dynamic> snapshot; // 执行前快照（含 kind 字段）
  final bool undone; // 是否已撤回

  const OperationLog({
    this.id,
    required this.createdAt,
    required this.source,
    required this.summary,
    required this.snapshot,
    this.undone = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'createdAt': createdAt,
        'source': source,
        'summary': summary,
        'snapshotJson': jsonEncode(snapshot),
        'undone': undone ? 1 : 0,
      };

  factory OperationLog.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> snapshot = const {};
    final raw = map['snapshotJson'] as String? ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) snapshot = decoded;
    } catch (_) {
      snapshot = const {};
    }
    return OperationLog(
      id: map['id'] as int?,
      createdAt:
          map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      source: map['source'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      snapshot: snapshot,
      undone: (map['undone'] as int? ?? 0) != 0,
    );
  }
}
