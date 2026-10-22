import '../models/course.dart';

/// 学期总周数推断（导入时按草稿课程反推）
///
/// 教务导出的课表常常比用户建学期时填的总周数长（实习/补课排到第 21 周等），
/// 直接入库会让超出部分永远显示不出来。这里从草稿里反推最晚周次，
/// 由核对页提示用户是否顺手把学期总周数补齐。
///
/// 纯函数、不碰数据库，便于单测。
class WeekInfer {
  WeekInfer._();

  /// 这批草稿里最晚的上课周次；没有草稿或周次全为空返回 0（表示无从推断）
  ///
  /// 只看 [Course.weeks] 的绝对值，不看 [Course.weekType]：单双周只是
  /// 在已选周次上再过滤一次，最晚周次本身不会被单双周改变。
  static int maxWeek(List<Course> drafts) {
    var max = 0;
    for (final c in drafts) {
      for (final w in c.weeks) {
        if (w > max) max = w;
      }
    }
    return max;
  }

  /// 目标学期总周数若要装下这批草稿，应调整为多少周。
  ///
  /// 推断值不超过 [totalWeeks] 时返回 null——表示无需调整，UI 不该有任何提示。
  static int? inferredTotalWeeks(List<Course> drafts, int totalWeeks) {
    final max = maxWeek(drafts);
    if (max <= totalWeeks) return null;
    return max;
  }
}
