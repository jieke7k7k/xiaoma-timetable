import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/menu_config.dart';
import '../providers/providers.dart';
import '../services/notification_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/widget_service.dart';
import '../ui/app_styles.dart';

/// 设置页（QQ 式分级）
///
/// 2.0.5（WB_SPEC_205 第 1 节）起首页只保留分组标题 + 每类一行入口行
/// （图标 + 名称 + 一行副标题 + ›），**首页不出现任何开关 / 滑杆 / 选择器**；
/// 点进每个分类才看到该组的全部设置项（见 settings_sections.dart）。
///
/// 2.0.6（WB_SPEC_206 第 1 节）去掉全部分组小标题：小标题与入口行同名，
/// 纯重复。首页现在只留入口行，组与组之间用比行内更大的 AppSpacing 间距分隔。
///
/// 2.0.7（WB_SPEC_208 第 1 节）Taste 化只动布局与层级；2.0.8（WB_SPEC_209
/// 第 3 节）删掉「和智能助手聊聊」入口。
///
/// 2.1.0（WB_SPEC_212 第 3/4 节）：
/// - 删掉「智能助手设置」入口（AI 全部收进开发者选项，普通用户看不到 AI 字样）；
/// - 新增「菜单管理」入口（进菜单管理子页）；
/// - 新增「更多工具」分组：全量平铺可自定义的六个菜单项，右侧灰字标注
///   菜单显隐状态（与菜单配置实时一致），是菜单全关时的兜底入口；
/// - 解锁开发者选项后，在页面底部（桌面小组件之后）出现「开发者选项」入口。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 菜单配置驱动「更多工具」分组右侧的显隐标注（实时一致，无需重启）
    final menuConfig =
        ref.watch(menuConfigProvider).value ?? MenuConfig.defaults();
    // 解锁后才显示开发者选项入口；解锁前设置页不得出现任何 AI 字样与入口
    final devUnlocked = ref.watch(developerOptionsProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        children: [
          // 2.1.0（WB_SPEC_211 第 2 节）：云同步行。显示上次同步时间 + 立即同步
          // 按钮；未配置显示「未配置」；失败显示原因文案，不闪退。放在首页顶部，
          // 其余入口行顺序/副标题/跳转一律不动。
          const _CloudSyncTile(),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.badge_outlined,
            title: '学期设置',
            subtitle: '学期名称、开学日期、总周数',
            route: '/settings-semester',
          ),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.palette_outlined,
            title: '外观',
            subtitle: '主题、实时预览、格子外观、课程配色与显示字体',
            route: '/settings-appearance',
          ),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.notifications_active_outlined,
            title: '提醒',
            subtitle: '上课提醒、上课播报、今日课程常驻通知、提前提醒',
            route: '/settings-reminders',
          ),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.handyman_outlined,
            title: '课表工具',
            subtitle: '课程搜索、空闲时段、考试倒计时、导出课表图片、日期备注',
            route: '/course-tools',
          ),
          const SizedBox(height: AppSpacing.group),
          // 2.1.0（WB_SPEC_212 第 4 节）：新增菜单管理入口
          const _EntryTile(
            icon: Icons.tune_outlined,
            title: '菜单管理',
            subtitle: '右上角菜单里显示哪些功能、按什么顺序排',
            route: '/menu-manage',
          ),
          const SizedBox(height: AppSpacing.group),
          // 2.1.0（WB_SPEC_212 第 4 节）：「更多工具」兜底分组——菜单里关掉的
          // 功能在设置页依然找得到；与「课表工具」「学期与数据」部分重复是故意的。
          const _GroupHeader('更多工具'),
          ..._divideRows([
            for (final spec in kCustomMenuItems)
              _ToolTile(
                icon: spec.icon,
                title: spec.title,
                route: spec.route,
                visible: menuConfig.byId(spec.id).visible,
              ),
          ]),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.folder_outlined,
            title: '学期与数据',
            subtitle: '导入课表、学期管理、备份恢复、导出 ICS、数据管理',
            route: '/settings-data',
          ),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.shield_outlined,
            title: '权限',
            subtitle: '通知、精确闹钟、电池优化',
            route: '/settings-permissions',
          ),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.info_outline,
            title: '关于小马课表',
            subtitle: '版本、检查更新、公告、更新日志与开源许可',
            route: '/about',
          ),
          const SizedBox(height: AppSpacing.group),
          const _EntryTile(
            icon: Icons.widgets_outlined,
            title: '桌面小组件',
            subtitle: '今日课程小组件的添加说明',
            route: '/settings-widget',
          ),
          // 2.1.0（WB_SPEC_212 第 3 节）：开发者选项入口，只在解锁后出现，
          // 固定在设置页底部（桌面小组件入口之后）；解锁前不渲染任何 AI 相关入口
          if (devUnlocked) ...[
            const SizedBox(height: AppSpacing.group),
            const _EntryTile(
              icon: Icons.build_outlined,
              title: '开发者选项',
              subtitle: '智能助手聊天、智能助手设置、智能助手历史',
              route: '/developer-options',
            ),
          ],
        ],
      ),
    );
  }
}

