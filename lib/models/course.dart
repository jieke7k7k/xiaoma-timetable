import 'dart:convert';

/// 课程模型：对应数据库 courses 表
class Course {
  final int? id;
  final int semesterId; // 所属学期 id
  final String name; // 课程名
  final String? teacher; // 老师，可空
  final String? classroom; // 教室，可空
  final int colorValue; // ARGB 颜色整数
  final int dayOfWeek; // 星期几，1~7（周一为 1）
  final int startSection; // 开始节次
  final int endSection; // 结束节次
  final List<int> weeks; // 上课周次列表，如 [1,2,3,5]，入库时序列化为 JSON
  final int weekType; // 0-全部，1-单周，2-双周
  final String? note; // 备注，可空
  final int? examDate; // 考试日期时间戳（毫秒），可空，阶段五预留

  const Course({
    this.id,
    required this.semesterId,
    required this.name,
    this.teacher,
    this.classroom,
    required this.colorValue,
    required this.dayOfWeek,
    required this.startSection,
    required this.endSection,
    required this.weeks,
    this.weekType = 0,
    this.note,
    this.examDate,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'semesterId': semesterId,
        'name': name,
        'teacher': teacher,
        'classroom': classroom,
        'colorValue': colorValue,
        'dayOfWeek': dayOfWeek,
        'startSection': startSection,
        'endSection': endSection,
        'weeksJson': jsonEncode(weeks),
        'weekType': weekType,
        'note': note,
        'examDate': examDate,
      };

  factory Course.fromMap(Map<String, dynamic> map) => Course(
        id: map['id'] as int?,
        semesterId: map['semesterId'] as int,
        name: map['name'] as String,
        teacher: map['teacher'] as String?,
        classroom: map['classroom'] as String?,
        colorValue: map['colorValue'] as int,
        dayOfWeek: map['dayOfWeek'] as int,
        startSection: map['startSection'] as int,
        endSection: map['endSection'] as int,
        // 容错：weeksJson 损坏时按空列表处理，避免解析异常导致闪退
        weeks: _parseWeeks(map['weeksJson'] as String?),
        weekType: map['weekType'] as int? ?? 0,
        note: map['note'] as String?,
        examDate: map['examDate'] as int?,
      );

  static List<int> _parseWeeks(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List).map((e) => e as int).toList();
    } catch (_) {
      return [];
    }
  }

  /// 判断某周次是否应该显示本课程（结合周次列表与单双周设置）
  bool isActiveInWeek(int week) {
    if (!weeks.contains(week)) return false;
    switch (weekType) {
      case 1:
        return week.isOdd;
      case 2:
        return week.isEven;
      default:
        return true;
    }
  }

  Course copyWith({
    int? id,
    int? semesterId,
    String? name,
    String? teacher,
    String? classroom,
    int? colorValue,
    int? dayOfWeek,
    int? startSection,
    int? endSection,
    List<int>? weeks,
    int? weekType,
    String? note,
    int? examDate,
  }) =>
      Course(
        id: id ?? this.id,
        semesterId: semesterId ?? this.semesterId,
        name: name ?? this.name,
        teacher: teacher ?? this.teacher,
        classroom: classroom ?? this.classroom,
        colorValue: colorValue ?? this.colorValue,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startSection: startSection ?? this.startSection,
        endSection: endSection ?? this.endSection,
        weeks: weeks ?? this.weeks,
        weekType: weekType ?? this.weekType,
        note: note ?? this.note,
        examDate: examDate ?? this.examDate,
      );
}
