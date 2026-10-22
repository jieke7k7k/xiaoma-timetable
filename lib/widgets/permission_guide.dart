import 'package:flutter/material.dart';

import '../services/permission_service.dart';

/// 首次启动的权限引导（**只在第一次打开 App 时走一遍**）
///
/// 顺序与策略（用户定的）：
/// ① 通知权限——直接用插件 API 弹系统授权框；
/// ② 精确闹钟——说明后跳系统「闹钟和提醒」授权页；
/// ③ 电池优化——说明后跳系统电池优化页（跳不过去时页面里有「应用详情页」兜底）。
///
/// 每一步都能「跳过」，跳过与拒绝都不再自动弹：标记 `permissions_asked_v1`
/// 在引导**开始前**就写进 app_settings（见 [PermissionService.markGuided]），
/// 中途退出/被杀也不会变成天天弹窗。
///
/// 引导结束后不做任何强制校验——三项没开只是提醒可能延迟、后台可能被省电掐掉，
/// App 本身照常能用；补开的入口长期留在「设置 → 权限」。
Future<void> runPermissionGuide(BuildContext context) async {
  final service = PermissionService.instance;
  if (!await service.shouldGuide()) return;
  await service.markGuided();

  // ① 通知权限：系统授权框（Android 13+ 才有；低版本插件直接返回已授权）
  final granted = await service.requestNotification();
  if (!granted && context.mounted) {
    final go = await _ask(
      context,
      title: '允许小马课表发通知',
      body: '上课提醒、今日课程常驻通知和备注都走通知栏。'
          '不开也能用课表，但提醒不会响。',
      actionLabel: '去设置',
    );
    if (go) await service.openNotificationSettings();
  }

  // ② 精确闹钟：被限制时提醒会延迟几分钟（降级为不精确排期）
  var status = await service.status();
  if (!status.exactAlarm && context.mounted) {
    final go = await _ask(
      context,
      title: '开启「闹钟和提醒」',
      body: '上课提醒要准点到点响，需要系统允许精确闹钟。'
          '不开也能提醒，只是可能有几分钟误差。',
      actionLabel: '去设置',
    );
    if (go) await service.openExactAlarmSettings();
  }

  // ③ 电池优化：不加白名单，长时间不开 App 后提醒可能被系统省电策略掐掉
  status = await service.status();
  if (!status.battery && context.mounted) {
    final go = await _ask(
      context,
      title: '把小马课表加入电池优化白名单',
      body: '系统默认会在后台限制不常用 App，课程提醒可能被延迟甚至不响。'
          '在接下来的系统页面里把小马课表设为「不优化」即可；'
          '如果你的系统没有这一项，也可以到「应用详情页 → 电池」里手动改。',
      actionLabel: '去设置',
    );
    if (go) await service.openBatterySettings();
  }
}

/// 一步引导的说明对话框；返回 true 表示用户点了「去设置」
Future<bool> _ask(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
}) async {
  final go = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return go == true;
}
