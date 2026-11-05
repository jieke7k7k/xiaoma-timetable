import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/permission_service.dart';
import '../ui/app_styles.dart';
import '../ui/bottom_bar_metrics.dart';

/// 设置页（QQ 式分级 → WB_SPEC_218 第 ④ 节重组为三大分组）
///
/// 2.0.5（WB_SPEC_205 第 1 节）起首页只保留分组标题 + 每类一行入口行，
/// 首页不出现任何开关 / 滑杆 / 选择器；2.0.6 去全部分组小标题；2.0.7 Taste 化；
/// 2.1.0 加菜单管理入口与「更多工具」分组；2.1.3 删隐藏入口。
///
/// 2.1.7（WB_SPEC_218 第 ④ 节）按 Argon 方案重组为「3 大分组 + 顶部更多菜单」：
/// - 第一组「课表与学期」：当前学期与周次、课表工具箱（菜单管理并入课表工具页）；
/// - 第二组「展示与桌面」：外观与底栏、桌面小组件、上课提醒（附权限自检条）；
/// - 第三组「数据与安全」：数据备份与换机。
/// - AppBar 右上角 ⋮ 更多菜单：权限自检、关于小马课表（原路由不动，仅触发按钮
///   从列表移到 PopupMenuButton）。「更多工具」分组与「菜单管理」「权限」「关于」
///   三个独立入口行随之移除——功能分别并入课表工具箱 / ⋮ 菜单，砍掉约 22% 冗余行。
/// 同版第 ③ 节把「云同步」整条线删除，首页不再有云同步行。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.isEmbeddedInShell = false});

  /// 是否作为壳内一级视图（底部栏开启时）显示（WB_SPEC_213 第 2 节）。
  ///
  /// 由构造参数**静态**决定，不绑定响应式的 showBottomBar 状态：
  /// 壳内（true）永远不显示左上角返回箭头、列表底部加胶囊安全留白；
  /// Push 路由进入（false，默认）永远显示返回箭头、维持常规留白。
  final bool isEmbeddedInShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 底部栏形态（WB_SPEC_216 第 1 节）：壳内列表底部留白要按形态算
    // （标签栏 64 / 胶囊 0 占位式，口径同主页网格，见 ui/bottom_bar_metrics.dart）
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();

    // 动态副标题三处（WB_SPEC_218 第 ④ 节：状态外露、入口收拢）
    final semester = ref.watch(currentSemesterProvider).value;
    final todayWeek = ref.watch(todayWeekProvider);
    final semesterSubtitle = semester == null
        ? '学期名称、开学日期、总周数'
        : '${semester.name} · 第 $todayWeek 周';

    final themeMode =
        ref.watch(themeSettingsProvider).value ?? ThemeMode.system;
    final themeLabel = switch (themeMode) {
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
      _ => '跟随系统',
    };
    final barLabel = ui.showBottomBar ? '标签栏' : '底栏已关';
    final appearanceSubtitle = '$themeLabel · $barLabel';

    final reminder = ref.watch(reminderSettingsProvider).value;
    final reminderSubtitle = reminder == null
        ? '上课提醒、上课播报、今日课程常驻通知、提前提醒'
        : '${reminder.enabled ? '已开启' : '未开启'} · 课前 ${reminder.advanceMinutes} 分钟通知';

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        // 壳内（一级视图）不显示返回箭头；独立 Push 路由显示
        automaticallyImplyLeading: !isEmbeddedInShell,
        actions: [_buildMoreMenu(context)],
      ),
      body: ListView(
        // 壳内一级视图底部留白：按栏高算（标签栏 64，再加底部安全区），
        // 防止栏体遮挡列表末尾；独立 Push 路由维持常规留白。
        // 口径与主页网格同源，见 ui/bottom_bar_metrics.dart。
        padding: EdgeInsets.only(
          top: AppSpacing.m,
          bottom: isEmbeddedInShell
              ? bottomBarGridBottomPadding(
                  MediaQuery.paddingOf(context).bottom,
                  showBottomBar: ui.showBottomBar,
                )
              : AppSpacing.m,
        ),
        children: [
          const _GroupHeader('课表与学期'),
          ..._divideRows([
            _EntryTile(
              icon: Icons.badge_outlined,
              title: '当前学期与周次',
              subtitle: semesterSubtitle,
              route: '/settings-semester',
            ),
            const _EntryTile(
              icon: Icons.handyman_outlined,
              title: '课表工具箱',
              subtitle: '搜索、空闲时段、考试倒计时',
              route: '/course-tools',
            ),
          ]),
          const SizedBox(height: AppSpacing.group),
          const _GroupHeader('展示与桌面'),
          ..._divideRows([
            _EntryTile(
              icon: Icons.palette_outlined,
              title: '外观与底栏',
              subtitle: appearanceSubtitle,
              route: '/settings-appearance',
            ),
            const _EntryTile(
              icon: Icons.widgets_outlined,
              title: '桌面小组件',
              subtitle: '今日课程小组件的添加说明',
              route: '/settings-widget',
            ),
            // 上课提醒入口顶部附权限自检条：权限异常时高亮「权限异常，点击修复」，
            // 正常时隐藏（见 _PermissionAlertTile）。
            const _PermissionAlertTile(),
            _EntryTile(
              icon: Icons.notifications_active_outlined,
              title: '上课提醒',
              subtitle: reminderSubtitle,
              route: '/settings-reminders',
            ),
          ]),
          const SizedBox(height: AppSpacing.group),
          const _GroupHeader('数据与安全'),
          ..._divideRows([
            const _EntryTile(
              icon: Icons.backup_outlined,
              title: '数据备份与换机',
              subtitle: '本地导出、恢复与换机迁移（纯本地存储）',
              route: '/settings-data',
            ),
          ]),
        ],
      ),
    );
  }

  /// AppBar 右上角 ⋮ 更多菜单（WB_SPEC_218 第 ④ 节）：
  /// 权限自检、关于小马课表——原路由不动，仅触发按钮从 ListView 移到菜单。
  Widget _buildMoreMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert),
      onSelected: (route) => Navigator.pushNamed(context, route),
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: '/settings-permissions',
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('权限自检'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: '/about',
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于小马课表'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
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

/// 分组小标题（2.0.7 起沿用 settings_sections 同款：13 号、semibold、正文主色）。
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
      // 权限自检条（_PermissionAlertTile）自带两侧分隔线：它隐藏时不画，
      // 可见时自己画——这里不替它画，否则隐藏时它前后两条线会叠成 2px
      //（2.1.7 复查 Bug 1：大多数用户权限正常时「桌面小组件」与「上课提醒」
      // 之间的线比别处粗一倍）。
      if (i > 0 &&
          rows[i] is! _PermissionAlertTile &&
          rows[i - 1] is! _PermissionAlertTile)
        const Divider(height: 1, thickness: 1),
      rows[i],
    ],
  ];
}

