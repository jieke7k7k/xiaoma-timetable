import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import '../ui/app_styles.dart';
import '../ui/grid_metrics.dart';
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
/// - [AppearanceSettingsPage]（/settings-appearance）：实时预览 + 外观组整体 + 节次时间入口
/// - [RemindersSettingsPage]（/settings-reminders）：上课提醒 / 上课播报 / 常驻通知 / 提前提醒
/// - [DataSettingsPage]（/settings-data）：导入 / 学期管理 / 备份 / 恢复 / 导出 ICS / 数据管理
/// - [PermissionsSettingsPage]（/settings-permissions）：原 `_PermissionSummaryTile` 内容
/// - [WidgetSettingsPage]（/settings-widget）：桌面小组件说明文字
///
/// 2.0.7（WB_SPEC_208 第 2 节）Taste 化只动布局与层级：同一节内连续行之间用 1px
/// 分隔线（现有主题 dividerColor）、节与节之间间距统一 24（`AppSpacing.group`）、
/// 节标题主文字色 + semibold、行标题 medium。设置项、顺序、默认值、保存逻辑、
/// 校验、跳转、控件类型与颜色一律不动。

/// 实时预览「今天整列边框」覆盖层的 Key：测试据此断言开关开/关时该层的有无。
const Key kPreviewTodayHighlightKey = ValueKey('preview_today_highlight');

