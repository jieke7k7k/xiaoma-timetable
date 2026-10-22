/// 备注模型：对应数据库 notes 表
///
/// 备注按「日期」组织：[date] 恒为 yyyy-MM-dd 的本地日期字符串，
/// 与学期、课程都没有外键关系——它是「某天要做/记下的一件事」，
/// 由备注页维护，并可在通知栏常驻通知与桌面小部件按日展示。
class Note {
  final int? id;
  final String date; // 日期，格式 yyyy-MM-dd
  final String content; // 备注内容
  final int createdAt; // 创建时间（毫秒时间戳）

  const Note({
    this.id,
    required this.date,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'content': content,
        'createdAt': createdAt,
      };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as int?,
        date: map['date'] as String,
        content: map['content'] as String? ?? '',
        // 容错：旧数据/异常行没有时间戳时按「现在」补，避免页面排序炸掉
        createdAt:
            map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      );

  Note copyWith({
    int? id,
    String? date,
    String? content,
    int? createdAt,
  }) =>
      Note(
        id: id ?? this.id,
        date: date ?? this.date,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
      );
}
