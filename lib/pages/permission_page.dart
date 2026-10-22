import 'package:flutter/material.dart';

import '../services/permission_service.dart';
import '../ui/app_styles.dart';

/// 权限页（设置 → 权限）：三项权限的状态与补开入口
///
/// 状态是每次进页面现查的（系统设置里改完回来就能看到变化）；
/// 已授权的项只显示状态，未授权的项可以点进去跳对应系统页面。
class PermissionPage extends StatefulWidget {
  const PermissionPage({super.key});

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage> {
  PermissionSnapshot? _status;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await PermissionService.instance.status();
    if (!mounted) return;
    setState(() => _status = s);
  }

  /// 跳系统页：回来后重新查一次状态（用户在系统里改完，页面要跟着变）
  Future<void> _jump(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
    // 系统设置页是另一个 Activity，回到本页的时机不定；延时再查一次更准
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('权限'), centerTitle: true),
      body: status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _PermissionTile(
                  icon: Icons.notifications_active_outlined,
                  title: '通知权限',
                  subtitle: '上课提醒、今日课程常驻通知、备注都走通知栏',
                  granted: status.notification,
                  working: _working,
                  onOpen: () => _jump(
                    status.notification
                        ? PermissionService.instance.openNotificationSettings
                        : () async {
                            final ok = await PermissionService.instance
                                .requestNotification();
                            if (!ok) {
                              await PermissionService.instance
                                  .openNotificationSettings();
                            }
                          },
                  ),
                ),
                _PermissionTile(
                  icon: Icons.alarm_outlined,
                  title: '精确闹钟',
                  subtitle: '让上课提醒准点到点；不开也能提醒，可能有几分钟误差',
                  granted: status.exactAlarm,
                  working: _working,
                  onOpen: () => _jump(
                    () => PermissionService.instance.openExactAlarmSettings(),
                  ),
                ),
                _PermissionTile(
                  icon: Icons.battery_std_outlined,
                  title: '电池优化白名单',
                  subtitle: '不加入白名单时，系统省电策略可能让提醒延迟或消失',
                  granted: status.battery,
                  working: _working,
                  onOpen: () => _jump(
                    PermissionService.instance.openBatterySettings,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('应用详情页'),
                  subtitle: const Text(
                    '上面某一项在你的系统上找不到时，可以到应用详情页里手动改',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _working
                      ? null
                      : () => _jump(PermissionService.instance.openAppDetails),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  child: Text(
                    '三项都不是必需的：没开也能正常看课表，只是提醒可能延迟或'
                    '在后台被省电策略掐掉。首次打开 App 时会引导一次，之后不再自动弹。',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.working,
    required this.onOpen,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final bool working;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: granted
                  ? scheme.primaryContainer
                  : scheme.errorContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            child: Text(
              granted ? '已授权' : '未授权',
              style: TextStyle(
                fontSize: 12,
                color: granted ? scheme.onPrimaryContainer : scheme.error,
              ),
            ),
          ),
          if (!granted) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right,
              color: working ? scheme.outline : null,
            ),
          ],
        ],
      ),
      onTap: working ? null : onOpen,
    );
  }
}
