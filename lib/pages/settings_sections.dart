import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/backup_service.dart';
import '../services/fonts_service.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/permission_service.dart';
import '../services/widget_service.dart';
import '../ui/app_select_field.dart';
import '../ui/app_styles.dart';
import '../ui/grid_metrics.dart';
import '../ui/settings_icon_box.dart';
import '../ui/settings_entry_row.dart';
import '../ui/settings_line_frame.dart';
import '../utils/backup_codec.dart';
import '../utils/color_schemes.dart';
import '../utils/ics_export.dart';
import '../utils/morandi_palette.dart';
import '../utils/override_effect.dart';
import '../utils/slot_layout.dart';
import '../widgets/app_dialog.dart';
import '../widgets/course_card.dart';
import '../widgets/empty_state.dart';

/// 设置分类子页（WB_SPEC_205 第 1 节·QQ 式分级）
///
/// 设置首页只留分组标题 + 每类一行入口，点进分类才到本文件的各子页。
/// 这些子页里的控件与业务逻辑全部从 settings_page.dart **原样搬来**（搬家），
/// 不许丢项、不许改行为：
/// - [SemesterSettingsPage]（/settings-semester）：学期名称 / 开学日期 / 总周数
/// - [AppearanceSettingsPage]（/settings-appearance）：实时预览 + 8 行入口（WB_SPEC_228）
/// - [RemindersSettingsPage]（/settings-reminders）：上课提醒 / 上课播报 / 常驻通知 / 提前提醒
/// - [DataSettingsPage]（/settings-data）：导入 / 学期管理 / 备份 / 恢复 / 导出 ICS / 数据管理
/// - [PermissionsSettingsPage]（/settings-permissions）：原 `_PermissionSummaryTile` 内容
/// - [WidgetSettingsPage]（/settings-widget）：桌面小组件说明 + 立即刷新桌面小部件 / 部件状态（WB_SPEC_219）
///
/// 2.0.7（WB_SPEC_208 第 2 节）Taste 化只动布局与层级：同一节内连续行之间用 1px
/// 分隔线（现有主题 dividerColor）、节与节之间间距统一 24（`AppSpacing.group`）、
/// 节标题主文字色 + semibold、行标题 medium。设置项、顺序、默认值、保存逻辑、
/// 校验、跳转、控件类型与颜色一律不动。

/// 实时预览「今天整列边框」覆盖层的 Key：测试据此断言开关开/关时该层的有无。
const Key kPreviewTodayHighlightKey = ValueKey('preview_today_highlight');

/// 外观页「切换动效」某个选项的 Key（2026-11-05：三种动效做成开关）。
///
/// 测试据此取 ChoiceChip，断言选中态与切换后的持久化。
Key shellTransitionChipKey(ShellTransitionStyle style) =>
    ValueKey('shell_transition_${style.id}');

/// 把同一组内连续行用轻量分隔线隔开（与 settings_page 的 Taste 口径一致）。
///
/// WB_SPEC_222：分隔线 thickness 0.5、outlineVariant 20%，对齐标题文字左缘。
/// 组内行都有 leading 槽时文字左缘在 x=72（ListTile 标题起始位置是
/// max(minLeadingWidth=40, leading 宽) + horizontalTitleGap=16，再加内容边距左 16；
/// Argon 给的 64 漏算了 40dp leading 槽宽，已纠正），此时 indent 取 72。
/// 组内行没有 leading（如 _SliderRow、无 secondary 的 SwitchListTile）时文字左缘
/// 在 x=16，调用处须传 indent: 16，否则分隔线会越过文字左缘（222 复审 Bug 4）。
/// 只作用于「行与行之间」，节标题、预览、下拉、色板等非行控件不走这里。
List<Widget> _divideRows(ColorScheme scheme, List<Widget> rows,
    {double indent = 72}) {
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0)
        Divider(
          height: 1,
          thickness: 0.5,
          color: scheme.outlineVariant.withValues(alpha: 0.2),
          indent: indent,
          endIndent: 16,
        ),
      rows[i],
    ],
  ];
}

/// 行尾小箭头（WB_SPEC_222：20dp、onSurfaceVariant 60%）。
///
/// 单独成组件是因为各行处于不同的 builder 作用域（Consumer 的 ctx、
/// FutureBuilder 的 ctx 等），直接取 Theme 不方便。
class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right,
      size: 20,
      color: Theme.of(context)
          .colorScheme
          .onSurfaceVariant
          .withValues(alpha: 0.6),
    );
  }
}

/// 学期设置子页：学期名称（只读）、开学日期、总周数
class SemesterSettingsPage extends ConsumerWidget {
  const SemesterSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semesterAsync = ref.watch(currentSemesterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('学期设置'), centerTitle: true),
      body: semesterAsync.when(
        data: (semester) => ListView(
          children: _divideRows(Theme.of(context).colorScheme, [
            ListTile(
              leading: const SettingsIconBox(icon: Icons.badge_outlined, category: SettingsIconCategory.schedule),
              title: const Text(
                '学期名称',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(semester.name),
            ),
            ListTile(
              leading: const SettingsIconBox(icon: Icons.event_outlined, category: SettingsIconCategory.schedule),
              title: const Text(
                '开学日期',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('${semester.startDate}（自动对齐到当周周一）'),
              trailing: const _Chevron(),
              onTap: () => _pickStartDate(context, ref, semester.startDate),
            ),
            ListTile(
              leading: const SettingsIconBox(icon: Icons.view_week_outlined, category: SettingsIconCategory.schedule),
              title: const Text(
                '总周数',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('${semester.totalWeeks} 周'),
              trailing: const _Chevron(),
              onTap: () => _editTotalWeeks(context, ref, semester.totalWeeks),
            ),
          ]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        // 数据库异常兜底：图标 + 中文说明 + 重试入口，不允许白屏/闪退
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '设置加载失败',
          message: '$e',
          actionLabel: '重试',
          onAction: () => ref.read(currentSemesterProvider.notifier).reload(),
        ),
      ),
    );
  }

  Future<void> _pickStartDate(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final initial = DateTime.tryParse(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择开学日期',
    );
    if (picked == null) return;
    final old = ref.read(currentSemesterProvider).value;
    if (old == null) return;
    try {
      // 走学期管理页「编辑学期」的同一个入口（2.0.0 复审 C3）：改库 → 同步内存
      // → 刷列表 → 浏览周钳制 → 提醒重排 / 常驻通知 / 小部件三联动，
      // 与管理页改同一门数据走同一条路，口径不再分叉
      await ref.read(semestersProvider.notifier).updateSemester(
            old.copyWith(startDate: DateFormat('yyyy-MM-dd').format(picked)),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('开学日期已更新')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  Future<void> _editTotalWeeks(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final controller = TextEditingController(text: '$current');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AppDialog(
        title: '设置总周数',
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '如 20', suffixText: '周'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 1 || v > 30) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text('请输入 1~30 之间的周数')));
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final notifier = ref.read(currentSemesterProvider.notifier);
    final old = ref.read(currentSemesterProvider).value;
    if (old == null) return;
    try {
      await notifier.updateSemester(old.copyWith(totalWeeks: result));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('总周数已更新')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }
}

/// 外观子页（WB_SPEC_219 第 2 节）：实时预览置页首，其余条目按 4 组重排。
///
/// 预览吸顶（SliverPersistentHeader）与现有「ListView + 单一 _AppearanceGroup」
/// 结构冲突：预览高度动态依赖 ui.cellHeight（44–96）与 columnCount，改造成
/// slivers 需拆分预览网格参数计算、并会改动现有 widget 测试依赖的 ListView 结构。
/// 按规格书 2.2 允许的退路，退为「页面第 1 项不吸顶」：预览区仍是列表首个
/// 可视块，网格参数计算逻辑原样留在 [_AppearanceGroup] 内，未搬动。
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观'), centerTitle: true),
      body: ListView(
        children: const [_AppearanceGroup()],
      ),
    );
  }
}

/// 提醒子页：上课提醒 / 上课播报 / 今日课程常驻通知 / 提前提醒
///
/// WB_SPEC_231 第 4.2–4.4 节起改成「用到时才申请权限」：
/// - 上课提醒、今日课程常驻通知两个开关在打开前先查通知权限，被拒时开关保持
///   关闭并弹带引导的确认框（不再出现「开关亮着、提醒收不到」的假开启）；
/// - 精确闹钟未授权时开关仍保持开（照旧降级为非精确排期），开关行下方常驻一行
///   轻量提示，点按跳系统「闹钟和提醒」页，授权后自动消失；
/// - 首次成功开启提醒后只提示一次电池优化（标记 `battery_hint_shown`）。
class RemindersSettingsPage extends ConsumerStatefulWidget {
  const RemindersSettingsPage({super.key});

