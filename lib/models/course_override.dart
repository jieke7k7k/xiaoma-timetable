/// 单次调课模型：对应数据库 course_overrides 表（阶段五「节假日单次调课」预留）
/// 用于把某门课在「原周次」的那一次课临时调到其他时间/教室，或标记停课，
/// 不影响该课程在其他周次的正常排布。
class CourseOverride {
  static const int cancelFlag = -1; // targetWeek 取该值表示「本周停课」

  final int? id;
  final int courseId; // 关联的课程 id
  final int originalWeek; // 原周次
  final int targetWeek; // 调至周次；为 cancelFlag 时表示取消本次课
  final int? targetDayOfWeek; // 调至星期几（停课时为空）
  final int? targetStartSection; // 调至开始节次
  final int? targetEndSection; // 调至结束节次
  final String? targetClassroom; // 调至教室

  const CourseOverride({
    this.id,
    required this.courseId,
    required this.originalWeek,
    required this.targetWeek,
    this.targetDayOfWeek,
    this.targetStartSection,
    this.targetEndSection,
    this.targetClassroom,
  });

  /// 是否为「停课」记录
  bool get isCancellation => targetWeek == cancelFlag;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'courseId': courseId,
        'originalWeek': originalWeek,
        'targetWeek': targetWeek,
        'targetDayOfWeek': targetDayOfWeek,
        'targetStartSection': targetStartSection,
        'targetEndSection': targetEndSection,
        'targetClassroom': targetClassroom,
      };

  factory CourseOverride.fromMap(Map<String, dynamic> map) => CourseOverride(
        id: map['id'] as int?,
        courseId: map['courseId'] as int,
        originalWeek: map['originalWeek'] as int,
        targetWeek: map['targetWeek'] as int,
        targetDayOfWeek: map['targetDayOfWeek'] as int?,
        targetStartSection: map['targetStartSection'] as int?,
        targetEndSection: map['targetEndSection'] as int?,
        targetClassroom: map['targetClassroom'] as String?,
      );
}
