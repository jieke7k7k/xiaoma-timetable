import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// 纯重复。首页现在只留入口行，组与组之间用比行内更大的 AppSpacing 间距分隔；
/// 入口行本身、顺序、副标题、跳转全不动。
///
/// 2.0.7（WB_SPEC_208 第 1 节）Taste 化只动布局与层级：组与组之间间距统一为
/// 24（`AppSpacing.group`）；智能助手组内两行用 1px 分隔线（现有主题
/// dividerColor）隔开，不再用空隙硬隔；入口行标题字重 medium。入口行、顺序、
/// 副标题、图标、跳转一个不改，颜色一律不动。
///
/// 2.0.8（WB_SPEC_209 第 3 节）删掉「和智能助手聊聊」入口（聊天改从底部栏进），
/// 随之去掉它与「智能助手设置」之间的 1px 分隔线；智能助手设置入口、顺序、
/// 副标题、跳转不变。设置首页入口由 10 行变 9 行。
///
/// 取代 2.0.3 的「外观平铺首页」规范：原先直接摆在首页的学期设置三项、外观组
/// （实时预览 + 主题 + 格子外观 + 卡片显示 + 课程配色 + 主题颜色 + 字体）、
/// 提醒四项、学期与数据六行、权限摘要、桌面小组件说明，全部下沉到各自子页，
/// 控件与业务逻辑原样搬过去（不许丢项、不许改行为）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
          // 2.0.8（WB_SPEC_209 第 3 节）：删掉「和智能助手聊聊」入口（聊天从底部栏进），
          // 智能助手设置入口保留，顺序/副标题/跳转不变；组内只剩一行，分隔线随行数消失
          const _EntryTile(
            icon: Icons.settings_outlined,
            title: '智能助手设置',
            subtitle: '接口地址、模型名、API Key、测试对话与 AI 桥',
            route: '/ai-settings',
          ),
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
