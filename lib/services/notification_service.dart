import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../database/dao.dart';
import '../utils/note_notice.dart';
import '../utils/reminder_plan.dart';

/// 上课提醒通知渠道 ID（高优先级，中文名「课程提醒」）。
/// 注意：后续「今日课程常驻通知栏」会另建渠道 ongoing_course_channel，勿混用。
const String kCourseReminderChannelId = 'course_reminder_channel';
const String kCourseReminderChannelName = '课程提醒';

/// 备注常驻通知专用渠道 ID / 名称与通知 ID。
///
/// 与课程提醒各占一个 id / 一个渠道，互不干扰：
/// - id 取 int 最大值减 1 的量级（远离滚动窗口的 1~几百）；
/// - 渠道重要性 low 且不响铃不震动，备注是「瞥一眼」的常驻信息，不是打扰；
/// - 常驻（ongoing=true）由 AndroidNotificationDetails 控制，用户不能滑掉，
///   只能在备注页删到「今天明天都没有」时由 [NotificationService.refreshNoteNotice] 取消。
const String kNoteChannelId = 'note_ongoing_channel';
const String kNoteChannelName = '备注';
const int kNoteNotificationId = 0x7FFFFFFE;

/// 上课本地通知提醒服务（阶段四·第 1 项）
///
/// 设计说明（精确闹钟「每日重排」模型的落地方式）：
/// flutter_local_notifications 只提供「通知点按」回调，没有「通知触发瞬间」回调，
/// 因此「每天 0 点由后台任务自动重排」无法用纯本地通知实现。
/// 这里改用「滚动窗口」方案，达到等价效果：
///   1. [rescheduleAll] 一次性排好「今天 + 未来 N 天」的课程提醒（exactAllowWhileIdle
///      精确闹钟，App 被杀后台也能准时响）；（2.0.0 起不再排 0 点自举标记通知：
///      它没有任何触发回调、只会在通知栏白占一条，复审 C6 已删除。）
///   2. 触发点：App 启动、切换学期、增删改课程、改提醒设置（见 providers.dart 挂点）；
///   3. 重启手机：插件内置的 ScheduledNotificationBootReceiver 会把已排的通知重新注册
///      到 AlarmManager，滚动窗口内的提醒照常触发；本项目的 BootReceiver 作为第二道保险。
/// 这样即便长时间不打开 App，窗口内的提醒也不会丢失。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 滚动窗口天数：今天 + 未来 29 天，共 30 天（1.3.4 长假期间不开 App 也要有提醒）。
  ///
  /// ID 分配安全性：每次 [rescheduleAll] 先 cancelAll，再从 1 起单调递增，
  /// 上限是「30 天 × 每天节次数」（按最大 12 节算约 360），
  /// 与备注常驻通知的 [kNoteNotificationId]（0x7FFFFFFE ≈ 21.4 亿）相距 6 个数量级，
  /// 既不会 int 溢出也不会撞号；同一窗口内 id 唯一、无重复。
  /// 另注：Android AlarmManager 同时活跃闹钟上限约 500，360 仍在安全区内。
  static const int _windowDays = 30;

  /// 初始化只跑一次的未来：并发调用（App 启动 + rescheduleAll 兜底）共享它。
  ///
  /// 1.3.2 起通知初始化挪到首帧之后，rescheduleAll 可能比它先跑到，
  /// 共享 Future 保证排期前一定等到真正的初始化完成（旧写法只靠 bool 标记，
  /// 会出现「标记已初始化但插件还没就绪就去排期」的竞态）。
  Future<void>? _initFuture;

  /// 初始化：时区 + 插件 + 通知渠道（幂等，App 启动时调用一次）。
  ///
  /// 所有异常内部捕获并打日志，保证初始化失败不拖垮 App 启动。
  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
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
      await _ensureNoteChannel();
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

  /// 确保「备注」低重要性渠道已创建（常驻展示当天/明天备注，不响铃不震动）。
  Future<void> _ensureNoteChannel() async {
    const channel = AndroidNotificationChannel(
      kNoteChannelId,
      kNoteChannelName,
      description: '当天与明天的备注，常驻显示',
      importance: Importance.low,
      enableVibration: false,
      showBadge: false,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 刷新备注常驻通知（有今天/明天备注就常驻显示，都没有就取消）。
  ///
  /// 为什么总是紧跟 [rescheduleAll]：那条流程第一步就是 `_plugin.cancelAll()`，
  /// 会把备注通知一起清掉，所以两条出口（提醒关闭提前返回 / 排期完成）都补一次
  /// 重建，保证「改提醒设置」不会顺手弄丢备注通知。
  ///
  /// 挂载时机：备注增删改（providers 的 NotesNotifier）、App 启动
  /// （HomeShell 首帧任务里的 rescheduleAll 内部调用）。跨天仍需打开一次
  /// App 才刷新——与今日课程常驻通知、桌面小部件是同一条已知限制
  /// （本地通知没有「触发瞬间回调」）。
  Future<void> refreshNoteNotice() async {
    try {
      await initialize();
      final notes = await Dao.instance.getAllNotes();
      final notice = buildNoteNotice(now: DateTime.now(), notes: notes);
      if (notice == null) {
        await _plugin.cancel(id: kNoteNotificationId);
        return;
      }
      await _plugin.show(
        id: kNoteNotificationId,
        title: notice.title,
        body: notice.text,
        notificationDetails: _noteDetails(notice),
      );
    } catch (e) {
      debugPrint('刷新备注常驻通知失败：$e');
    }
  }

  /// 备注常驻通知样式：低重要性 + ongoing（不可滑掉）+ 大文本展开多行。
  NotificationDetails _noteDetails(NoteNotice notice) => NotificationDetails(
        android: AndroidNotificationDetails(
          kNoteChannelId,
          kNoteChannelName,
          channelDescription: '当天与明天的备注，常驻显示',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          channelShowBadge: false,
          ongoing: true,
          autoCancel: false,
          styleInformation: BigTextStyleInformation(
            notice.text,
            contentTitle: notice.title,
            summaryText: '备注',
          ),
        ),
      );

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

  /// 重排全部课程提醒（30 天滚动窗口）。
  ///
  /// 流程：cancelAll 清空旧提醒 → 读当前学期/课程/节次/设置 → 逐条排期。
  /// 全部异常捕获：排期失败只打日志，保证切学期/增删改课程/开机不会闪退。
  Future<void> rescheduleAll() async {
    try {
      await initialize();

      final semester = await Dao.instance.getCurrentSemester();
      if (semester == null) return;

      // 先清空旧提醒，避免重复/残留
      await _plugin.cancelAll();

      // 提醒开关关闭时，清空即返回。cancelAll 会连带清掉备注常驻通知，
      // 必须在这里补一次重建（开关提醒不该弄丢备注通知）
      final enabled =
          await Dao.instance.getSettingBool('reminder_enabled', false);
      if (!enabled) {
        await refreshNoteNotice();
        return;
      }

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

      // cancelAll 把备注常驻通知也清了，排完后面顺手重建
      await refreshNoteNotice();
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

}
