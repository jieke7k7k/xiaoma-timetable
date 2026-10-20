/// 节次时间模型：对应数据库 time_slots 表
/// 描述第 N 节课的上下课时间，设置页可修改
class TimeSlot {
  final int section; // 节次号 1~12
  final String startTime; // 如 "08:00"
  final String endTime; // 如 "08:45"

  const TimeSlot({
    required this.section,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
        'section': section,
        'startTime': startTime,
        'endTime': endTime,
      };

  factory TimeSlot.fromMap(Map<String, dynamic> map) => TimeSlot(
        section: map['section'] as int,
        startTime: map['startTime'] as String,
        endTime: map['endTime'] as String,
      );

  TimeSlot copyWith({int? section, String? startTime, String? endTime}) =>
      TimeSlot(
        section: section ?? this.section,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
      );
}