  @override
  ConsumerState<RemindersSettingsPage> createState() =>
      _RemindersSettingsPageState();
}

class _RemindersSettingsPageState extends ConsumerState<RemindersSettingsPage>
    with WidgetsBindingObserver {
  /// 电池优化轻提示的一次性标记键（只写 '1'）
  static const String _batteryHintKey = 'battery_hint_shown';

  /// 精确闹钟当前未授权（只有在提醒开关已开时才展示那条轻量提示）
  bool _exactAlarmMissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshExactAlarmState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页授权回来（经 Home 切回，不经过拨开关/点提示的路径）时补刷一次，
  /// 否则已授权了降级提示行还残留着（Kimi 复审 Bug 5）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshExactAlarmState();
  }

  /// 查一次精确闹钟状态：进页面时、每次拨动提醒开关后、从系统页返回后
  Future<void> _refreshExactAlarmState() async {
    bool exact;
    try {
      exact = await NotificationService.instance.canScheduleExact();
    } catch (e) {
      // 插件没就绪（测试环境 / 通道异常）时查不出来：按「已授权」处理，
      // 宁可不显示降级提示，也不要让设置页崩在这里
      debugPrint('读取精确闹钟状态失败：$e');
      exact = true;
    }
    if (!mounted) return;
    setState(() => _exactAlarmMissing = !exact);
  }

