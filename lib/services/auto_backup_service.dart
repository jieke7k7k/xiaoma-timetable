import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/dao.dart';
import 'backup_service.dart';

/// 自动备份（1.3.5）：防丢数据的兜底网。
///
/// 时机：App 启动首帧后（挂在 HomeShell 的启动联动里）。距上次自动备份超过
/// [intervalDays] 天、或从未备份过，就自动生成一份。
/// 落点：应用文档目录 `auto_backups/auto_backup_yyyyMMdd_HHmmss.json`，
/// 内容与手动导出完全同格式（同一个 BackupCodec）。
/// 轮转：只留最近 [keepCount] 份，多出来的删掉。
/// 容错：全程静默——失败只 debugPrint，绝不阻塞启动、不弹任何 UI。
class AutoBackupService {
  AutoBackupService._();

  /// 上次自动备份时间（app_settings 键，值存 ISO8601 字符串）
  static const String lastBackupAtKey = 'auto_backup_last_at';

  /// 距上次自动备份超过这个天数才重新生成
  static const int intervalDays = 7;

  /// 轮转保留的份数
  static const int keepCount = 3;

  static const String _dirName = 'auto_backups';
  static const String _prefix = 'auto_backup_';

  /// 到期就生成一份自动备份；没到期直接返回。任何异常都在内部吞掉。
  static Future<void> runIfDue({DateTime? now}) async {
    try {
      final t = now ?? DateTime.now();
      final last = await lastBackupAt();
      if (last != null &&
          t.difference(last) < const Duration(days: intervalDays)) {
        return;
      }
      final bundle = await BackupService.instance.buildBackup(now: t);
      for (final w in bundle.warnings) {
        debugPrint('自动备份提示：$w');
      }
      const pretty = JsonEncoder.withIndent('  ');
      await _write(t, pretty.convert(bundle.json));
      // 时间最后写：只有落盘成功才算数，下次启动不会跳过一份没生成的备份
      await Dao.instance.setSetting(lastBackupAtKey, t.toIso8601String());
      debugPrint('自动备份完成：${_fileName(t)}');
    } catch (e) {
      debugPrint('自动备份失败（已忽略，不影响使用）：$e');
    }
  }

  /// 最近一次自动备份的时间；从未备份过返回 null（数据管理页只读展示用）
  static Future<DateTime?> lastBackupAt() async {
    final raw = await Dao.instance.getSetting(lastBackupAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static Future<File> _write(DateTime t, String content) async {
    final dir = await _backupDir();
    final file = File(p.join(dir.path, _fileName(t)));
    await file.writeAsString(content, flush: true);
    await _rotate(dir);
    return file;
  }

  static Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 只保留最近 [keepCount] 份：文件名内嵌 yyyyMMdd_HHmmss，字典序即时间先后。
  static Future<void> _rotate(Directory dir) async {
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File &&
          p.basename(e.path).startsWith(_prefix) &&
          e.path.endsWith('.json')) {
        files.add(e);
      }
    }
    if (files.length <= keepCount) return;
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final f in files.skip(keepCount)) {
      try {
        await f.delete();
      } catch (_) {
        // 删不掉就算了，下次启动还会再试；绝不因此报错
      }
    }
  }

  static String _fileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    // 带时分秒：同一天内多次触发（恢复出厂清空时间戳等）不会原地覆盖当天的好备份
    return '$_prefix${t.year}${two(t.month)}${two(t.day)}'
        '_${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }
}
