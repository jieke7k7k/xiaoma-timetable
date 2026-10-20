import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../database/dao.dart';
import '../utils/reminder_plan.dart';

/// 上课提醒通知渠道 ID（高优先级，中文名「课程提醒」）。
/// 注意：后续「今日课程常驻通知栏」会另建渠道 ongoing_course_channel，勿混用。
const String kCourseReminderChannelId = 'course_reminder_channel';
const String kCourseReminderChannelName = '课程提醒';

/// 自举闹钟通知 ID（次日 0 点重排标记）。
/// 用一个与课程提醒 ID 完全分离的大整数，避免与课程提醒 ID 冲突。
const int kBootstrapNotificationId = 0x7FFFFFFF;

/// 上课本地通知提醒服务（阶段四·第 1 项）
///
/// 设计说明（精确闹钟「每日重排」模型的落地方式）：
/// flutter_local_notifications 只提供「通知点按」回调，没有「通知触发瞬间」回调，
/// 因此「每天 0 点由后台任务自动重排」无法用纯本地通知实现。
/// 这里改用「滚动窗口」方案，达到等价效果：
///   1. [rescheduleAll] 一次性排好「今天 + 未来 N 天」的课程提醒（exactAllowWhileIdle
///      精确闹钟，App 被杀后台也能准时响），并额外排一条「次日 0 点」自举标记通知；
///   2. 触发点：App 启动、切换学期、增删改课程、改提醒设置（见 providers.dart 挂点）；
///   3. 重启手机：插件内置的 ScheduledNotificationBootReceiver 会把已排的通知重新注册
///      到 AlarmManager，滚动窗口内的提醒照常触发；本项目的 BootReceiver 作为第二道保险。
/// 这样即便长时间不打开 App，窗口内的提醒也不会丢失。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 滚动窗口天数：今天 + 未来 6 天，共 7 天。
  /// 7 天 × 每天约 6 节课 ≈ 40 个精确闹钟，远低于 Android AlarmManager 上限。
  static const int _windowDays = 7;

  bool _initialized = false;

  /// 初始化：时区 + 插件 + 通知渠道（幂等，App 启动时调用一次）。
  ///
  /// 所有异常内部捕获并打日志，保证初始化失败不拖垮 App 启动。
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 精确闹钟需要在本地时区准点触发，先加载时区库并固定东八区
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (e) {
      debugPrint('设置本地时区失败：$e');
    }

    try {
      // 仅做 Android（本项目不写 iOS 代码，Darwin 初始化分支略过，留待后续）
      // 小图标用纯白日历剪影：mipmap 彩色应用图标在状态栏会被压成白块/模糊
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_course'),
      );
      await _plugin.initialize(settings: settings);
      await _ensureChannel();
    } catch (e) {
      debugPrint('通知插件初始化失败：$e');
    }
  }

  /// 确保「课程提醒」高优先级渠道已创建
  Future<void> _ensureChannel() async {
    const channel = AndroidNotificationChannel(
      kCourseReminderChannelId,
      kCourseReminderChannelName,
      description: '上课提前提醒',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 申请 Android 13+ 通知权限（POST_NOTIFICATIONS）。
  /// 返回 true 表示已授权或系统版本无需授权；被拒返回 false（不抛异常）。
  Future<bool> ensureNotificationPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return (await android.requestNotificationsPermission()) ?? false;
  }

  /// 是否可精确排期（SCHEDULE_EXACT_ALARM）。
  /// 返回 false 表示需降级为非精确排期，并由 UI 引导用户去系统设置授权。
  Future<bool> canScheduleExact() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return (await android.canScheduleExactNotifications()) ?? false;
  }

  /// 请求精确闹钟权限（Android 12+ 会跳系统「闹钟和提醒」设置页）。
  /// 返回是否已授权；用户拒绝时由 UI 提示，绝不闪退。
  Future<bool> requestExactAlarmPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return (await android.requestExactAlarmsPermission()) ?? false;
  }

  /// 重排全部课程提醒（滚动窗口 + 次日 0 点自举标记）。
  ///
  /// 流程：cancelAll 清空旧提醒 → 读当前学期/课程/节次/设置 → 逐条排期。
  /// 全部异常捕获：排期失败只打日志，保证切学期/增删改课程/开机不会闪退。
  Future<void> rescheduleAll() async {
    try {
      await initialize();

      final semester = await Dao.instance.getCurrentSemester();
      if (semester == null) return;

      // 先清空旧提醒（含旧自举闹钟），避免重复/残留
      await _plugin.cancelAll();

      // 提醒开关关闭时，清空即返回
      final enabled =
          await Dao.instance.getSettingBool('reminder_enabled', false);
      if (!enabled) return;

      final courses = await Dao.instance.getCoursesBySemester(semester.id!);
      final slots = await Dao.instance.getTimeSlots();
      // 单次调课（阶段五）：停课的本次不排提醒，调课的按新时间排
      final overrides = await Dao.instance.getOverridesBySemester(semester.id!);
      final advance =
          await Dao.instance.getSettingInt('reminder_advance_minutes', 15);

      // 精确闹钟授权检查：无权限时降级为非精确排期（仍能提醒，可能略有延迟）
      final exact = await canScheduleExact();
      final mode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      final now = tz.TZDateTime.now(tz.local);
      final today = tz.TZDateTime(tz.local, now.year, now.month, now.day);
      int nextId = 1;

      for (int offset = 0; offset < _windowDays; offset++) {
        final day = today.add(Duration(days: offset));
        final plans = buildDailyReminderPlan(
          date: DateTime(day.year, day.month, day.day),
          semester: semester,
          courses: courses,
          timeSlots: slots,
          advanceMinutes: advance,
          overrides: overrides,
        );
        for (final plan in plans) {
          final fireAt = tz.TZDateTime.from(plan.reminderTime, tz.local);
          // 已过时刻不再排，避免一打开 App 就补响一堆过期提醒
          if (!fireAt.isAfter(now)) continue;
          await _plugin.zonedSchedule(
            id: nextId++,
            title: '上课提醒',
            body: buildReminderBody(plan.course, advance),
            scheduledDate: fireAt,
            notificationDetails: _courseDetails(),
            androidScheduleMode: mode,
          );
        }
      }

      // 次日 0 点自举标记（低优先级、静音，作为「每日重排」的时间锚点）
      final midnight = today.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: kBootstrapNotificationId,
        title: '课程提醒',
        body: '今日课程提醒已就绪',
        scheduledDate: midnight,
        notificationDetails: _bootstrapDetails(),
        androidScheduleMode: mode,
      );
    } catch (e) {
      debugPrint('通知重排失败：$e');
    }
  }

  /// 课程提醒通知样式：高优先级 + 高重要性，走「课程提醒」渠道
  NotificationDetails _courseDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          kCourseReminderChannelId,
          kCourseReminderChannelName,
          channelDescription: '上课提前提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  /// 自举标记通知样式：低重要性 + 静音，尽量不打扰用户
  NotificationDetails _bootstrapDetails() => const NotificationDetails(
        android: AndroidNotificationDetails(
          kCourseReminderChannelId,
          kCourseReminderChannelName,
          channelDescription: '课程提醒自举标记',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
        ),
      );
}