  @override
  Widget build(BuildContext context) {
    // WB_SPEC_222：组内分隔线颜色取自当前主题。
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('提醒'), centerTitle: true),
      body: ListView(
        children: [
          Consumer(
            builder: (ctx, ref, _) {
              final settings = ref.watch(reminderSettingsProvider);
              return settings.when(
                data: (s) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      secondary: const SettingsIconBox(icon: Icons.notifications_active_outlined, category: SettingsIconCategory.reminder),
                      title: const _InfoTitle(
                        title: '上课提醒',
                        message: '每节课提前提醒，App 被杀后也能准时响铃',
                      ),
                      value: s.enabled,
                      onChanged: (v) => _onReminderToggle(v),
                    ),
                    // 精确闹钟未授权且提醒已开：轻量提示，点按跳系统「闹钟和提醒」页
                    if (s.enabled && _exactAlarmMissing) _exactAlarmHint(scheme),
                  ],
                ),
                loading: () => const ListTile(
                  leading: SettingsIconBox(icon: Icons.notifications_active_outlined, category: SettingsIconCategory.reminder),
                  title: Text('上课提醒'),
                  subtitle: Text('加载中…'),
                ),
                error: (e, _) => ListTile(
                  leading: const SettingsIconBox(icon: Icons.notifications_active_outlined, category: SettingsIconCategory.reminder),
                  title: const Text('上课提醒'),
                  subtitle: Text('加载失败：$e'),
                ),
              );
            },
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          // 上课播报（2.0.2 起从「外观」页归入提醒组）：主页顶部状态条开关
          Consumer(
            builder: (ctx, ref, _) {
              final ui =
                  ref.watch(uiSettingsProvider).value ?? const UiSettings();
              return SwitchListTile(
                secondary: const SettingsIconBox(icon: Icons.campaign_outlined, category: SettingsIconCategory.reminder),
                title: const _InfoTitle(
                  title: '上课播报',
                  message: '主页顶部显示当前/下一节课状态条，默认关',
                ),
                value: ui.showClassBroadcast,
                onChanged: (v) => ref
                    .read(uiSettingsProvider.notifier)
                    .apply(ui.copyWith(showClassBroadcast: v)),
              );
            },
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          Consumer(
            builder: (ctx, ref, _) {
              final enabled = ref.watch(ongoingNoticeSettingsProvider);
              return enabled.when(
                data: (on) => SwitchListTile(
                  secondary: const SettingsIconBox(icon: Icons.pin_outlined, category: SettingsIconCategory.reminder),
                  title: const _InfoTitle(
                    title: '今日课程常驻通知',
                    message: '通知栏常驻显示今日剩余或明日课程预告',
                  ),
                  value: on,
                  onChanged: (v) => _onOngoingToggle(v),
                ),
                loading: () => const ListTile(
                  leading: SettingsIconBox(icon: Icons.pin_outlined, category: SettingsIconCategory.reminder),
                  title: Text('今日课程常驻通知'),
                  subtitle: Text('加载中…'),
                ),
                error: (e, _) => ListTile(
                  leading: SettingsIconBox(icon: Icons.pin_outlined, category: SettingsIconCategory.reminder),
                  title: const Text('今日课程常驻通知'),
                  subtitle: Text('加载失败：$e'),
                ),
              );
            },
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          Consumer(
            builder: (ctx, ref, _) {
              final advance =
                  ref.watch(reminderSettingsProvider).value?.advanceMinutes ??
                  15;
              return ListTile(
                leading: const SettingsIconBox(icon: Icons.timer_outlined, category: SettingsIconCategory.reminder),
                title: const Text(
                  '提前提醒',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text('提前 $advance 分钟'),
                trailing: const _Chevron(),
                onTap: () => _pickAdvanceMinutes(ctx, ref),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 精确闹钟降级提示：一行轻量文字（字号/字色沿用设置页副标题口径），点按跳设置
  Widget _exactAlarmHint(ColorScheme scheme) {
    return InkWell(
      onTap: () async {
        await PermissionService.instance.openExactAlarmSettings();
        await _refreshExactAlarmState();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: scheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '精确闹钟未授权，提醒可能延迟几分钟',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 上课提醒开关：严格两步事务（WB_SPEC_231 第 4.2 节）
  ///
  /// 第一步通知权限被拒 → 开关**绝不**变成 true（不写库），弹带引导的确认框；
  /// 第二步通知通过后先落库（开关正式变 true），再查精确闹钟——未授权只降级为
  /// 非精确排期 + 常驻轻量提示，开关保持开。
  Future<void> _onReminderToggle(bool value) async {
    final notifier = ref.read(reminderSettingsProvider.notifier);
    if (!value) {
      // 关闭：直接落库，不申请权限、不弹框（规格第 4.2 节末）
      await notifier.setEnabled(false);
      return;
    }
    // 第一步：核心必选权限——通知
    final granted =
        await NotificationService.instance.ensureNotificationPermission();
    if (!granted) {
      if (!mounted) return;
      final go = await showAppConfirmDialog(
        context,
        title: '需要通知权限',
        message: '需要开启通知权限才能发送上课提醒，是否前往系统设置开启？',
        confirmLabel: '去设置',
        cancelLabel: '暂不',
      );
      if (go == true) await PermissionService.instance.openAppDetails();
      return;
    }
    // 第二步：增强权限——精确闹钟（先落库，开关正式变 true）
    await notifier.setEnabled(true);
    if (!mounted) return;
    await _refreshExactAlarmState();
    if (_exactAlarmMissing && mounted) {
      await _showExactAlarmGuide(context);
    }
    await _maybeShowBatteryHint();
  }

  /// 今日课程常驻通知开关：与上课提醒第一步同一套事务（WB_SPEC_231 第 4.3 节）
  ///
  /// 只在用户手动拨开关时检查权限——进主页时不弹、不申请（否则又变回冷启动
  /// 要权限）；Android 13+ 全新安装默认值 true 但没权限时发不出通知属正常现象。
  Future<void> _onOngoingToggle(bool value) async {
    final notifier = ref.read(ongoingNoticeSettingsProvider.notifier);
    if (!value) {
      await notifier.setEnabled(false);
      return;
    }
    final granted =
        await NotificationService.instance.ensureNotificationPermission();
    if (!granted) {
      if (!mounted) return;
      final go = await showAppConfirmDialog(
        context,
        title: '需要通知权限',
        message: '需要开启通知权限才能在通知栏常驻显示今日课程，是否前往系统设置开启？',
        confirmLabel: '去设置',
        cancelLabel: '暂不',
      );
      if (go == true) await PermissionService.instance.openAppDetails();
      return;
    }
    await notifier.setEnabled(true);
  }

  /// 电池优化轻提示：只在**首次**成功开启提醒后出现一次（规格第 4.4 节）
  ///
  /// 跳系统电池优化列表页（ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS），
  /// 所以文案写「在列表里找到小马课表设为不优化」，不承诺一键搞定。
  Future<void> _maybeShowBatteryHint() async {
    if (!mounted) return;
    try {
      final shown = await Dao.instance.getSetting(_batteryHintKey);
      if (shown == '1') return;
      await Dao.instance.setSetting(_batteryHintKey, '1');
    } catch (e) {
      // 标记读写失败就让提示再来一次，绝不影响开关本身
      debugPrint('电池优化提示标记读写失败：$e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '为防止系统后台清理导致漏报，建议在电池优化列表里把小马课表设为「不优化」',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '去设置',
          onPressed: () => PermissionService.instance.openBatterySettings(),
        ),
      ),
    );
  }

  /// 精确闹钟授权引导对话框（拒绝也不闪退，只是提醒可能延迟）
  Future<void> _showExactAlarmGuide(BuildContext context) async {
    final go = await showAppConfirmDialog(
      context,
      title: '开启精确闹钟',
      message: '为保证 App 被杀后提醒仍准时，请在系统设置中允许「闹钟和提醒」权限。'
          '拒绝也可继续，但提醒可能略有延迟。',
      confirmLabel: '去设置',
      cancelLabel: '暂不',
    );
    if (go == true) {
      // requestExactAlarmsPermission 会跳系统「闹钟和提醒」设置页
      await NotificationService.instance.requestExactAlarmPermission();
      await _refreshExactAlarmState();
    }
  }

  /// 提前分钟选择（5/10/15/30，默认 15）
  Future<void> _pickAdvanceMinutes(BuildContext context, WidgetRef ref) async {
    const options = [5, 10, 15, 30];
    final current =
        ref.read(reminderSettingsProvider).value?.advanceMinutes ?? 15;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const ListTile(
              title: Text(
                '提前提醒时间',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final o in options)
              ListTile(
                title: Text('$o 分钟'),
                trailing: o == current
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, o),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref
          .read(reminderSettingsProvider.notifier)
          .setAdvanceMinutes(picked);
    }
  }
}

/// 数据备份与换机子页：导入课表 / 学期管理 / 备份到文件 / 从备份恢复 /
/// 导出课表（ICS）/ 数据管理，共 6 行（2.0.2 起由「高级与数据」拆解并入；
/// 2.1.7 WB_SPEC_218 第 ③/④ 节改名为「数据备份与换机」，顶部加纯本地存储提示条）。
class DataSettingsPage extends ConsumerWidget {
  const DataSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // WB_SPEC_222：组内分隔线颜色取自当前主题。
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与换机'), centerTitle: true),
      body: ListView(
        children: [
          // 2.1.7（WB_SPEC_218 第 ③ 节）：删云同步后的纯本地存储说明，
          // 顶部 InfoBanner 常驻提示换机/重装前先导出备份，不弹全屏公告。
          const _LocalOnlyInfoBanner(),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.upload_file_outlined, category: SettingsIconCategory.data),
            title: const _InfoTitle(
              title: '导入课表',
              message: 'ICS / 图片 OCR / PDF 导入，支持冲突检测',
            ),
            trailing: const _Chevron(),
            onTap: () => Navigator.pushNamed(context, '/import'),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.school_outlined, category: SettingsIconCategory.data),
            title: const _InfoTitle(
              title: '学期管理',
              message: '新建、切换或删除学期',
            ),
            trailing: const _Chevron(),
            onTap: () => Navigator.pushNamed(context, '/semester-manage'),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.backup_outlined, category: SettingsIconCategory.data),
            title: const _InfoTitle(
              title: '备份到文件',
              message: '导出全部数据为 JSON 文件，换机/重装可恢复',
            ),
            trailing: const _Chevron(),
            onTap: () => _exportBackup(context),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.restore_outlined, category: SettingsIconCategory.data),
            title: const _InfoTitle(
              title: '从备份恢复',
              message: '选择备份 JSON，恢复前会再次确认（覆盖现有数据）',
            ),
            trailing: const _Chevron(),
            onTap: () => _restoreBackup(context, ref),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.calendar_month_outlined, category: SettingsIconCategory.data),
            title: const _InfoTitle(
              title: '导出课表（ICS）',
              message: '当前学期课表导出为日历文件，可分享或导入其他日历 App',
            ),
            trailing: const _Chevron(),
            onTap: () => _exportIcs(context, ref),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.sd_storage_outlined, category: SettingsIconCategory.data),
            title: const _InfoTitle(
              title: '数据管理',
              message: '存储占用、备份快捷入口与恢复出厂',
            ),
            trailing: const _Chevron(),
            onTap: () => Navigator.pushNamed(context, '/data-manage'),
          ),
        ],
      ),
    );
  }

  /// 备份提示的附加文案（如某个字体超限没写进备份）；没有提示时为空串
  String _warnText(List<String> warnings) =>
      warnings.isEmpty ? '' : '\n${warnings.join('\n')}';

  /// 导出 JSON 全量备份：读库组装（含自定义字体）→ 用户选保存位置 → 落盘。
  /// 用户取消（返回 null）不算失败，静默返回。
  Future<void> _exportBackup(BuildContext context) async {
    try {
      final bundle = await BackupService.instance.buildBackup(
        now: DateTime.now(),
      );
      // 缩进美化：备份要人肉应急查看/修改时更可读，体积代价可忽略
      const pretty = JsonEncoder.withIndent('  ');
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final path = await BackupService.instance.saveTextFile(
        fileName: '小马课表备份_$stamp.json',
        content: pretty.convert(bundle.json),
        extension: 'json',
      );
      if (path == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已保存到：$path${_warnText(bundle.warnings)}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份导出失败：$e')));
      }
    }
  }

  /// 恢复备份后：提醒重排 → 常驻通知重建 + 排链（串行，理由见调用处注释）
  Future<void> _refreshNoticesAfterRestore() async {
    try {
      await NotificationService.instance.rescheduleAll();
      await OngoingNoticeService.instance.refresh();
    } catch (e) {
      debugPrint('恢复备份后刷新通知失败：$e');
    }
  }

  /// 从备份恢复：选文件 → 内存校验 → 二次确认（覆盖现有数据）→ 单事务恢复。
  /// 校验发生在确认弹窗之前，因此格式错误时数据库完全没被碰过，现有数据无损。
  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    try {
      final path = await BackupService.instance.pickJsonFile();
      if (path == null) return;
      final data = await BackupService.instance.readBackup(path);
      if (!context.mounted) return;

      // 二次确认：恢复是覆盖式操作且不可撤销，必须让用户明确知晓代价
      final confirmed = await showAppConfirmDialog(
        context,
        title: '确认恢复备份？',
        message: '备份中包含 ${data.semesters.length} 个学期、${data.courses.length} 门课程'
            '${data.courseOverrides.isEmpty ? '' : '、${data.courseOverrides.length} 条调课记录'}。'
            '\n\n恢复会覆盖现有全部数据（含节次时间与设置），且无法撤销。',
        confirmLabel: '覆盖并恢复',
        destructive: true,
      );
      if (confirmed != true || !context.mounted) return;

      // 恢复期间用对话框遮罩，防止重复点击或误以为卡死
      final closing = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AppDialog(
          title: '正在恢复',
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('正在恢复…'),
            ],
          ),
        ),
      );
      RestoreSummary? summary;
      Object? error;
      try {
        summary = await BackupService.instance.restore(data);
      } catch (e) {
        error = e;
      }
      // 无论成败先关进度框；事务失败会整体回滚，现有数据完好
      if (context.mounted) Navigator.of(context).pop();
      await closing;
      if (error != null || summary == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('恢复失败：$error\n现有数据未受影响，可放心重试')),
          );
        }
        return;
      }

      // 刷新所有读库的 Provider：app_settings 也被覆盖，
      // 主题/提醒/常驻通知设置必须一并重建，否则界面还停留在旧设置
      ref.invalidate(currentSemesterProvider);
      ref.invalidate(semestersProvider);
      ref.invalidate(timeSlotsProvider);
      ref.invalidate(coursesProvider);
      ref.invalidate(themeSettingsProvider);
      ref.invalidate(reminderSettingsProvider);
      ref.invalidate(ongoingNoticeSettingsProvider);
      ref.invalidate(notesProvider);
      ref.invalidate(courseOverridesProvider);
      ref.invalidate(segmentSettingsProvider);
      ref.invalidate(uiSettingsProvider);
      ref.read(displayWeekProvider.notifier).goToday();
      // 通知/常驻通知/小组件基于恢复后的数据重排刷新（内部均已捕获异常）。
      // 提醒重排与常驻通知重建必须串行：rescheduleAll 的 cancelAll 会连课程常驻
      // 通知一起清掉，并行时谁后到谁说了算（WB_SPEC_229 第 6.3 节）
      unawaited(WidgetService.instance.refreshWidgets());
      unawaited(_refreshNoticesAfterRestore());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '恢复完成：${summary.semesters} 个学期、'
              '${summary.courses} 门课程'
              '${summary.courseOverrides > 0 ? '、${summary.courseOverrides} 条调课记录' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      // 文件读取/解析阶段的失败：数据库尚未被触碰，现有数据完好
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败：$e\n现有数据未受影响，可放心重试')),
        );
      }
    }
  }

  /// 导出当前学期课表为 ICS 日历文件（逐周展开，每次上课一个事件）
  Future<void> _exportIcs(BuildContext context, WidgetRef ref) async {
    final semester = ref.read(currentSemesterProvider).value;
    if (semester == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('尚未加载当前学期，请稍后再试')));
      return;
    }
    final courses = ref.read(coursesProvider).value;
    if (courses == null || courses.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前学期没有课程，无需导出')));
      return;
    }
    try {
      final result = IcsExporter.build(
        semester: semester,
        courses: courses,
        slots: ref.read(timeSlotsProvider).value ?? const [],
        now: DateTime.now(),
      );
      // 学期名进入文件名，过滤文件系统非法字符（Windows 同步盘也可能存这份文件）
      final safeName = semester.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = await BackupService.instance.saveTextFile(
        fileName: '小马课表_${safeName}_课表.ics',
        content: result.content,
        extension: 'ics',
      );
      if (path == null) return;
      var msg = '已导出 ${result.eventCount} 节课：$path';
      if (result.skippedCount > 0) {
        msg += '\n（另有 ${result.skippedCount} 次因节次时间缺失被跳过）';
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ICS 导出失败：$e')));
      }
    }
  }
}

