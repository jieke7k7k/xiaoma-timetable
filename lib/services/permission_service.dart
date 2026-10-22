import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../database/dao.dart';
import 'notification_service.dart';

/// 权限收敛服务：通知 / 精确闹钟 / 电池优化白名单（**全 App 唯一入口**）
///
/// 之前这三项散落在提醒设置开关里（开提醒时顺带申请、被拒给个 SnackBar），
/// 用户从没被完整告知过要开哪些。本服务把它们收成一处：
/// - [status] 一次查三项（供设置页显示「已授权 / 未授权」）；
/// - [requestNotification] 走插件 API 直接弹系统授权框；
/// - [openExactAlarmSettings] / [openBatterySettings] 跳对应的系统页面；
/// - [shouldGuide] / [markGuided] 管「首次启动引导只出现一次」的标记。
///
/// 原生侧只补了一个 MethodChannel（MainActivity 的 device 通道）用来**查状态**
/// 与跳「应用详情页 / 电池优化设置页」；申请通知与精确闹钟仍复用
/// flutter_local_notifications 的插件 API，不重复造轮子。
class PermissionService {
  PermissionService._();

  static final PermissionService instance = PermissionService._();

  /// 首次引导的标记键（app_settings）。值 '1' 表示这套引导已经走过。
  static const String askedKey = 'permissions_asked_v1';

  /// 原生「设备设置」通道（MainActivity 里注册）
  static const MethodChannel _channel =
      MethodChannel('com.jieke.xiaomakebiao/device');

  // ---------- 状态 ----------

  /// 三项权限当前状态；非 Android（或通道没实现）一律按「无需处理」返回已授权，
  /// 免得在别的平台上显示一堆红色「未授权」。
  Future<PermissionSnapshot> status() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const PermissionSnapshot(
        notification: true,
        exactAlarm: true,
        battery: true,
      );
    }
    var notification = false;
    var battery = true;
    var exactFromChannel = false;
    try {
      final raw = await _channel.invokeMethod<Object?>('status');
      if (raw is Map) {
        notification = raw['notification'] == true;
        // 电池优化取反语义：原生回的是「是否已忽略优化」，查不到时按已加入处理
        battery = raw['battery'] != false;
        exactFromChannel = raw['exactAlarm'] == true;
      }
    } on MissingPluginException {
      // 原生还没注册这个通道（如桌面端调试）：按已授权处理，不打扰用户
      return const PermissionSnapshot(
        notification: true,
        exactAlarm: true,
        battery: true,
      );
    } on PlatformException catch (e) {
      debugPrint('读取权限状态失败：${e.message}');
    }
    // 精确闹钟：原生判定为准，再「或」上插件的判定——插件在还没初始化时会返回
    // false，那条路会误报成未授权，取或可以避免这种假阴性
    final exact = exactFromChannel ||
        await NotificationService.instance.canScheduleExact();
    return PermissionSnapshot(
      notification: notification,
      exactAlarm: exact,
      battery: battery,
    );
  }

  // ---------- 申请 / 跳转 ----------

  /// 申请通知权限（Android 13+ 会弹系统授权框），返回是否已授权
  Future<bool> requestNotification() =>
      NotificationService.instance.ensureNotificationPermission();

  /// 跳系统「闹钟和提醒」授权页（插件 API），返回是否已授权
  Future<bool> openExactAlarmSettings() =>
      NotificationService.instance.requestExactAlarmPermission();

  /// 跳本 App 的通知设置页（原生通道）
  Future<void> openNotificationSettings() => _invoke('openNotificationSettings');

  /// 跳系统「电池优化」白名单设置页；失败时回退到应用详情页
  Future<void> openBatterySettings() => _invoke('openBatteryOptimizationSettings');

  /// 跳本 App 的应用详情页（电池优化的兜底入口，任何 Android 都有）
  Future<void> openAppDetails() => _invoke('openAppDetails');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 通道没实现：静默失败，页面层已经给了中文说明
    } on PlatformException catch (e) {
      debugPrint('跳转系统设置失败（$method）：${e.message}');
    }
  }

  // ---------- 首次引导标记 ----------

  /// 这套引导还没走过？
  Future<bool> shouldGuide() async {
    try {
      return await Dao.instance.getSetting(askedKey) != '1';
    } catch (_) {
      // 读库失败时不挡路：宁可再引导一次，也不要因为异常卡住启动
      return true;
    }
  }

  /// 标记「引导已走过」。在引导**开始前**调用——中途退出/杀 App 也不该反复打扰。
  Future<void> markGuided() async {
    try {
      await Dao.instance.setSetting(askedKey, '1');
    } catch (_) {
      // 标记写不进去最多是下次再问一次，不影响任何功能
    }
  }
}

/// 三项权限的快照
class PermissionSnapshot {
  const PermissionSnapshot({
    required this.notification,
    required this.exactAlarm,
    required this.battery,
  });

  /// 通知权限（Android 13+ 运行时权限）
  final bool notification;

  /// 精确闹钟（Android 12+ 的 SCHEDULE_EXACT_ALARM）
  final bool exactAlarm;

  /// 电池优化白名单（true = 已加入，不会被省电策略掐掉后台）
  final bool battery;

  bool get allGranted => notification && exactAlarm && battery;
}
