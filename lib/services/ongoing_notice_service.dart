import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/dao.dart';
import '../utils/ongoing_notice.dart';

/// 今日课程常驻通知栏服务（阶段四·第 3 项，Android only）
///
/// 通过 MethodChannel 与 Android 原生前台 Service（OngoingCourseService）通信：
/// - update：下发标题 + 行文案，由原生 Service startForeground 渲染常驻通知；
/// - stop：停服务并移除通知。
///
/// 三层架构（借鉴 csust-course-schedule 的「纯逻辑 / 服务 / 原生」分层，MIT）：
/// 纯逻辑在 ongoing_notice.dart，本层只负责读库 + 调通道，原生层负责真正渲染。
/// 全部异常 try/catch 打中文日志，绝不闪退。
class OngoingNoticeService {
  OngoingNoticeService._();
  static final OngoingNoticeService instance = OngoingNoticeService._();

  static const MethodChannel _channel =
      MethodChannel('com.jieke.xiaomakebiao/ongoing_course');

  /// 重算并下发常驻通知。
  ///
  /// 读 app_settings 键 ongoing_enabled（默认开启）：
  /// - 关闭：直接下发 stop，清通知停服务；
  /// - 开启：读当前学期 / 课程 / 节次，构建通知内容后下发 update。
  Future<void> refresh() async {
    try {
      final enabled =
          await Dao.instance.getSettingBool('ongoing_enabled', true);
      if (!enabled) {
        await stop();
        return;
      }
      final semester = await Dao.instance.getCurrentSemester();
      if (semester == null) {
        // 无当前学期（理论上不会发生）：清空常驻通知兜底
        await stop();
        return;
      }
      final courses = await Dao.instance.getCoursesBySemester(semester.id!);
      final slots = await Dao.instance.getTimeSlots();
      // 单次调课（阶段五）：停课的本次不展示，调课的按新时间/教室展示
      final overrides = await Dao.instance.getOverridesBySemester(semester.id!);
      final notice = buildOngoingNotice(
        now: DateTime.now(),
        semester: semester,
        courses: courses,
        timeSlots: slots,
        overrides: overrides,
      );
      await _channel.invokeMethod('update', {
        'title': notice.title,
        'lines': notice.lines,
      });
    } catch (e) {
      debugPrint('更新常驻通知失败：$e');
    }
  }

  /// 停止常驻通知：停服务 + 移除通知
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      debugPrint('停止常驻通知失败：$e');
    }
  }
}