/// 纯本地存储提示条（WB_SPEC_218 第 ③ 节）：数据备份与换机页顶部的常驻说明。
///
/// 删云同步后 App 不再往云端同步数据，换机靠手动备份恢复。这条提示在备份页
/// 顶部常驻说明，不弹全屏公告，也不阻断任何操作。
class _LocalOnlyInfoBanner extends StatelessWidget {
  const _LocalOnlyInfoBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '小马课表采用纯本地隐私存储，不包含云端同步。换机或重装应用前，'
              '请点击下方「备份到文件」并保存至微信文件传输助手或系统下载目录。',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 权限子页：原 [_PermissionSummaryTile] 的内容搬进来，首页只留一行入口
class PermissionsSettingsPage extends StatelessWidget {
  const PermissionsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('权限'), centerTitle: true),
      body: ListView(children: [const _PermissionSummaryTile()]),
    );
  }
}

/// 桌面小组件子页：说明文字搬进来，首页只留一行入口
class WidgetSettingsPage extends StatelessWidget {
  const WidgetSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // WB_SPEC_222：组内分隔线颜色取自当前主题。
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件'), centerTitle: true),
      body: ListView(
        children: [
          ListTile(
            leading: const SettingsIconBox(icon: Icons.widgets_outlined, category: SettingsIconCategory.appearance),
            title: Text(
              '今日课程小组件',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('在桌面长按空白处 →「小组件」→ 找到「小马课表」，即可添加今日课程小组件'),
          ),
          // WB_SPEC_219：从外观页移入「立即刷新桌面小部件」「部件状态」，
          // 追加在「今日课程小组件」说明行之后，中间用 0.5 Divider 隔开；
          // 两项 onTap 逻辑、SnackBar 文案、FutureBuilder 逻辑一字不动。
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          ListTile(
            leading: const SettingsIconBox(icon: Icons.widgets_outlined, category: SettingsIconCategory.appearance),
            title: const _InfoTitle(
              title: '立即刷新桌面小部件',
              message: '把最新课程重新推送到桌面小部件',
            ),
            onTap: () async {
              await WidgetService.instance.refreshWidgets();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已推送。若桌面仍不显示，长按小部件删除后重新添加一次即可')),
              );
            },
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: scheme.outlineVariant.withValues(alpha: 0.2),
            indent: 72,
            endIndent: 16,
          ),
          // 部件自检状态（1.2.7）：Provider 回写的上次更新记录
          FutureBuilder<({int ts, int ids, String? error})>(
            future: WidgetService.instance.debugStatus(),
            builder: (ctx, snap) {
              final d = snap.data;
              if (d == null || d.ts == 0) {
                return const ListTile(
                  leading: SettingsIconBox(icon: Icons.info_outline, category: SettingsIconCategory.system),
                  title: Text(
                    '部件状态',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text('还没有收到小部件的更新记录（先添加一个桌面小部件）'),
                );
              }
              final t = DateTime.fromMillisecondsSinceEpoch(d.ts);
              final hh = t.hour.toString().padLeft(2, '0');
              final mm = t.minute.toString().padLeft(2, '0');
              return ListTile(
                leading: const SettingsIconBox(icon: Icons.info_outline, category: SettingsIconCategory.system),
                title: const Text(
                  '部件状态',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  d.error == null
                      ? '上次更新 $hh:$mm · 共 ${d.ids} 个小部件 · 无异常'
                      : '上次更新 $hh:$mm · 共 ${d.ids} 个小部件 · 异常：${d.error}',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 权限入口行：显示「已授权 x / 3」摘要。
///
/// 2.0.2 起随「高级与数据」拆解单列在设置页一级页面（原 advanced_page.dart）。
/// 2.0.5 起随 QQ 式整顿搬进权限子页（首页只留一行入口）。
/// 状态查询是一次平台通道调用，因此只在 initState 里发起一次（放在 build 里
/// 会让每次重建都查一遍）；从权限页返回时再查一次，用户在系统里改完立即可见。
class _PermissionSummaryTile extends StatefulWidget {
  const _PermissionSummaryTile();

  @override
  State<_PermissionSummaryTile> createState() => _PermissionSummaryTileState();
}

class _PermissionSummaryTileState extends State<_PermissionSummaryTile> {
  late Future<PermissionSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = PermissionService.instance.status();
  }

  Future<void> _open() async {
    await Navigator.pushNamed(context, '/permissions');
    if (!mounted) return;
    setState(() => _future = PermissionService.instance.status());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PermissionSnapshot>(
      future: _future,
      builder: (ctx, snap) {
        final s = snap.data;
        return ListTile(
          leading: const SettingsIconBox(icon: Icons.shield_outlined, category: SettingsIconCategory.schedule),
          title: const Text(
            '权限',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            s == null
                ? '正在读取…'
                : '通知 ${s.notification ? '已授权' : '未授权'} · '
                    '闹钟 ${s.exactAlarm ? '已授权' : '未授权'} · '
                    '电池 ${s.battery ? '已授权' : '未授权'}',
          ),
          trailing: const _Chevron(),
          onTap: _open,
        );
      },
    );
  }
}

/// 外观分组（2.0.3 起由原「外观」二级页平铺进设置首页，2.0.5 起随 QQ 式整顿
/// 整体搬进外观子页 [AppearanceSettingsPage]）：
/// 外观页重组后的全部条目（WB_SPEC_219 第 2 节）：
/// 页首实时预览 + 4 个分组（色彩与主题 / 课表网格与表头 / 课程卡片样式与字体 /
/// 导航与交互动效）。只移动位置与分组，控件、provider、字段、行为原样。
/// 节次时间入口移到设置首页；立即刷新桌面小部件、部件状态移到 WidgetSettingsPage。
/// 外观父页（WB_SPEC_228 §3）：只剩 1 个实时预览 + 8 行入口。
///
/// 全部细节控件按 §4 对照表搬进 4 个专项子页；父页不再出现宫格、滑杆、
/// 竖排三按钮，只保留导航入口与两个留在本页的控件（深浅模式、底部栏开关）。
/// 三处 Argon 第四轮补齐：主题色收成行（宫格进 BottomSheet）、同步链收进
/// 课程配色面板底部、切换动效收成单行（选项进 BottomSheet）。
class _AppearanceGroup extends ConsumerWidget {
  const _AppearanceGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    void apply(UiSettings next) => notifier.apply(next);

    // provider 未加载完（首帧）时按跟随系统显示，加载后自动到位
    final themeMode =
        ref.watch(themeSettingsProvider).value ?? ThemeMode.system;
    final themeLabel = ui.themeCustomColor != null
        ? '自定义'
        : themePresetById(ui.themePresetId).name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // §3：顶部实时预览卡片，不吸顶（随页面滚动）；卡片本身有边框，不另加框
        const AppearancePreviewCard(),

        // ── 第 1 组「色彩与字体」4 行 ────────────────────────────
        SettingsLineFrame(
          title: '色彩与字体',
          children: [
            _ThemeModeRow(
              themeMode: themeMode,
              onChanged: (m) =>
                  ref.read(themeSettingsProvider.notifier).setMode(m),
            ),
            SettingsEntryRow(
              title: '界面主题色',
              valueWidget: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _ThemeDot(color: Color(ui.themeSeedValue)),
              ),
              value: themeLabel,
              onTap: () => _openThemeSheet(context, ui, apply),
            ),
            SettingsEntryRow(
              title: '课程配色',
              valueWidget: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _ColorStrip(
                  colors: ui.colorScheme.colors.take(4).toList(),
                ),
              ),
              value: ui.colorScheme.name,
              onTap: () => _openSchemeSheet(context, ui, apply),
            ),
            SettingsEntryRow(
              title: '显示字体',
              value: fontLabelOf(ui.fontId),
              route: '/settings-font',
            ),
          ],
        ),

        // ── 第 2 组「课表排版与细节」2 行 ─────────────────────────
        SettingsLineFrame(
          title: '课表排版与细节',
          children: [
            SettingsEntryRow(
              title: '课表网格与表头',
              subtitle: '周末收起、非本周课程、行高与网格线',
              value: ui.autoFitHeight
                  ? '自适应'
                  : '${ui.cellHeight.round()}px',
              route: '/settings-appearance-grid',
            ),
            SettingsEntryRow(
              title: '课程卡片样式',
              subtitle: '卡片圆角、字号大小、教室与教师显示',
              value:
                  '${ui.cornerRadius.round()}px · ${(ui.cardTextScale * 100).round()}%',
              route: '/settings-card-style',
            ),
          ],
        ),

        // ── 第 3 组「导航与底栏」2 行 ─────────────────────────────
        // 联动 ①：底部栏显示关时，切换动效行整个不进 children，
        // 因而不留空位、不留分隔线（条件渲染，见 §1 例外条款）。
        SettingsLineFrame(
          title: '导航与底栏',
          children: [
            SettingsSwitchRow(
              title: '底部栏显示',
              subtitle: '关闭后可从主页右上角菜单进入设置',
              value: ui.showBottomBar,
              onChanged: (v) => apply(ui.copyWith(showBottomBar: v)),
            ),
            if (ui.showBottomBar)
              SettingsEntryRow(
                title: '切换动效',
                value: ui.shellTransitionStyle.label,
                onTap: () => _openTransitionSheet(context, ui, apply),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.group),
      ],
    );
  }

  /// §3.1 界面主题色：色点宫格放进 BottomSheet，父页不直接展开宫格。
  void _openThemeSheet(
    BuildContext context,
    UiSettings ui,
    void Function(UiSettings) apply,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('界面主题色',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in kThemePresets)
                    _ThemeChip(
                      name: preset.name,
                      color: Color(preset.seed),
                      selected: ui.themeCustomColor == null &&
                          ui.themePresetId == preset.id,
                      onTap: () {
                        apply(ui.copyWith(
                          themePresetId: preset.id,
                          clearThemeCustomColor: true,
                        ));
                        Navigator.pop(ctx);
                      },
                    ),
                  _ThemeChip(
                    name: '自定义',
                    color: ui.themeCustomColor != null
                        ? Color(ui.themeCustomColor!)
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                    selected: ui.themeCustomColor != null,
                    isCustom: true,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final picked = await showDialog<Color>(
                        context: context,
                        builder: (_) => _HsvPickerDialog(
                          initial: Color(ui.themeSeedValue),
                        ),
                      );
                      if (picked != null) {
                        apply(ui.copyWith(
                          themeCustomColor: picked.toARGB32(),
                        ));
                      }
                    },
                  ),
                ],
              ),
              if (ui.themeCustomColor != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      apply(ui.copyWith(clearThemeCustomColor: true));
                      Navigator.pop(ctx);
                    },
                    child: const Text('清除自定义，回到预置主题色'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// §3.2 课程配色面板：方案列表 + 底部灰白小按钮（原橙色文字链收进来）。
  void _openSchemeSheet(
    BuildContext context,
    UiSettings ui,
    void Function(UiSettings) apply,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('课程配色',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final scheme in kCourseColorSchemes)
                    ListTile(
                      leading: _ColorDots(
                        colors: scheme.colors.take(4).toList(),
                      ),
                      title: Text(scheme.name),
                      trailing: ui.colorSchemeId == scheme.id
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        apply(ui.copyWith(colorSchemeId: scheme.id));
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.tonal(
                onPressed: () {
                  apply(ui.copyWith(
                    themePresetId: ui.colorScheme.recommendedThemeId,
                    clearThemeCustomColor: true,
                  ));
                  Navigator.pop(ctx);
                },
                child: const Text('同步应用推荐界面主题色'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// §3.3 切换动效：单行入口 + 底部弹层 SegmentedButton 三选一。
  void _openTransitionSheet(
    BuildContext context,
    UiSettings ui,
    void Function(UiSettings) apply,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('切换动效',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<ShellTransitionStyle>(
                segments: [
                  for (final style in ShellTransitionStyle.values)
                    ButtonSegment<ShellTransitionStyle>(
                      value: style,
                      label: Text(style.label),
                    ),
                ],
                selected: {ui.shellTransitionStyle},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  apply(ui.copyWith(
                    shellTransitionStyle: selection.first,
                  ));
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 实时预览卡片（父页 + 网格/卡片两个专项子页共用）。
///
/// 预览 1:1 所需的真实网格参数计算与迁移前完全一致，只抽成共用组件搬位置，
/// provider、绑定、算法一字未动。
class AppearancePreviewCard extends ConsumerWidget {
  const AppearancePreviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final courses = ref.watch(coursesProvider).value ?? const [];
    final overrides = ref.watch(courseOverridesProvider).value ?? const [];
    final displayWeek = ref.watch(displayWeekProvider);
    final showOther = ref.watch(showOtherWeeksProvider);
    final autoCollapse = ref.watch(autoCollapseWeekendProvider);
    final previewDays = computeDisplayDays(
      effectiveCoursesForWeek(
        courses: courses,
        overrides: overrides,
        week: displayWeek,
      ),
      displayWeek,
      showOther,
      autoCollapse,
    );
    final slots = ref.watch(timeSlotsProvider).value ?? const <TimeSlot>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header('实时预览'),
        Preview(ui: ui, columnCount: previewDays.length, slots: slots),
      ],
    );
  }
}

/// 深浅模式：56dp 标准行，右端 3 选项 SegmentedButton（§2 控件映射）。
class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({
    required this.themeMode,
    required this.onChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kSettingsSingleRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '深浅模式',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.system,
                  label: Text('跟随系统'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text('浅色'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text('深色'),
                ),
              ],
              selected: {themeMode},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6),
                ),
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ],
        ),
      ),
    );
  }
}

/// 界面主题色入口行右侧的紧凑色点（§3.1 文案「● 可可棕」）。
class _ThemeDot extends StatelessWidget {
  const _ThemeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// 显示字体入口行的当前值回显（标题以现代码为准，只读不改）。
String fontLabelOf(String fontId) {
  final imported = FontsService.byId(fontId);
  if (imported != null) return '${imported.name}（导入）';
  return switch (fontId) {
    'lxgw' => '霞鹜文楷',
    'zcool' => '站酷快乐体',
    'smiley' => '得意黑',
    'noto' => '思源黑体',
    _ => '系统默认',
  };
}


/// 条目标题 + 旁挂 ⓘ 说明按钮（WB_SPEC_205 第 9 节）
///
/// 说明性副标题不再行内平铺，改成标题旁一个 ⓘ 小图标，点开 [showAppInfoDialog]
/// 看原文。行本身只剩标题 + 控件，回到 QQ 式干净排版。
class _InfoTitle extends StatelessWidget {
  const _InfoTitle({required this.title, required this.message});

  final String title;

  /// 弹窗正文（原副标题说明文字，一字未改）
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 2.0.7 Taste 化：行标题字重 medium（颜色沿用 ListTile 标题主题色）
        Flexible(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        AppInfoIconButton(
          tooltip: title,
          onPressed: () => showAppInfoDialog(
            context,
            title: title,
            message: message,
          ),
        ),
      ],
    );
  }
}

/// 外观分组里的节标题（2.0.7 Taste 化：主文字颜色 onSurface、字重 semibold、
/// 字号不放大；上边距 24 统一节与节之间的间距）
class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          // WB_SPEC_222：弱化标题、突出内容；小标题不上彩色。
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// 方案色带：前 6 个颜色的小色块（设置页里一眼看全方案气质）
class _ColorStrip extends StatelessWidget {
  const _ColorStrip({required this.colors});