/// 分类入口行（图标 + 名称 + 一行副标题 + ›）：点进对应子页/已有二级页
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      // 2.0.7 Taste 化：标题字重 medium，副标题沿用主题次要颜色与字号（不改色不放大）
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}

/// 「更多工具」分组的小标题（2.1.0 新增）。
///
/// 与 settings_sections.dart 的节标题同款（13 号、semibold、正文主色），
/// 只做层级、不放大；组名与组内行名不重复，故保留标题不违反 2.0.6 去重原则。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// 把同一组内连续行用 1px 分隔线隔开（与 settings_sections 的 Taste 口径一致）。
List<Widget> _divideRows(List<Widget> rows) {
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0) const Divider(height: 1, thickness: 1),
      rows[i],
    ],
  ];
}

/// 「更多工具」分组里的一行：图标 + 名称 + 右侧灰字菜单显隐标注。
///
/// 点开直接进对应功能页；**不在本行放开关**（开关只在菜单管理页），
/// 点开某功能也不改动其菜单显隐。
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.route,
    required this.visible,
  });

  final IconData icon;
  final String title;
  final String route;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      // 灰色小字标注菜单显隐状态（与菜单配置实时一致）
      trailing: Text(
        visible ? '已在菜单显示' : '已在菜单隐藏',
        style: TextStyle(fontSize: 12, color: scheme.outline),
      ),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}

/// 云同步行（2.1.0）：显示上次同步时间/状态 + 「立即同步」按钮。
///
/// 未配置（缺 dart-define）时副标题显示「未配置」、不提供按钮；配置后副标题为
/// 上次同步摘要；同步失败时副标题是失败原因文案。任何异常都不闪退。
class _CloudSyncTile extends ConsumerStatefulWidget {
  const _CloudSyncTile();

  @override
  ConsumerState<_CloudSyncTile> createState() => _CloudSyncTileState();
}

class _CloudSyncTileState extends ConsumerState<_CloudSyncTile> {
  String? _summary;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await SupabaseSyncService.instance.lastSyncSummary();
      if (mounted) setState(() => _summary = s);
    } catch (_) {
      // 读摘要失败（库异常）就保持现状，不让设置页崩
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final outcome = await SupabaseSyncService.instance.syncNow();
      if (!mounted) return;
      if (outcome.changed) {
        // 云同步下载改动了本地数据：失效相关 Provider 并联动通知/小组件
        ref.invalidate(coursesProvider);
        ref.invalidate(notesProvider);
        unawaited(NotificationService.instance.rescheduleAll());
        unawaited(WidgetService.instance.refreshWidgets());
      }
      await _load();
    } catch (e) {
      // 兜底：同步服务内部已捕获，这里再兜一层，绝不闪退
      if (mounted) setState(() => _summary = '同步失败：$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = SupabaseSyncService.instance.configured;
    final String subtitle;
    if (!configured) {
      subtitle = '未配置（需要构建时注入 Supabase 连接）';
    } else if (_syncing) {
      subtitle = '正在同步…';
    } else {
      subtitle = _summary ?? '上次同步：—';
    }
    return ListTile(
      leading: const Icon(Icons.cloud_outlined),
      title: const Text('云同步', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      trailing: !configured || _syncing
          ? null
          : TextButton(
              onPressed: _syncNow,
              child: const Text('立即同步'),
            ),
    );
  }
}
