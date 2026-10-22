import '../utils/week_calc.dart';

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

  /// 从数据库行构造。
  ///
  /// [totalWeeks] 除 null 兜底 20 之外还要钳到 1~30（2.0.0 复审 C7）：它是
  /// PageView 页码的上界、周次推断的下界，0/负数会让「第 0 周」与除零式的
  /// 边界计算出现在页面上，超大值（手改备份塞个 9999）会让周次跳转条失控。
  /// 区间与学期表单校验（[validateSemesterForm]）一致，两处同一个数。
  factory Semester.fromMap(Map<String, dynamic> map) => Semester(
        id: map['id'] as int?,
        name: map['name'] as String,
        startDate: map['startDate'] as String,
        totalWeeks: (map['totalWeeks'] as int? ?? 20).clamp(1, 30),
        isCurrent: (map['isCurrent'] as int? ?? 0) == 1,
      );

  /// 开学日期的安全解析（防御性）
  ///
  /// [startDate] 在库里是 TEXT，正常恒为 yyyy-MM-dd；但手工改过备份、旧版本
  /// 脏数据都可能让它解析失败，散落各处的 DateTime.parse 会直接抛异常崩页。
  ///
  /// 回退值选「今天所在周一」而非某个固定日期（如默认的 2026-09-07）：
  /// 固定日期在若干年后会算出上千周、在若干年前也会让周次远超总周数，
  /// 页面定位照样越界；回退到本周一则恒等于第 1 周，任何周次计算与
  /// PageView 定位都落在合理区间内，是最安全的兜底。
  DateTime get startDateParsed =>
      DateTime.tryParse(startDate) ?? WeekCalc.alignToMonday(DateTime.now());

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