  final List<int> colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colors.take(6))
          Container(
            width: 13,
            height: 22,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: Color(c),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// 4 颗代表色圆点（WB_SPEC_232 第 5.3 节：课程配色抽屉行右侧）
class _ColorDots extends StatelessWidget {
  const _ColorDots({required this.colors});

  final List<int> colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in colors)
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Color(c),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

/// 主题色圆点选项（预置与自定义共用）
class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
    this.isCustom = false,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: isCustom
                  ? const Icon(Icons.colorize, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(name),
          ],
        ),
      ),
    );
  }
}

/// 自定义主题色取色器：HSV 三滑杆 + 实时预览（无第三方依赖）
class _HsvPickerDialog extends StatefulWidget {
  const _HsvPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_HsvPickerDialog> createState() => _HsvPickerDialogState();
}

class _HsvPickerDialogState extends State<_HsvPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AppDialog(
      title: '自定义主题色',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            alignment: Alignment.center,
            child: Text(
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _hsvSlider(
            '色相',
            _hsv.hue,
            360,
            (v) => setState(() => _hsv = _hsv.withHue(v)),
          ),
          _hsvSlider(
            '饱和',
            _hsv.saturation,
            1,
            (v) => setState(() => _hsv = _hsv.withSaturation(v)),
          ),
          _hsvSlider(
            '明度',
            _hsv.value,
            1,
            (v) => setState(() => _hsv = _hsv.withValue(v)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('应用'),
        ),
      ],
    );
  }

  Widget _hsvSlider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 36, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 实时预览（1.2.0 改 1:1）：从真实课表「截一角」出来渲染——
