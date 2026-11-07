import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/permission_service.dart';
import '../utils/route_observer.dart';
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
/// - 第二组「展示与桌面」：外观与底栏、桌面小组件、上课提醒（提醒开了但缺
///   权限时，行尾挂柔和琥珀色「待完善」徽标；提醒没开时不检查不显示）。
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
            // WB_SPEC_219：节次时间设置入口从外观二级页移入设置首页「课表与学期」组
            const _EntryTile(
              icon: Icons.schedule_outlined,
              title: '节次时间设置',
              subtitle: '自定义每节课上下课时间',
              route: '/time-settings',
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
            // 上课提醒入口行：提醒没开时不检查权限、不显示任何提示；提醒开了
            // 但缺权限时，行尾挂柔和琥珀色「待完善」徽标（见 _ReminderEntryTile）。
            _ReminderEntryTile(subtitle: reminderSubtitle),
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
  ///
  /// 位置与圆角（Argon 方案 Q7 + 复查 Bug 2）：offset 左移 8dp、下沉 48dp，
  /// 菜单顶落在顶栏底（toolbarHeight 48）之下，打开后仍能看到顶栏；
  /// 圆角 16dp；背景浅色 surfaceContainerHigh／深色 surfaceContainer，
  /// 阴影浅 6／深 8。
  Widget _buildMoreMenu(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert),
      // 复查 Bug 2：M3 下菜单顶 = ⋮ 按钮顶 + offset.dy；按钮贴顶栏顶，
      // dy=10 时菜单顶才 10，盖住顶栏约 34dp。dy 取顶栏高 48，菜单顶
      // 正好落在顶栏底之下（见 settings_page_test「⋮ 菜单」位置断言）。
      offset: const Offset(-8, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: dark ? scheme.surfaceContainer : scheme.surfaceContainerHigh,
      elevation: dark ? 8 : 6,
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
      if (i > 0) const Divider(height: 1, thickness: 1),
      rows[i],
    ],
  ];
}

/// 上课提醒入口行（Argon 方案 Q3）。
///
/// 提醒没开时不检查权限、不显示任何提示；提醒开了但缺权限时，只在行尾挂
/// 一个柔和琥珀色胶囊小徽标「待完善」，点行进提醒设置页修复。旧的顶部
/// 独立权限异常红条已删（太突兀）。
class _ReminderEntryTile extends ConsumerStatefulWidget {
  const _ReminderEntryTile({required this.subtitle});

  final String subtitle;

  @override
  ConsumerState<_ReminderEntryTile> createState() => _ReminderEntryTileState();
}

class _ReminderEntryTileState extends ConsumerState<_ReminderEntryTile>
    with WidgetsBindingObserver, RouteAware {
  /// 提醒开了且权限有缺失时为 true，行尾挂「待完善」徽标。
  ///
  /// 双向更新（复查 Bug 3）：每次查询都按最新 allGranted 重写，补授权后
  /// 返回徽标消失；查询失败也不锁死，下次触发会再查。
  bool _needsAttention = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后查一次（provider 此时可能未就绪，_checkIfNeeded 内现读现判）
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置回来（去开权限时应用会切后台）重新查询
    if (state == AppLifecycleState.resumed) _checkIfNeeded();
  }

  @override
  void didPopNext() {
    // 从提醒设置子页回来重新查询：补授权后徽标消失
    _checkIfNeeded();
  }

  /// 提醒开了才查权限；结果双向写回 _needsAttention，失败不锁死。
  Future<void> _checkIfNeeded() async {
    final enabled =
        ref.read(reminderSettingsProvider).value?.enabled ?? false;
    if (!enabled) {
      if (mounted) setState(() => _needsAttention = false);
      return;
    }
    try {
      final s = await PermissionService.instance.status();
      if (mounted) setState(() => _needsAttention = !s.allGranted);
    } catch (_) {
      // 查询失败（平台通道缺失/异常）按「无异常」处理，不打扰、不闪退；
      // 不锁死：下次开关变化/页面恢复/回到本页时会再查
      if (mounted) setState(() => _needsAttention = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminder = ref.watch(reminderSettingsProvider).value;
    final enabled = reminder?.enabled ?? false;
    // 提醒开关变化时重查（关→开且缺权限要出现徽标；开→关要清掉徽标）。
    // 不在 build 里直接发查询（复查优化 3）：只挂监听，查询走生命周期。
    ref.listen(reminderSettingsProvider, (_, _) => _checkIfNeeded());
    final showBadge = enabled && _needsAttention;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      // 2.0.7 Taste 化：标题字重 medium，副标题沿用主题次要颜色与字号
      title: const Text('上课提醒', style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(widget.subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBadge)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '待完善',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.brightness == Brightness.dark
                      ? const Color(0xFFFFD54F)
                      : const Color(0xFF8D6E00),
                ),
              ),
            ),
          if (showBadge) const SizedBox(width: 6),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.pushNamed(context, '/settings-reminders'),
    );
  }
}
