import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../database/dao.dart';
import '../models/ui_settings.dart';

/// 用户导入的一款字体（1.2.1）
///
/// 文件存 App 私有目录 fonts/ 下（文件名 = [id].[ext]），
/// 运行时通过 FontLoader 注册为 family `Imported_<id>`，
/// UiSettings.fontId 存的就是这个 id（imp_ 前缀）。
class ImportedFont {
  const ImportedFont({required this.id, required this.name, required this.ext});

  /// 唯一 id：imp_<毫秒时间戳>
  final String id;

  /// 显示名（源文件名去掉扩展名）
  final String name;

  /// 文件扩展名：ttf / otf
  final String ext;

  /// FontLoader 注册用的 family 名
  String get family => 'Imported_$id';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'ext': ext};

  static ImportedFont? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], ext = j['ext'];
    if (id is! String || !id.startsWith('imp_')) return null;
    if (name is! String || name.isEmpty) return null;
    if (ext is! String || (ext != 'ttf' && ext != 'otf')) return null;
    return ImportedFont(id: id, name: name, ext: ext);
  }
}

/// 导入字体服务：注册表存 app_settings.imported_fonts（JSON），
/// 启动时（runApp 前）加载全部已导入字体，设置页负责导入/删除/选用。
///
/// 已知边界：TTC 合集不支持；仅单字重（粗体为引擎合成）；
/// 字体文件不进备份——恢复备份后注册表条目若文件缺失会自动剔除。
class FontsService {
  FontsService._();

  static const String _registryKey = 'imported_fonts';
  static List<ImportedFont> _fonts = [];

  /// 当前已导入且文件完好的字体
  static List<ImportedFont> get fonts => List.unmodifiable(_fonts);

  static bool isImportedId(String fontId) => fontId.startsWith('imp_');

  static ImportedFont? byId(String fontId) {
    for (final f in _fonts) {
      if (f.id == fontId) return f;
    }
    return null;
  }

  /// 主题实际字体：导入字体查注册表，内置字体走 UiSettings 映射
  static String? resolveFamily(UiSettings ui) =>
      isImportedId(ui.fontId) ? byId(ui.fontId)?.family : ui.fontFamily;

  static Future<Directory> _fontsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/fonts');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 启动初始化：读注册表 → 逐个注册加载；文件缺失的条目剔除并回写注册表
  static Future<void> init() async {
    try {
      final raw = await Dao.instance.getSetting(_registryKey);
      final registered = decodeRegistry(raw);
      final dir = await _fontsDir();
      final alive = <ImportedFont>[];
      for (final f in registered) {
        final file = File('${dir.path}/${f.id}.${f.ext}');
        if (!await file.exists()) continue;
        try {
          await _register(f, file);
          alive.add(f);
        } catch (e) {
          debugPrint('导入字体加载失败（已跳过）：${f.name}，$e');
        }
      }
      _fonts = alive;
      if (alive.length != registered.length) await _persist();
    } catch (e) {
      debugPrint('导入字体初始化失败：$e');
    }
  }

  static Future<void> _register(ImportedFont font, File file) async {
    final bytes = await file.readAsBytes();
    final loader = FontLoader(font.family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  /// 导入一个字体文件：复制进私有目录 → 注册加载（无效文件会抛错并清理）
  /// → 写注册表。成功返回字体记录，调用方一般随即把它设为当前字体。
  static Future<ImportedFont> importFont(File src, String displayName) async {
    final ext = src.path.split('.').last.toLowerCase();
    final id = 'imp_${DateTime.now().millisecondsSinceEpoch}';
    final font = ImportedFont(id: id, name: displayName, ext: ext);
    final dir = await _fontsDir();
    final dest = File('${dir.path}/$id.$ext');
    await src.copy(dest.path);
    try {
      await _register(font, dest);
    } catch (e) {
      try {
        await dest.delete();
      } catch (_) {}
      rethrow;
    }
    _fonts = [..._fonts, font];
    await _persist();
    return font;
  }

  /// 删除一款导入字体（文件 + 注册表）。
  /// 注：FontLoader 注册的 family 在本进程内无法注销，重启后才彻底消失；
  /// 若删的是当前字体，调用方需同时把 fontId 切回系统默认。
  static Future<void> removeFont(ImportedFont font) async {
    _fonts = _fonts.where((f) => f.id != font.id).toList();
    await _persist();
    try {
      final dir = await _fontsDir();
      final file = File('${dir.path}/${font.id}.${font.ext}');
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('删除导入字体文件失败：$e');
    }
  }

  static Future<void> _persist() =>
      Dao.instance.setSetting(_registryKey, encodeRegistry(_fonts));

  /// 注册表编解码（纯函数，便于测试）
  static String encodeRegistry(List<ImportedFont> fonts) =>
      jsonEncode(fonts.map((f) => f.toJson()).toList());

  static List<ImportedFont> decodeRegistry(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(ImportedFont.fromJson).whereType<ImportedFont>().toList();
    } catch (_) {
      return const [];
    }
  }
}