/// 格高 = 真实格高、列宽 =（屏宽 − 节次栏宽）÷ 主页当前列数、
/// 表头高/节次栏宽/字号全部与主界面同一套常量和组件，
/// 所见即所得，不再有缩放比例差。
///
/// 2.0.5（WB_SPEC_205 第 6 节）起：展示「今天起连续三天」的列（今天是第一列），
/// 列头为真实星期与日期；[UiSettings.highlightTodayColumn] 开时按主页同款样式
/// （主题色描边、线宽 1.5、圆角 6）给第一列画整列边框，关时不画。
class Preview extends StatelessWidget {
  const Preview({
    super.key,
    required this.ui,
    required this.columnCount,
    required this.slots,
  });

  final UiSettings ui;

  /// 主页当前实际显示的列数（与主页同源计算），决定真实列宽
  final int columnCount;

  /// 真实作息（节次栏时间文案与主页一致）
  final List<TimeSlot> slots;

  static final _sampleA = Course(
    semesterId: 0,
    name: '药理学',
    teacher: '周老师',
    classroom: '教3-201',
    colorValue: MorandiPalette.colors[3],
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    weeks: const [1],
    note: '带实验报告',
  );
  static final _sampleB = Course(
    semesterId: 0,
    name: '有机化学',
    teacher: '李老师',
    classroom: '实验楼402',
    colorValue: MorandiPalette.colors[8],
    dayOfWeek: 2,
    startSection: 2,
    endSection: 3,
    weeks: const [1],
  );

