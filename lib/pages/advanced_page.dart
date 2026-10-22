import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/permission_service.dart';
import '../services/widget_service.dart';
import '../utils/backup_codec.dart';
import '../utils/ics_export.dart';

/// 高级与数据（设置 → 高级与数据）：收低频入口的二级页。
///
/// 2.0.1 设置页分组时，把 AI 桥 / 权限 / 数据管理 / 关于小马课表这几样低频项
/// 从设置页挪到这里，路由不变、入口一个不少，只是换了安放层级。
class AdvancedPage extends ConsumerWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('高级与数据'), centerTitle: true),
      body: ListView(
        children: [
          const _SectionHeader(title: 'AI 桥'),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: const Text('AI 桥'),
            subtitle: const Text(
              '把私有仓库当命令信箱：外部 AI 下指令改课表，删除类指令会先等你确认',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/bridge'),
          ),
          const _SectionHeader(title: '权限'),
          const _PermissionSummaryTile(),
          const _SectionHeader(title: '数据管理'),
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
          ListTile(
            leading: const Icon(Icons.sd_storage_outlined),
            title: const Text('数据管理'),
            subtitle: const Text('存储占用、备份快捷入口与恢复出厂'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/data-manage'),
          ),
          const _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于小马课表'),
            subtitle: const Text('版本、检查更新、公告、更新日志与开源许可'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/about'),
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认恢复备份？'),
          content: Text(
            '备份中包含 ${data.semesters.length} 个学期、${data.courses.length} 门课程'
            '${data.courseOverrides.isEmpty ? '' : '、${data.courseOverrides.length} 条调课记录'}。'
            '\n\n恢复会覆盖现有全部数据（含节次时间与设置），且无法撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖并恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;

      // 恢复期间用对话框遮罩，防止重复点击或误以为卡死
      final closing = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
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

/// 分区标题（与设置页同款）
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

/// 权限入口行：显示「已授权 x / 3」摘要。
///
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
