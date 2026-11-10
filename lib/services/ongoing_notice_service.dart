import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/dao.dart';
import '../utils/next_class.dart';
import '../utils/ongoing_boundary.dart';
import '../utils/ongoing_notice.dart';
import 'notification_service.dart';

/// 今日课程常驻通知栏服务（阶段四·第 3 项，Android only）
///
/// 2.2.0（WB_SPEC_229）起的架构：**一条通知、两个更新通道**，不再有前台 Service。
/// - 通道 A（App 活着）：Dart 算文案（[buildOngoingNotice] 一字未动），经
///   flutter_local_notifications 直接发 ongoing 通知（见 [NotificationService.showOngoingCourseNotice]）；
/// - 通道 B（App 被杀 / 在后台）：精确闹钟唤醒原生 OngoingCourseReceiver，它自己读库、
///   自己算焦点、自己 notify 同一条通知，刷完立即预约下一个边界点。
///
/// 两个通道用同一个渠道（ongoing_course_channel「今日课程」）+ 同一个通知 id（1001），
/// 后到的覆盖先到的，用户始终只看到一条通知在翻页。
///
/// 本类只做「读库 + 组装 + 派发」三件事；文案纯逻辑在 ongoing_notice.dart，
/// 边界点纯逻辑在 ongoing_boundary.dart，原生渲染在 OngoingCourseReceiver.kt。
/// 全部异常 try/catch 打中文日志，绝不闪退。
class OngoingNoticeService {
  OngoingNoticeService._();
  static final OngoingNoticeService instance = OngoingNoticeService._();

  /// 与原生通信的通道。名字沿用旧名（调用方不用改），但语义变了：
  /// 它现在**只负责排链 / 停链**，不再负责渲染通知。
  static const MethodChannel _channel =
      MethodChannel('com.jieke.xiaomakebiao/ongoing_course');

  /// 重算并下发常驻通知，同时把闹钟链接上。
  ///
  /// 这就是「刷新常驻通知」的唯一入口：App 启动、改课、切学期、改开关、周视图
  /// 焦点变化都调它（调用点一字未动）。内部两件事都是幂等的：
  /// 1. 重建通知（通道 A）；
  /// 2. 按下一个边界点重排闹钟（通道 B）——排链前先撤旧闹钟，改课后不留旧链。
  ///
  /// 读 app_settings 键 ongoing_enabled（默认开启）：关闭即 [stop]（两个通道都停）。
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
        // 无当前学期（理论上不会发生）：清空常驻通知 + 停链兜底
        await stop();
        return;
      }
      final courses = await Dao.instance.getCoursesBySemester(semester.id!);
      final slots = await Dao.instance.getTimeSlots();
      // 单次调课（阶段五）：停课的本次不展示，调课的按新时间/教室展示
      final overrides = await Dao.instance.getOverridesBySemester(semester.id!);
      final now = DateTime.now();

      // 通道 A：文案仍是同一套纯逻辑，换的只是下发方式（旧：MethodChannel update；
      // 新：flutter_local_notifications show，与备注常驻通知同一种做法）
      final notice = buildOngoingNotice(
        now: now,
        semester: semester,
        courses: courses,
        timeSlots: slots,
        overrides: overrides,
      );
      await NotificationService.instance.showOngoingCourseNotice(
        title: notice.title,
        lines: notice.lines,
      );

      // 通道 B：边界点交给原生精确闹钟。焦点与上面文案用的是同一时刻的同一套输入，
      // 这里再算一次只是为了拿 current/next 的起止时刻（纯内存计算，开销可忽略）
      final focus = computeClassFocus(
        now: now,
        semester: semester,
        courses: courses,
        timeSlots: slots,
        overrides: overrides,
      );
      await _scheduleNext(computeNextBoundary(now: now, focus: focus));
    } catch (e) {
      debugPrint('更新常驻通知失败：$e');
    }
  }

  /// 停止常驻通知：取消通知 + 取消已排的链闹钟
  Future<void> stop() async {
    try {
      await NotificationService.instance.cancelOngoingCourseNotice();
    } catch (e) {
      debugPrint('停止常驻通知失败：$e');
    }
    try {
      await _channel.invokeMethod('cancelScheduled');
    } catch (e) {
      debugPrint('取消常驻通知链失败：$e');
    }
  }

  /// 把下一个边界点交给原生排精确闹钟（毫秒时间戳，绝对时刻，与时区无关）
  Future<void> _scheduleNext(DateTime boundary) async {
    try {
      await _channel.invokeMethod('scheduleNext', {
        'triggerAtMillis': boundary.millisecondsSinceEpoch,
      });
    } catch (e) {
      // 排链失败不影响已经刷新的通知，下次 App 打开会重排，不静默失败也不弹错
      debugPrint('预约常驻通知链失败：$e');
    }
  }
}
