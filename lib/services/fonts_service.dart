import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../database/dao.dart';
import '../models/ui_settings.dart';
import '../utils/backup_codec.dart';

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
/// 已知边界：TTC 合集不支持；仅单字重（粗体为引擎合成）。
/// 字体文件自 1.3.5 起随备份走（base64 写进 JSON 的 fonts 段），
/// 超过 8MB 的不进备份——恢复后这类条目文件缺失，启动 init() 会自动剔除。
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

  /// 读出当前已注册字体的文件内容，交给备份编码（1.3.5）。
  ///
  /// 只读 [fonts]（已确认文件存在且注册成功的那批）；个别文件读不到就跳过，
  /// 不进备份而已，不影响备份其余部分。
  static Future<List<BackupFont>> readForBackup() async {
    final dir = await _fontsDir();
    final result = <BackupFont>[];
    for (final f in _fonts) {
      final file = File('${dir.path}/${f.id}.${f.ext}');
      try {
        if (!await file.exists()) continue;
        result.add(BackupFont(
          name: f.name,
          fileName: '${f.id}.${f.ext}',
          bytes: await file.readAsBytes(),
        ));
      } catch (e) {
        debugPrint('读取字体文件失败（不进备份）：${f.name}，$e');
      }
    }
    return result;
  }

  /// 从备份恢复字体：写回字体目录 → 重新注册 → 补进注册表（1.3.5）。
  ///
  /// 恢复顺序上，app_settings（含 imported_fonts 注册表）已经先被备份覆盖，
  /// 所以这里只做「补充」：把本次真正写文件成功的条目并进注册表，
  /// 既不删减备份里的其他条目（如超限没进备份的字体，条目仍在），
  /// 也不把内存列表清成只剩恢复成功的那些。单个字体失败只跳过它自己。
  ///
  /// 返回成功恢复的字体数量。
  static Future<int> restoreFonts(List<BackupFont> fonts) async {
    if (fonts.isEmpty) return 0;
    final dir = await _fontsDir();
    final restored = <ImportedFont>[];
    for (final f in fonts) {
      try {
        final font = _fontForRestore(f);
        final file = File('${dir.path}/${font.id}.${font.ext}');
        await file.writeAsBytes(f.bytes, flush: true);
        await _register(font, file);
        restored.add(font);
      } catch (e) {
        debugPrint('备份中的字体恢复失败（已跳过）：${f.name}，$e');
      }
    }
    if (restored.isEmpty) return 0;

    // toList()：注册表为空时 decodeRegistry 返回的是 const []（不可改）
    final registry =
        decodeRegistry(await Dao.instance.getSetting(_registryKey)).toList();
    for (final f in restored) {
      registry.removeWhere((e) => e.id == f.id);
      registry.add(f);
    }
    await Dao.instance.setSetting(_registryKey, encodeRegistry(registry));

    // 内存列表只保留「注册表里有 + 本进程已注册过」的：本次恢复成功的，
    // 以及会话开始时就加载好的那些。其余条目要么文件缺失，要么下次启动
    // 由 init() 重新加载。
    final restoredIds = restored.map((f) => f.id).toSet();
    _fonts = [
      for (final f in registry)
        if (restoredIds.contains(f.id) ||
            _fonts.any((e) => e.id == f.id))
          f,
    ];
    return restored.length;
  }

  /// 从备份里的文件名还原字体记录。
  ///
  /// 文件名形如 `imp_1700000000000.ttf`：能解析出合法 id/扩展名就沿用
  /// （这样才对得上 ui_settings 里记住的 fontId），解析不出来就按当前时间
  /// 造一个新 id（界面设置会回退到默认字体，但至少字体文件不丢）。
  static ImportedFont _fontForRestore(BackupFont f) {
    final dot = f.fileName.lastIndexOf('.');
    final rawId = dot > 0 ? f.fileName.substring(0, dot) : f.fileName;
    final rawExt = dot > 0 ? f.fileName.substring(dot + 1).toLowerCase() : 'ttf';
    final ext = (rawExt == 'ttf' || rawExt == 'otf') ? rawExt : 'ttf';
    final id = rawId.startsWith('imp_') && rawId.length > 4
        ? rawId
        : 'imp_${DateTime.now().microsecondsSinceEpoch}';
    final name = f.name.trim().isEmpty ? id : f.name;
    return ImportedFont(id: id, name: name, ext: ext);
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