  static const _rows = 3;
  static const _showCols = 3;
  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenW = MediaQuery.sizeOf(context).width;
    // 与主页完全相同的列宽公式（主页网格占满屏宽）
    final colW = (screenW - kTimeAxisWidth) / columnCount;
    final rowH = ui.cellHeight;
    final contentW = kTimeAxisWidth + colW * _showCols;
    // 今天起连续三天（今天是第一列）
    final today = DateTime.now();
    final days = [
      today,
      today.add(const Duration(days: 1)),
      today.add(const Duration(days: 2)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(AppRadii.card),
          color: scheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        // 窄屏时从右侧裁切，如同透过窗口看真实课表的一角
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: contentW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 表头：与主页同高、同字号（月份 + 星期/日期），今天列第一列
                Container(
                  height: kGridHeaderHeight,
                  color: scheme.surfaceContainerLow,
                  child: Row(
                    children: [
                      SizedBox(
                        width: kTimeAxisWidth,
                        child: Center(
                          child: Text(
                            '${today.month}月',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      ),
                      for (final day in days)
                        SizedBox(
                          width: colW,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _weekNames[day.weekday - 1],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: identical(day, today)
                                      ? scheme.primary
                                      : scheme.outline,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                width: 22,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: identical(day, today)
                                      ? scheme.primary
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: identical(day, today)
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: identical(day, today)
                                        ? scheme.onPrimary
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: rowH * _rows,
                  child: Row(
                    children: [
                      // 节次栏：与主页同宽、同字号（节次 12 号、时间 8 号）
                      SizedBox(
                        width: kTimeAxisWidth,
                        child: Column(
                          children: [
                            for (var i = 0; i < _rows; i++)
                              SizedBox(
                                height: rowH,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    if (ui.axisShowTime &&
                                        slots.length > i) ...[
                                      Text(
                                        slots[i].startTime,
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: scheme.outline,
                                        ),
                                      ),
                                      Text(
                                        slots[i].endTime,
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: scheme.outline,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // 网格 + 示例卡片（卡片内边距与主页同为 1.5）
                      SizedBox(
                        width: colW * _showCols,
                        child: Stack(
                          children: [
                            if (ui.showGridLines)
                              CustomPaint(
                                size: Size(colW * _showCols, rowH * _rows),
                                painter: _PreviewGridPainter(
                                  colW: colW,
                                  rowH: rowH,
                                  rows: _rows,
                                  cols: _showCols,
                                  color: scheme.outlineVariant,
                                ),
                              ),
                            _previewCard(_sampleA, 0, 0, 2, colW, rowH),
                            _previewCard(_sampleB, 1, 1, 2, colW, rowH),
                            // 今天整列边框高亮（2.0.5）：给第一列画一圈主题色框，
                            // 与主页同款样式（线宽 1.5、圆角 6），压在最上层保证连续
                            if (ui.highlightTodayColumn)
                              Positioned(
                                left: 0,
                                top: 0,
                                width: colW,
                                height: rowH * _rows,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    key: kPreviewTodayHighlightKey,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: scheme.primary,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        AppRadii.chip,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewCard(
    Course course,
    int col,
    int row,
    int span,
    double colW,
    double rowH,
  ) {
    const pad = 1.5;
    return Positioned(
      left: col * colW + pad,
      top: row * rowH + pad,
      width: colW - pad * 2,
      height: span * rowH - pad * 2,
      child: CourseCard(
        course: course,
        onTap: () {},
        onLongPress: () {},
        displayColorValue: mapCourseColor(course.colorValue, ui.colorScheme),
        cornerRadius: ui.cornerRadius,
        borderWidth: ui.borderWidth,
        textScale: ui.cardTextScale,
        showClassroom: ui.showClassroom,
        showTeacher: ui.showTeacher,
        showNote: ui.showNote,
      ),
    );
  }
}

class _PreviewGridPainter extends CustomPainter {
  _PreviewGridPainter({
    required this.colW,
    required this.rowH,
    required this.rows,
    required this.cols,
    required this.color,
  });

  final double colW;
  final double rowH;
  final int rows;
  final int cols;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (var r = 1; r < rows; r++) {
      canvas.drawLine(Offset(0, r * rowH), Offset(size.width, r * rowH), paint);
    }
    for (var c = 1; c < cols; c++) {
      canvas.drawLine(
        Offset(c * colW, 0),
        Offset(c * colW, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewGridPainter old) =>
      old.colW != colW ||
      old.rowH != rowH ||
      old.cols != cols ||
      old.color != color;
}

/// 显示字体区（1.2.1）：内置五款单选 + 用户导入字体（列表/导入/删除）。
/// 导入字体的注册表在 FontsService（静态），本组件用本地状态触发重建。
/// WB_SPEC_228 §4.3：228 专项子页用 [FontSettingsSection.inline] 平铺形态。
class FontSettingsSection extends StatefulWidget {
  const FontSettingsSection({
    super.key,
    required this.ui,
    required this.apply,
    this.inline = false,
  });

  final UiSettings ui;
  final void Function(UiSettings next) apply;

  /// true = 第 3 层子页内的线框平铺形态（字体网格 + 框外导入按钮）
  final bool inline;

  @override
  State<FontSettingsSection> createState() => FontSettingsSectionState();
}

class FontSettingsSectionState extends State<FontSettingsSection> {

  bool _importing = false;

  Future<void> _importFont() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
    );
    if (picked.isEmpty || !mounted) return;
    final path = picked.first.path;
    if (path == null) return;
    final baseName = path.split('/').last;
    final name = baseName.replaceAll(
      RegExp(r'\.(ttf|otf)$', caseSensitive: false),
      '',
    );
    setState(() => _importing = true);
    try {
      final font = await FontsService.importFont(
        File(path),
        name.isEmpty ? '导入字体' : name,
      );
      widget.apply(widget.ui.copyWith(fontId: font.id));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入并应用「${font.name}」')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败：这个文件不是有效的字体文件（仅支持 TTF / OTF）')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _removeFont(ImportedFont font) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除导入字体',
      message: '确定删除「${font.name}」吗？删除后使用该字体的设置会回到系统默认。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true) return;
    await FontsService.removeFont(font);
    if (widget.ui.fontId == font.id) {
      widget.apply(widget.ui.copyWith(fontId: 'system'));
    }
    if (mounted) setState(() {});
  }

  /// WB_SPEC_228 §4.3：第 3 层《显示字体》子页内全平铺——线框内字体网格，
  /// 框外只留导入/删除入口与说明。选项点击仍走原 `apply(copyWith(fontId:))`。
  Widget _inlineBody(BuildContext context) {
    final ui = widget.ui;
    final imported = FontsService.fonts;
    final selectedImported = FontsService.byId(ui.fontId);
    const builtins = [
      (id: 'system', name: '系统默认', family: null),
      (id: 'lxgw', name: '霞鹜文楷', family: 'LXGWWenKai'),
      (id: 'zcool', name: '站酷快乐体', family: 'ZCOOLKuaiLe'),
      (id: 'smiley', name: '得意黑', family: 'SmileySans'),
      (id: 'noto', name: '思源黑体', family: 'NotoSansSC'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsLineFrame(
          title: '字体',
          children: [
            for (final f in builtins)
              _FontOptionRow(
                name: f.name,
                fontFamily: f.family,
                selected: ui.fontId == f.id,
                onTap: () => widget.apply(ui.copyWith(fontId: f.id)),
              ),
            for (final f in imported)
              _FontOptionRow(
                name: '${f.name}（导入）',
                fontFamily: f.family,
                selected: ui.fontId == f.id,
                onTap: () => widget.apply(ui.copyWith(fontId: f.id)),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('导入字体文件'),
                onPressed: _importing ? null : _importFont,
              ),
              if (selectedImported != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除所选字体'),
                  onPressed: () => _removeFont(selectedImported),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '从手机里选 TTF / OTF 字体，导入后立即全 App 生效',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline) return _inlineBody(context);
    final ui = widget.ui;
    final imported = FontsService.fonts;
    // 当前选中的导入字体（若有）；final 便于在下方删除按钮闭包里安全判空
    final selectedImported = FontsService.byId(ui.fontId);
    const builtins = [
      (id: 'system', name: '系统默认', family: null),
      (id: 'lxgw', name: '霞鹜文楷', family: 'LXGWWenKai'),
      (id: 'zcool', name: '站酷快乐体', family: 'ZCOOLKuaiLe'),
      (id: 'smiley', name: '得意黑', family: 'SmileySans'),
      (id: 'noto', name: '思源黑体', family: 'NotoSansSC'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header('显示字体'),
        // 当前字体预览（下拉项本身也各自用自己的字体渲染）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            '小马课表 · 药理学',
            style: TextStyle(
              fontSize: 17,
              fontFamily: FontsService.resolveFamily(ui),
            ),
          ),
        ),
        // 显示字体：标准 56dp 设置行（WB_SPEC_232 第 5.3 节），行尾用该字体本身渲染；
        // 抽屉里每行也用各自字体渲染，导入的带「（导入）」后缀
        AppSelectSettingRow<String>(
          title: '显示字体',
          value: ui.fontId,
          sheetTitle: '显示字体',
          options: [
            for (final f in builtins)
              AppSelectOption(
                value: f.id,
                shortLabel: f.name,
                labelStyle: TextStyle(fontFamily: f.family),
              ),
            for (final f in imported)
              AppSelectOption(
                value: f.id,
                shortLabel: '${f.name}（导入）',
                labelStyle: TextStyle(fontFamily: f.family),
              ),
          ],
          // 抽屉底部：导入入口（调现有 _importFont；先关抽屉再选文件，
          // 否则文件选择器会被抽屉盖住、导入后列表也不刷新）
          footer: Builder(
            builder: (sheetContext) => TextButton.icon(
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('导入本地 TTF/OTF 字体'),
              onPressed: () {
                Navigator.pop(sheetContext);
                _importFont();
              },
            ),
          ),
          trailing: Text(
            selectedImported != null
                ? '${selectedImported.name}（导入）'
                : builtins
                    .firstWhere(
                      (f) => f.id == ui.fontId,
                      orElse: () => builtins.first,
                    )
                    .name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: FontsService.resolveFamily(ui)),
          ),
          onChanged: (v) => widget.apply(ui.copyWith(fontId: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              OutlinedButton.icon(
                icon: _importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('导入字体文件'),
                onPressed: _importing ? null : _importFont,
              ),
              if (selectedImported != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除所选字体'),
                  onPressed: () => _removeFont(selectedImported),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '从手机里选 TTF / OTF 字体，导入后立即全 App 生效',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// §4.3 字体网格行：56dp 平铺，选中打勾，字体名用自身字体渲染。
class _FontOptionRow extends StatelessWidget {
  const _FontOptionRow({
    required this.name,
    required this.fontFamily,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String? fontFamily;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: kSettingsSingleRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
