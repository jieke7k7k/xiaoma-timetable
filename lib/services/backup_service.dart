import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../database/db_helper.dart';
import '../utils/backup_codec.dart';

/// 备份/导出文件服务（阶段五）
///
/// 只负责「文件怎么选、怎么存、怎么读」这类平台相关的脏活；
/// 数据的组装与校验在 [BackupCodec]（纯逻辑，可脱离文件系统单测）。
/// 异常一律向上抛，由 UI 层 catch 后转成中文提示，本层不做吞异常。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// 弹出系统文件选择器，让用户选一个 JSON 备份文件；取消返回 null
  Future<String?> pickJsonFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return null;
    return files.first.path;
  }

  /// 读取并解析备份文件。只做内存校验、不写数据库 —— 落实「先校验后动手」：
  /// 任何格式问题都在用户确认覆盖之前暴露，此时现有数据零风险。
  Future<BackupData> readBackup(String path) async {
    final content = await File(path).readAsString();
    return BackupCodec.decode(content);
  }

  /// 执行恢复：单个事务内清空重建，失败自动回滚（细节见 BackupCodec.restore）。
  /// 成功后由调用方负责刷新 Provider 与通知/小组件联动。
  Future<RestoreSummary> restore(BackupData data) async {
    final db = await DbHelper.instance.database;
    return BackupCodec.restore(db, data);
  }

  /// 通过系统「保存到…」选择器把文本写到用户选择的位置。
  /// Android 上传入 bytes 会让选择器直接落盘写入，返回最终保存路径；
  /// 用户取消返回 null。
  ///
  /// file_picker 13.x 的 saveFile 返回 Future<Uri?>，这里转成路径字符串，
  /// 与 [pickJsonFile] 的返回约定保持一致。
  Future<String?> saveTextFile({
    required String fileName,
    required String content,
    required String extension,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final uri = await FilePicker.saveFile(
      dialogTitle: '选择保存位置',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: bytes,
    );
    return uri?.toFilePath();
  }
}
