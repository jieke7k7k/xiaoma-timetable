import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/school_entry.dart';

/// 学校目录加载与「最近使用」持久化服务
/// 复用 path_provider 应用文档目录小 JSON 文件模式（与 channel_state.json 同款），零新增依赖
class SchoolCatalogService {
  static const String defaultAssetPath = 'assets/data/schools.json';
  static const String _stateFileName = 'school_picker_state.json';

  final AssetBundle _bundle;
  final Future<Directory> Function() _getAppDocDir;

  SchoolCatalogService({
    AssetBundle? bundle,
    Future<Directory> Function()? getAppDocDir,
  })  : _bundle = bundle ?? rootBundle,
        _getAppDocDir = getAppDocDir ?? getApplicationDocumentsDirectory;

  /// 从 assets 加载学校列表；文件缺失、JSON 损坏或单条缺字段均静默跳过，绝不抛异常
  Future<List<SchoolEntry>> loadSchools({
    String assetPath = defaultAssetPath,
  }) async {
    try {
      final rawText = await _bundle.loadString(assetPath);
      return parseSchoolsJson(rawText);
    } catch (_) {
      return const [];
    }
  }

  /// 纯函数：解析学校列表 JSON 字符串，按原顺序返回有效条目，按 url 去重
  static List<SchoolEntry> parseSchoolsJson(String rawText) {
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is! List) return const [];

      final entries = <SchoolEntry>[];
      final seenUrls = <String>{};

      for (final item in decoded) {
        final entry = SchoolEntry.tryFromJson(item);
        if (entry == null) continue;
        // 唯一键为 url，重复项跳过（保留先出现的）
        if (seenUrls.add(entry.url)) {
          entries.add(entry);
        }
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  /// 读取上次选中的学校 url；文件不存在或损坏时返回 null
  Future<String?> loadLastUsedUrl() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final url = decoded['lastUsedUrl'];
        if (url is String && url.trim().isNotEmpty) {
          return url.trim();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 保存上次选中的学校 url；写入失败时静默忽略，不影响主流程
  Future<void> saveLastUsedUrl(String url) async {
    try {
      final file = await _stateFile();
      final payload = jsonEncode({
        'lastUsedUrl': url,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // 持久化失败不阻断选校流程
    }
  }

  Future<File> _stateFile() async {
    final dir = await _getAppDocDir();
    return File('${dir.path}/$_stateFileName');
  }
}
