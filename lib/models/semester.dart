/// 学期模型：对应数据库 semesters 表
class Semester {
  final int? id;
  final String name; // 学期名，如「大三上学期」
  final String startDate; // 开学第一周的周一日期，ISO 字符串 yyyy-MM-dd
  final int totalWeeks; // 总周数，默认 20
  final bool isCurrent; // 是否为当前激活学期

  const Semester({
    this.id,
    required this.name,
    required this.startDate,
    this.totalWeeks = 20,
    this.isCurrent = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'startDate': startDate,
        'totalWeeks': totalWeeks,
        // SQLite 没有布尔类型，用 0/1 存储
        'isCurrent': isCurrent ? 1 : 0,
      };

  factory Semester.fromMap(Map<String, dynamic> map) => Semester(
        id: map['id'] as int?,
        name: map['name'] as String,
        startDate: map['startDate'] as String,
        totalWeeks: map['totalWeeks'] as int? ?? 20,
        isCurrent: (map['isCurrent'] as int? ?? 0) == 1,
      );

  Semester copyWith({
    int? id,
    String? name,
    String? startDate,
    int? totalWeeks,
    bool? isCurrent,
  }) =>
      Semester(
        id: id ?? this.id,
        name: name ?? this.name,
        startDate: startDate ?? this.startDate,
        totalWeeks: totalWeeks ?? this.totalWeeks,
        isCurrent: isCurrent ?? this.isCurrent,
      );
}
