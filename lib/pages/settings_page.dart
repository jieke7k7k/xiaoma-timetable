import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/permission_service.dart';
import '../services/widget_service.dart';
import '../utils/backup_codec.dart';
import '../utils/ics_export.dart';
import '../widgets/app_dialog.dart';
import '../widgets/empty_state.dart';

/// 设置页
///
/// 2.0.2（WB-202 第 2 项·A 方案）整体重组，条目一个不能丢、路由尽量复用：
/// - 「界面设置」改名「外观」；「提醒设置」改名「提醒」，上课播报开关
///   （原在外观页）归入提醒组；
/// - 功能类入口（课程搜索 / 空闲时段 / 考试倒计时 / 导出课表图片 / 日期备注）
///   收进二级页「课表工具」（course_tools_page.dart，路由 /course-tools），
///   一级页只留一行入口；
/// - 「高级与数据」拆解：AI 桥并入「智能助手」二级页（ai_settings_page.dart，
///   与接口地址 / 模型 / Key / 测试对话同页）；备份 / 恢复 / 导出 ICS / 数据管理
///   与教务导入、学期管理同组为「学期与数据」；权限、关于小马课表各单列一行
///   （原 advanced_page.dart 内容全部迁出，路由 /advanced 一并移除）；
/// - 智能助手设置（接口地址 / 模型 / Key / 测试对话）收在二级页，一级页只留
///   「和智能助手聊聊」与「智能助手设置」两行入口。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semesterAsync = ref.watch(currentSemesterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: semesterAsync.when(
        data: (semester) => ListView(
          children: [
            const _SectionHeader(title: '学期设置'),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('学期名称'),
              subtitle: Text(semester.name),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('开学日期'),
              subtitle: Text('${semester.startDate}（自动对齐到当周周一）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickStartDate(context, ref, semester.startDate),
            ),
            ListTile(
              leading: const Icon(Icons.view_week_outlined),
              title: const Text('总周数'),
              subtitle: Text('${semester.totalWeeks} 周'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editTotalWeeks(context, ref, semester.totalWeeks),
            ),
            // 2.0.2 起学期管理并入「学期与数据」组（与教务导入同组），此处只留
            // 学期名称 / 开学日期 / 总周数三项本体设置
            const _SectionHeader(title: '外观'),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('外观'),
              subtitle: const Text('格子大小、配色方案、主题颜色、显示字体，带实时预览'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/ui-settings'),
            ),
            // 主题三档选择：跟随系统/浅色/深色（阶段五·深色适配）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Consumer(
                builder: (ctx, ref, _) {
                  // provider 未加载完（首帧）时按跟随系统显示，加载后自动到位
                  final mode =
                      ref.watch(themeSettingsProvider).value ??
                      ThemeMode.system;
                  return SegmentedButton<ThemeMode>(
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
                    selected: {mode},
                    onSelectionChanged: (selection) => ref
                        .read(themeSettingsProvider.notifier)
                        .setMode(selection.first),
                  );
                },
              ),
            ),
            Consumer(
              builder: (ctx, ref, _) {
                final showOther = ref.watch(showOtherWeeksProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.visibility_outlined),
                  title: const Text('显示非本周课程'),
                  subtitle: const Text('开启后其他周次的课程置灰显示，方便全局查看'),
                  value: showOther,
                  onChanged: (v) =>
                      ref.read(showOtherWeeksProvider.notifier).toggle(v),
                );
              },
            ),
            Consumer(
              builder: (ctx, ref, _) {
                final autoCollapse = ref.watch(autoCollapseWeekendProvider);
                return SwitchListTile(
                  secondary: const Icon(Icons.weekend_outlined),
                  title: const Text('周末无课时自动收起周六日'),
                  subtitle: const Text('开启后周末没课时周视图只显示周一到周五，更宽敞'),
                  value: autoCollapse,
                  onChanged: (v) =>
                      ref.read(autoCollapseWeekendProvider.notifier).toggle(v),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.widgets_outlined),
              title: const Text('立即刷新桌面小部件'),
              subtitle: const Text('把最新课程重新推送到桌面小部件'),
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
                    title: Text('部件状态'),
                    subtitle: Text('还没有收到小部件的更新记录（先添加一个桌面小部件）'),
                  );
                }
                final t = DateTime.fromMillisecondsSinceEpoch(d.ts);
                final hh = t.hour.toString().padLeft(2, '0');
                final mm = t.minute.toString().padLeft(2, '0');
                return ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('部件状态'),
                  subtitle: Text(
                    d.error == null
                        ? '上次更新 $hh:$mm · 共 ${d.ids} 个小部件 · 无异常'
                        : '上次更新 $hh:$mm · 共 ${d.ids} 个小部件 · 异常：${d.error}',
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('节次时间设置'),
              subtitle: const Text('自定义每节课上下课时间，可一键套用大节时间'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/time-settings'),
            ),
            const _SectionHeader(title: '提醒'),
            Consumer(
              builder: (ctx, ref, _) {
                final settings = ref.watch(reminderSettingsProvider);
                return settings.when(
                  data: (s) => SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('上课提醒'),
                    subtitle: const Text('每节课提前提醒，App 被杀后也能准时响铃'),
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
            // 上课播报（2.0.2 起从「外观」页归入提醒组）：主页顶部状态条开关
            Consumer(
              builder: (ctx, ref, _) {
                final ui =
                    ref.watch(uiSettingsProvider).value ?? const UiSettings();
                return SwitchListTile(
                  secondary: const Icon(Icons.campaign_outlined),
                  title: const Text('上课播报'),
                  subtitle: const Text('主页顶部显示当前/下一节课状态条，默认关'),
                  value: ui.showClassBroadcast,
                  onChanged: (v) => ref
                      .read(uiSettingsProvider.notifier)
                      .apply(ui.copyWith(showClassBroadcast: v)),
                );
              },
            ),
            Consumer(
              builder: (ctx, ref, _) {
                final enabled = ref.watch(ongoingNoticeSettingsProvider);
                return enabled.when(
                  data: (on) => SwitchListTile(
                    secondary: const Icon(Icons.pin_outlined),
                    title: const Text('今日课程常驻通知'),
                    subtitle: const Text('通知栏常驻显示今日剩余或明日课程预告'),
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
            Consumer(
              builder: (ctx, ref, _) {
                final advance =
                    ref.watch(reminderSettingsProvider).value?.advanceMinutes ??
                    15;
                return ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('提前提醒'),
                  subtitle: Text('提前 $advance 分钟'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickAdvanceMinutes(ctx, ref),
                );
              },
            ),
            // 功能类入口收进二级页（2.0.2），一级页只留一行
            const _SectionHeader(title: '课表工具'),
            ListTile(
              leading: const Icon(Icons.handyman_outlined),
              title: const Text('课表工具'),
              subtitle: const Text('课程搜索、空闲时段、考试倒计时、导出课表图片、日期备注'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/course-tools'),
            ),
            const _SectionHeader(title: '智能助手'),
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('和智能助手聊聊'),
              subtitle: const Text('带着课表上下文回答问题，也能帮你改课表（改前会先确认）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/ai-chat'),
            ),
            // 接口地址 / 模型 / Key / 测试对话 / AI 桥都在二级页（2.0.2）
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('智能助手设置'),
              subtitle: const Text('接口地址、模型名、API Key、测试对话与 AI 桥'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/ai-settings'),
            ),
            // 「高级与数据」拆解后：备份 / 恢复 / 导出 ICS / 数据管理与教务导入、
            // 学期管理同组（2.0.2）
            const _SectionHeader(title: '学期与数据'),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('导入课表'),
              subtitle: const Text('ICS / 图片 OCR / PDF 导入，支持冲突检测'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/import'),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('学期管理'),
              subtitle: const Text('新建、切换或删除学期'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/semester-manage'),
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('备份到文件'),
              subtitle: const Text('导出全部数据为 JSON 文件，换机/重装可恢复'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _exportBackup(context),
            ),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('从备份恢复'),
              subtitle: const Text('选择备份 JSON，恢复前会再次确认（覆盖现有数据）'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _restoreBackup(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('导出课表（ICS）'),
              subtitle: const Text('当前学期课表导出为日历文件，可分享或导入其他日历 App'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _exportIcs(context, ref),
            ),
            const _AutoBackupTile(),
            ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: const Text('数据管理'),
              subtitle: const Text('存储占用、备份快捷入口与恢复出厂'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/data-manage'),
            ),
            // 权限、关于各单列一行（原在「高级与数据」二级页里，2.0.2 拆解上浮）
            const _SectionHeader(title: '权限'),
            const _PermissionSummaryTile(),
            const _SectionHeader(title: '关于小马课表'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于小马课表'),
              subtitle: const Text('版本、检查更新、公告、更新日志与开源许可'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/about'),
            ),
            const _SectionHeader(title: '桌面小组件'),
            const ListTile(
              leading: Icon(Icons.widgets_outlined),
              title: Text('今日课程小组件'),
              subtitle: Text('在桌面长按空白处 →「小组件」→ 找到「小马课表」，即可添加今日课程小组件'),
            ),
          ],
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
      // 2.0.2（WB-202 第 4 项）：切全 App 统一弹窗组件
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
    // 2.0.2（WB-202 第 4 项）：切统一确认弹窗
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

  // ---------- 学期与数据（2.0.2 起由「高级与数据」拆解并入） ----------

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
      // 2.0.2（WB-202 第 4 项）：切统一确认弹窗（破坏性标红）
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// 自动备份只读行（2.0.2 起随「高级与数据」拆解并入「学期与数据」组）。
///
/// 自动备份由 App 启动时静默完成（约每 7 天一份，保留最近 3 份），
/// 这里只展示最近一次时间，不提供手动触发——与数据管理页同一口径。
/// 状态查询读本地文件，因此只在 initState 里发起一次（放 build 里会每次重建都查）。
class _AutoBackupTile extends StatefulWidget {
  const _AutoBackupTile();

  @override
  State<_AutoBackupTile> createState() => _AutoBackupTileState();
}

class _AutoBackupTileState extends State<_AutoBackupTile> {
  late Future<DateTime?> _lastAuto = AutoBackupService.lastBackupAt();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DateTime?>(
      future: _lastAuto,
      builder: (ctx, snap) {
        final t = snap.data;
        return ListTile(
          leading: const Icon(Icons.history_outlined),
          title: const Text('自动备份'),
          subtitle: Text(
            t == null
                ? '暂无自动备份（每 7 天自动生成一次）'
                : '最近自动备份：${t.month}月${t.day}日',
          ),
        );
      },
    );
  }
}

/// 权限入口行：显示「已授权 x / 3」摘要。
///
/// 2.0.2 起随「高级与数据」拆解单列在设置页一级页面（原 advanced_page.dart）。
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
          title: const Text('权限'),
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