/// 上课提醒入口顶部的权限自检条（WB_SPEC_218 第 ④ 节）。
///
/// 读一次三项权限（通知 / 精确闹钟 / 电池优化）：有异常时渲染一条高亮的
/// 「权限异常，点击修复」行，点进权限自检页；全部正常、读取中或查询失败时
/// 渲染 [SizedBox.shrink]（隐藏，不占位、不打扰）。
class _PermissionAlertTile extends ConsumerStatefulWidget {
  const _PermissionAlertTile();

  @override
  ConsumerState<_PermissionAlertTile> createState() => _PermissionAlertTileState();
}

class _PermissionAlertTileState extends ConsumerState<_PermissionAlertTile> {
  bool _abnormal = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final s = await PermissionService.instance.status();
      if (mounted && !s.allGranted) setState(() => _abnormal = true);
    } catch (_) {
      // 查询失败（平台通道缺失/异常）按「无异常」处理，不打扰、不闪退
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_abnormal) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    // 可见时自带上下两条分隔线（_divideRows 不替它画，见该函数注释）；
    // 隐藏时整条消失、不留线。
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1, thickness: 1),
        ListTile(
          leading: Icon(Icons.error_outline, color: scheme.error),
          title: Text(
            '权限异常，点击修复',
            style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, '/settings-permissions'),
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }
}