/// 把同一节内的一组连续设置行用 1px 分隔线隔开（2.0.7 Taste 化）。
///
/// 分隔线用现有主题 dividerColor（`Divider` 不指定 color 即取主题值），
/// 不改黑、不放大；只作用于「行与行之间」，节标题、预览、下拉、色板等
/// 非行控件不走这里。
List<Widget> _divideRows(List<Widget> rows) {
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0) const Divider(height: 1, thickness: 1),
      rows[i],
    ],
  ];
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
          children: _divideRows([
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text(
                '学期名称',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(semester.name),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text(
                '开学日期',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('${semester.startDate}（自动对齐到当周周一）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickStartDate(context, ref, semester.startDate),
            ),
            ListTile(
              leading: const Icon(Icons.view_week_outlined),
              title: const Text(
                '总周数',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text('${semester.totalWeeks} 周'),
              trailing: const Icon(Icons.chevron_right),
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

/// 外观子页：实时预览（置于 [_AppearanceGroup] 顶部）+ 外观组整体 + 节次时间入口
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外观'), centerTitle: true),
      body: ListView(
        children: [
          const _AppearanceGroup(),
          // 2.0.7 Taste 化：节次时间入口与外观组之间节间距统一 24
          const SizedBox(height: AppSpacing.group),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const _InfoTitle(
              title: '节次时间设置',
              message: '自定义每节课上下课时间，可一键套用大节时间',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/time-settings'),
          ),
        ],
      ),
    );
  }
}

/// 提醒子页：上课提醒 / 上课播报 / 今日课程常驻通知 / 提前提醒
class RemindersSettingsPage extends ConsumerWidget {
  const RemindersSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒'), centerTitle: true),
      body: ListView(
        children: [
          Consumer(
            builder: (ctx, ref, _) {
              final settings = ref.watch(reminderSettingsProvider);
              return settings.when(
                data: (s) => SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const _InfoTitle(
                    title: '上课提醒',
                    message: '每节课提前提醒，App 被杀后也能准时响铃',
                  ),
                  value: s.enabled,
                  onChanged: (v) => _onReminderToggle(ctx, ref, v),
                ),
                loading: () => const ListTile(
                  leading: Icon(Icons.notifications_active_outlined),
                  title: Text('上课提醒'),
                  subtitle: Text('加载中…'),
                ),
                error: (e, _) => ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('上课提醒'),
                  subtitle: Text('加载失败：$e'),
                ),
              );
            },
          ),
          const Divider(height: 1, thickness: 1),
          // 上课播报（2.0.2 起从「外观」页归入提醒组）：主页顶部状态条开关
          Consumer(
            builder: (ctx, ref, _) {
              final ui =
                  ref.watch(uiSettingsProvider).value ?? const UiSettings();
              return SwitchListTile(
                secondary: const Icon(Icons.campaign_outlined),
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
          const Divider(height: 1, thickness: 1),
          Consumer(
            builder: (ctx, ref, _) {
              final enabled = ref.watch(ongoingNoticeSettingsProvider);
              return enabled.when(
                data: (on) => SwitchListTile(
                  secondary: const Icon(Icons.pin_outlined),
                  title: const _InfoTitle(
                    title: '今日课程常驻通知',
                    message: '通知栏常驻显示今日剩余或明日课程预告',
                  ),
                  value: on,
                  onChanged: (v) => ref
                      .read(ongoingNoticeSettingsProvider.notifier)
                      .setEnabled(v),
                ),
                loading: () => const ListTile(
                  leading: Icon(Icons.pin_outlined),
                  title: Text('今日课程常驻通知'),
                  subtitle: Text('加载中…'),
                ),
                error: (e, _) => ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('今日课程常驻通知'),
                  subtitle: Text('加载失败：$e'),
                ),
              );
            },
          ),
          const Divider(height: 1, thickness: 1),
          Consumer(
            builder: (ctx, ref, _) {
              final advance =
                  ref.watch(reminderSettingsProvider).value?.advanceMinutes ??
                  15;
              return ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text(
                  '提前提醒',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text('提前 $advance 分钟'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickAdvanceMinutes(ctx, ref),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 上课提醒开关：开启时申请通知权限 + 精确闹钟授权引导，再持久化
  Future<void> _onReminderToggle(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final notifier = ref.read(reminderSettingsProvider.notifier);
    if (value) {
      // Android 13+ 通知权限：被拒给中文提示，但不阻断开启（用户可稍后授权）
      final granted = await NotificationService.instance
          .ensureNotificationPermission();
      if (!granted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通知权限被拒绝，提醒可能无法显示，请到系统设置开启')),
        );
      }

      // 精确闹钟：无权限时降级为非精确排期，并引导用户去系统设置授权
      final exact = await NotificationService.instance.canScheduleExact();
      if (!exact && context.mounted) {
        await _showExactAlarmGuide(context);
      }
    }
    await notifier.setEnabled(value);
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

/// 学期与数据子页：导入课表 / 学期管理 / 备份到文件 / 从备份恢复 /
/// 导出课表（ICS）/ 数据管理，共 6 行（2.0.2 起由「高级与数据」拆解并入）
class DataSettingsPage extends ConsumerWidget {
  const DataSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('学期与数据'), centerTitle: true),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const _InfoTitle(
              title: '导入课表',
              message: 'ICS / 图片 OCR / PDF 导入，支持冲突检测',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/import'),
          ),
          const Divider(height: 1, thickness: 1),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const _InfoTitle(
              title: '学期管理',
              message: '新建、切换或删除学期',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/semester-manage'),
          ),
          const Divider(height: 1, thickness: 1),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const _InfoTitle(
              title: '备份到文件',
              message: '导出全部数据为 JSON 文件，换机/重装可恢复',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportBackup(context),
          ),
          const Divider(height: 1, thickness: 1),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const _InfoTitle(
              title: '从备份恢复',
              message: '选择备份 JSON，恢复前会再次确认（覆盖现有数据）',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _restoreBackup(context, ref),
          ),
          const Divider(height: 1, thickness: 1),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const _InfoTitle(
              title: '导出课表（ICS）',
              message: '当前学期课表导出为日历文件，可分享或导入其他日历 App',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _exportIcs(context, ref),
          ),
          const Divider(height: 1, thickness: 1),
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const _InfoTitle(
              title: '数据管理',
              message: '存储占用、备份快捷入口与恢复出厂',
            ),
            trailing: const Icon(Icons.chevron_right),
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
      // 通知/常驻通知/小组件基于恢复后的数据重排刷新（内部均已捕获异常）
      unawaited(NotificationService.instance.rescheduleAll());
      unawaited(OngoingNoticeService.instance.refresh());
      unawaited(WidgetService.instance.refreshWidgets());
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
    return Scaffold(
      appBar: AppBar(title: const Text('桌面小组件'), centerTitle: true),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.widgets_outlined),
            title: Text(
              '今日课程小组件',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('在桌面长按空白处 →「小组件」→ 找到「小马课表」，即可添加今日课程小组件'),
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
          leading: const Icon(Icons.shield_outlined),
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
          trailing: const Icon(Icons.chevron_right),
          onTap: _open,
        );
      },
    );
  }
}

/// 外观分组（2.0.3 起由原「外观」二级页平铺进设置首页，2.0.5 起随 QQ 式整顿
/// 整体搬进外观子页 [AppearanceSettingsPage]）：
/// 主题模式三段选择 + 原外观页全部条目（实时预览/格子外观/卡片显示/课程配色/
/// 主题颜色/显示字体）+ 显示非本周课程/周末收起/刷新小部件/部件状态。
/// 条目顺序与原外观页内顺序一致，逻辑原样复用。
class _AppearanceGroup extends ConsumerWidget {
  const _AppearanceGroup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final notifier = ref.read(uiSettingsProvider.notifier);
    void apply(UiSettings next) => notifier.apply(next);

    // 预览 1:1 所需的真实网格参数：列数与主页当前周完全同源计算
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

    // provider 未加载完（首帧）时按跟随系统显示，加载后自动到位
    final themeMode =
        ref.watch(themeSettingsProvider).value ?? ThemeMode.system;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 主题三档选择：跟随系统/浅色/深色（阶段五·深色适配）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('跟随系统'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('浅色'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('深色'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) => ref
                .read(themeSettingsProvider.notifier)
                .setMode(selection.first),
          ),
        ),
        const _Header('实时预览'),
        Preview(ui: ui, columnCount: previewDays.length, slots: slots),
        const _Header('格子外观'),
        ..._divideRows([
          SwitchListTile(
            title: const _InfoTitle(
              title: '行高自适应一屏',
              message: '按屏幕高度均分行高，整张课表不用上下滚',
            ),
            value: ui.autoFitHeight,
            onChanged: (v) => apply(ui.copyWith(autoFitHeight: v)),
          ),
          _SliderRow(
            label: '课程格子高度',
            valueText: ui.autoFitHeight
                ? '自适应中'
                : '${ui.cellHeight.round()} px',
            value: ui.cellHeight,
            min: 44,
            max: 96,
            divisions: 26,
            onChanged: ui.autoFitHeight
                ? (_) {}
                : (v) => apply(ui.copyWith(cellHeight: v)),
          ),
          _SliderRow(
            label: '格子圆角半径',
            valueText: '${ui.cornerRadius.round()} px',
            value: ui.cornerRadius,
            min: 0,
            max: 20,
            divisions: 20,
            onChanged: (v) => apply(ui.copyWith(cornerRadius: v)),
          ),
          SwitchListTile(
            title: const Text(
              '显示网格线',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            value: ui.showGridLines,
            onChanged: (v) => apply(ui.copyWith(showGridLines: v)),
          ),
          _SliderRow(
            label: '格子边框粗细',
            valueText: ui.borderWidth <= 0
                ? '无边框'
                : '${ui.borderWidth.toStringAsFixed(1)} px',
            value: ui.borderWidth,
            min: UiSettings.borderWidthMin,
            max: UiSettings.borderWidthMax,
            divisions: 30,
            onChanged: (v) => apply(ui.copyWith(borderWidth: v)),
          ),
          SwitchListTile(
            title: const _InfoTitle(
              title: '节数栏显示时间',
              message: '关掉后左侧只显示节次数字',
            ),
            value: ui.axisShowTime,
            onChanged: (v) => apply(ui.copyWith(axisShowTime: v)),
          ),
          SwitchListTile(
            title: const _InfoTitle(
              title: '标题显示单双周',
              message: '开时左上角显示「第 X 周 · 单周/双周」，关时只显示「第 X 周」，默认关',
            ),
            value: ui.showWeekParity,
            onChanged: (v) => apply(ui.copyWith(showWeekParity: v)),
          ),
          SwitchListTile(
            title: const _InfoTitle(
              title: '今天整列边框高亮',
              message: '给今天这一整天加一圈主题色边框，默认关',
            ),
            value: ui.highlightTodayColumn,
            onChanged: (v) => apply(ui.copyWith(highlightTodayColumn: v)),
          ),
        ]),
        const _Header('卡片显示'),
        ..._divideRows([
          _SliderRow(
            label: '卡片文字大小',
            valueText: '${(ui.cardTextScale * 100).round()}%',
            value: ui.cardTextScale,
            min: UiSettings.textScaleMin,
            max: UiSettings.textScaleMax,
            divisions: 50,
            onChanged: (v) => apply(ui.copyWith(cardTextScale: v)),
          ),
          SwitchListTile(
            title: const Text(
              '显示教室',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            value: ui.showClassroom,
            onChanged: (v) => apply(ui.copyWith(showClassroom: v)),
          ),
          SwitchListTile(
            title: const Text(
              '显示老师',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            value: ui.showTeacher,
            onChanged: (v) => apply(ui.copyWith(showTeacher: v)),
          ),
          SwitchListTile(
            title: const _InfoTitle(
              title: '显示备注',
              message: '备注以小字显示在卡片上',
            ),
            value: ui.showNote,
            onChanged: (v) => apply(ui.copyWith(showNote: v)),
          ),
        ]),
        const _Header('课程配色'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: DropdownButtonFormField<String>(
            key: ValueKey('scheme_${ui.colorSchemeId}'),
            initialValue: ui.colorSchemeId,
            decoration: const InputDecoration(
              labelText: '课程配色',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final scheme in kCourseColorSchemes)
                DropdownMenuItem(
                  value: scheme.id,
                  child: Row(
                    children: [
                      _ColorStrip(colors: scheme.colors),
                      const SizedBox(width: 10),
                      Text(scheme.name),
                    ],
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) apply(ui.copyWith(colorSchemeId: v));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: Text(
                '顺带应用推荐主题色「${themePresetById(ui.colorScheme.recommendedThemeId).name}」',
              ),
              onPressed: () => apply(
                ui.copyWith(
                  themePresetId: ui.colorScheme.recommendedThemeId,
                  clearThemeCustomColor: true,
                ),
              ),
            ),
          ),
        ),
        const _Header('主题颜色'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final preset in kThemePresets)
                _ThemeChip(
                  name: preset.name,
                  color: Color(preset.seed),
                  selected:
                      ui.themeCustomColor == null &&
                      ui.themePresetId == preset.id,
                  onTap: () => apply(
                    ui.copyWith(
                      themePresetId: preset.id,
                      clearThemeCustomColor: true,
                    ),
                  ),
                ),
              _ThemeChip(
                name: '自定义',
                color: ui.themeCustomColor != null
                    ? Color(ui.themeCustomColor!)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                selected: ui.themeCustomColor != null,
                isCustom: true,
                onTap: () async {
                  final picked = await showDialog<Color>(
                    context: context,
                    builder: (_) =>
                        _HsvPickerDialog(initial: Color(ui.themeSeedValue)),
                  );
                  if (picked != null) {
                    apply(ui.copyWith(themeCustomColor: picked.toARGB32()));
                  }
                },
              ),
            ],
          ),
        ),
        if (ui.themeCustomColor != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    apply(ui.copyWith(clearThemeCustomColor: true)),
                child: const Text('清除自定义，回到预置主题色'),
              ),
            ),
          ),
        _FontSection(ui: ui, apply: apply),
        ..._divideRows([
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: const _InfoTitle(
              title: '显示非本周课程',
              message: '开启后其他周次的课程置灰显示，方便全局查看',
            ),
            value: showOther,
            onChanged: (v) =>
                ref.read(showOtherWeeksProvider.notifier).toggle(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.weekend_outlined),
            title: const _InfoTitle(
              title: '周末无课时自动收起周六日',
              message: '开启后周末没课时周视图只显示周一到周五，更宽敞',
            ),
            value: autoCollapse,
            onChanged: (v) =>
                ref.read(autoCollapseWeekendProvider.notifier).toggle(v),
          ),
          ListTile(
            leading: const Icon(Icons.widgets_outlined),
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
          // 部件自检状态（1.2.7）：Provider 回写的上次更新记录
          FutureBuilder<({int ts, int ids, String? error})>(
            future: WidgetService.instance.debugStatus(),
            builder: (ctx, snap) {
              final d = snap.data;
              if (d == null || d.ts == 0) {
                return const ListTile(
                  leading: Icon(Icons.info_outline),
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
                leading: const Icon(Icons.info_outline),
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
        ]),
      ],
    );
  }
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
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          // 2.0.7 Taste 化：滑杆行标题字重 medium
          SizedBox(
            width: 108,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(valueText, textAlign: TextAlign.right),
          ),
        ],
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
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
              borderRadius: BorderRadius.circular(10),
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
          borderRadius: BorderRadius.circular(12),
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
                                      borderRadius: BorderRadius.circular(6),
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
class _FontSection extends StatefulWidget {
  const _FontSection({required this.ui, required this.apply});

  final UiSettings ui;
  final void Function(UiSettings next) apply;

  @override
  State<_FontSection> createState() => _FontSectionState();
}

class _FontSectionState extends State<_FontSection> {
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

  @override
  Widget build(BuildContext context) {
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownButtonFormField<String>(
            key: ValueKey('font_${ui.fontId}'),
            initialValue: ui.fontId,
            decoration: const InputDecoration(
              labelText: '显示字体',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final f in builtins)
                DropdownMenuItem(
                  value: f.id,
                  child: Text(f.name, style: TextStyle(fontFamily: f.family)),
                ),
              for (final f in imported)
                DropdownMenuItem(
                  value: f.id,
                  child: Text(
                    '${f.name}（导入）',
                    style: TextStyle(fontFamily: f.family),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) widget.apply(ui.copyWith(fontId: v));
            },
          ),
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
