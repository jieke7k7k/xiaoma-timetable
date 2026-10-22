import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import '../providers/providers.dart';
import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/widget_service.dart';
import '../widgets/app_dialog.dart';

/// 数据管理页（1.2.4）：存储占用总览 + 备份/恢复快捷入口 + 恢复出厂。
/// 设置页原有的备份入口保留不动，这里是把数据相关的事归拢到一页。
class DataManagePage extends ConsumerStatefulWidget {
  const DataManagePage({super.key});

  @override
  ConsumerState<DataManagePage> createState() => _DataManagePageState();
}

class _DataManagePageState extends ConsumerState<DataManagePage> {
  late Future<(int, int)> _sizes = _loadSizes();

  /// 最近一次自动备份的时间（只读展示，不提供手动触发入口）
  late Future<DateTime?> _lastAuto = AutoBackupService.lastBackupAt();

  Future<(int, int)> _loadSizes() async {
    var dbSize = 0;
    var fontSize = 0;
    try {
      final dbPath = await getDatabasesPath();
      final dbFile = File('$dbPath/simple_timetable.db');
      if (await dbFile.exists()) dbSize = await dbFile.length();
      final docs = await getApplicationDocumentsDirectory();
      final fontsDir = Directory('${docs.path}/fonts');
      if (await fontsDir.exists()) {
        await for (final e in fontsDir.list(recursive: true)) {
          if (e is File) fontSize += await e.length();
        }
      }
    } catch (_) {
      // 占用只是展示信息，读不到就显示 0
    }
    return (dbSize, fontSize);
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// 数据变更后统一刷新：各数据源失效重读 + 通知/小部件/常驻条跟着新数据走
  void _refreshAll() {
    ref.invalidate(currentSemesterProvider);
    ref.invalidate(semestersProvider);
    ref.invalidate(coursesProvider);
    ref.invalidate(courseOverridesProvider);
    ref.invalidate(notesProvider);
    ref.invalidate(timeSlotsProvider);
    ref.invalidate(segmentSettingsProvider);
    ref.invalidate(uiSettingsProvider);
    ref.invalidate(themeSettingsProvider);
    ref.invalidate(reminderSettingsProvider);
    ref.invalidate(onboardingDoneProvider);
    NotificationService.instance.rescheduleAll();
    OngoingNoticeService.instance.refresh();
    WidgetService.instance.refreshWidgets();
    setState(() {
      _sizes = _loadSizes();
      _lastAuto = AutoBackupService.lastBackupAt();
    });
  }

  Future<void> _exportBackup() async {
    try {
      // 与设置页、自动备份同一条组装路径（含自定义字体），格式永远一致
      final bundle = await BackupService.instance.buildBackup(now: DateTime.now());
      const pretty = JsonEncoder.withIndent('  ');
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final path = await BackupService.instance.saveTextFile(
        fileName: '小马课表备份_$stamp.json',
        content: pretty.convert(bundle.json),
        extension: 'json',
      );
      if (path == null || !mounted) return;
      final warn =
          bundle.warnings.isEmpty ? '' : '\n${bundle.warnings.join('\n')}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('备份已保存到：$path$warn')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('备份导出失败：$e')));
      }
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final path = await BackupService.instance.pickJsonFile();
      if (path == null) return;
      final data = await BackupService.instance.readBackup(path);
      if (!mounted) return;
      // 2.0.2（WB-202 第 4 项）：切统一确认弹窗（破坏性标红）
      final confirmed = await showAppConfirmDialog(
        context,
        title: '确认恢复备份？',
        message: '备份中包含 ${data.semesters.length} 个学期、${data.courses.length} 门课程。'
            '\n\n恢复会覆盖现有全部数据（含节次时间与设置），且无法撤销。',
        confirmLabel: '覆盖并恢复',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
      await BackupService.instance.restore(data);
      if (!mounted) return;
      _refreshAll();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已从备份恢复')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$e')));
      }
    }
  }

  Future<void> _factoryReset() async {
    // 2.0.2（WB-202 第 4 项）：两步确认都切统一确认弹窗（破坏性标红）
    final first = await showAppConfirmDialog(
      context,
      title: '恢复出厂？',
      message: '将删除全部学期、课程、设置与导入的字体，回到刚安装时的状态。\n\n'
          '此操作不可撤销。建议先导出一份备份。',
      confirmLabel: '继续',
      destructive: true,
    );
    if (first != true || !mounted) return;
    final second = await showAppConfirmDialog(
      context,
      title: '最后确认',
      message: '真的要清空全部数据吗？删除后只能通过备份文件恢复。',
      confirmLabel: '清空全部数据',
      destructive: true,
    );
    if (second != true || !mounted) return;
    try {
      await DbHelper.instance.resetAllData();
      // 库外的本地文件一并清：导入字体、通道缓存/已读状态
      final docs = await getApplicationDocumentsDirectory();
      final fontsDir = Directory('${docs.path}/fonts');
      if (await fontsDir.exists()) await fontsDir.delete(recursive: true);
      final channelState = File('${docs.path}/channel_state.json');
      if (await channelState.exists()) await channelState.delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重置失败：$e')));
      }
      return;
    }
    if (!mounted) return;
    _refreshAll();
    Navigator.popUntil(context, (r) => r.isFirst);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已恢复出厂，回到初始状态')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理'), centerTitle: true),
      body: ListView(
        children: [
          const _Header('存储占用'),
          FutureBuilder<(int, int)>(
            future: _sizes,
            builder: (context, snap) {
              final (db, fonts) = snap.data ?? (0, 0);
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('课表数据库'),
                    trailing: Text(_fmt(db)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.font_download_outlined),
                    title: const Text('导入的字体'),
                    trailing: Text(_fmt(fonts)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.summarize_outlined),
                    title: const Text('合计'),
                    trailing: Text(
                      _fmt(db + fonts),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              );
            },
          ),
          const _Header('备份与恢复'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('备份到文件'),
            subtitle: const Text('导出全部数据为 JSON 文件，换机/重装可恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('从备份恢复'),
            subtitle: const Text('选择备份 JSON，恢复前会再次确认（覆盖现有数据）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _restoreBackup,
          ),
          // 只读：自动备份由 App 启动时静默完成（约每 7 天一份，保留最近 3 份）
          FutureBuilder<DateTime?>(
            future: _lastAuto,
            builder: (context, snap) {
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
          ),
          const _Header('危险操作'),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
            title: Text('恢复出厂', style: TextStyle(color: scheme.error)),
            subtitle: const Text('清空全部学期、课程、设置与导入字体，不可撤销'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _factoryReset,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
