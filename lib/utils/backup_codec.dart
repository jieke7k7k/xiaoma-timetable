import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/course.dart';
import '../models/course_override.dart';
import '../models/note.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';

/// JSON 备份的编解码 + 恢复入库（阶段五·备份恢复）
///
/// 三条铁律（为什么这么设计）：
/// 1. **先校验后动手**：[decode] 全程只在内存里解析校验，任何结构问题都抛出
///    带中文信息的 [BackupFormatException]；只有校验全部通过，[restore] 才会
///    碰数据库，把「坏文件破坏现有数据」的可能拦在确认弹窗之前。
/// 2. **单事务原子恢复**：[restore] 在一个事务里清空重建，任何一步失败整体
///    回滚，现有数据不会出现「删了一半」的状态。
/// 3. **外键重映射**：恢复后自增 id 必然与备份时不同，课程/调课记录通过
///    「旧 id → 新 id」映射重建归属关系，绝不照抄备份里的 id。
///
/// 备份 JSON 顶层结构（字段名与本项目数据表一一对应，非照搬外部项目）：
/// ```json
/// {
///   "app": "simple_timetable",
///   "version": 3,
///   "exportedAt": "2026-10-15T12:00:00.000",
///   "semesters": [...], "timeSlots": [...],
///   "courses": [...], "courseOverrides": [...],
///   "appSettings": { "key": "value" },
///   "notes": [{ "id": 1, "date": "2026-10-23", "content": "...", ... }],
///   "fonts": [{ "name": "...", "fileName": "imp_1.ttf", "base64": "..." }]
/// }
/// ```
/// version 字段用于未来字段变更时的兼容判断：导入比当前 App 更新的版本时
/// 直接拒绝并提示升级，避免把新格式解析成错误数据。
///
/// v2（1.3.5）新增可选段 fonts：把用户导入的自定义字体文件以 base64 带进备份，
/// 恢复时写回字体目录并重新注册。v1 备份没有这一段，[decode] 按空列表处理，
/// 其余部分照常恢复（见 [BackupData.fonts]）。
///
/// v3（2.0.0）新增可选段 notes：备注此前是唯一没进备份的业务数据（丢备份＝丢
/// 全部备忘）。v1/v2 备份没有这一段，[decode] 按空列表处理，与 fonts 段同一套
/// 兼容做法。同一版起 [secretSettingKeys] 列出的四个键（AI Key 与桥的
/// 令牌/仓库）永不写进备份，恢复时也以本机值为准——备份文件是要能随手分享的，
/// 带上凭据就是泄露。
class BackupCodec {
  BackupCodec._();

  /// 当前备份格式版本。未来若字段变更（增/删/改含义）必须 +1，
  /// 并在 [decode] 里为旧版本写兼容分支。
  ///
  /// v3（2.0.0）：新增 notes 段（备注进备份）。
  static const int backupVersion = 3;

  /// 备份文件归属标记（信息性字段，version 才是格式判断依据）
  static const String appTag = 'simple_timetable';

  /// **永不进备份**的设置键（2.0.0 复审 B2）。
  ///
  /// 这四个键都是「本机凭据」：AI 的 Key 与 AI 桥的令牌（以及它指向哪个仓库）。
  /// 备份文件的用途是换机/重装，甚至是随手发给别人帮忙看一眼，带上凭据等于
  /// 把密钥交出去。集中成一份常量集合，是为了 [encode]（剔除）与 [restore]
  /// （保留本机值）共用同一份名单，将来新增凭据键只改这一处。
  ///
  /// 用户侧文案已同步：页面里「别外发备份文件」的提示改为「备份里不含密钥」。
  static const Set<String> secretSettingKeys = {
    'ai_api_key',
    'bridge_token',
    'bridge_owner',
    'bridge_repo',
  };

  /// 云同步水位键（须与 `SupabaseSyncService.lastSyncAtKey` 保持一致）。
  ///
  /// 它不属于机密键、正常进备份；但恢复时**强制归零**——见 [restore]，
  /// 等价于恢复后下一次同步重新走「首次迁移」全量上传（upsert 幂等），
  /// 避免沿用备份里的旧水位把恢复进来的课程/备注当成「已同步过」而漏传。
  static const String syncWatermarkKey = 'supabase_last_sync_at';

  /// 剔除机密键后的设置副本（[encode] 用）。不修改入参。
  static Map<String, String> stripSecretSettings(Map<String, String> settings) =>
      {
        for (final e in settings.entries)
          if (!secretSettingKeys.contains(e.key)) e.key: e.value,
      };

  /// 单个字体文件进备份的体积上限（8MB）。
  ///
  /// 字体以 base64 写进 JSON，体积还要再膨胀约 1/3；超限的文件直接跳过，
  /// 否则一份备份就几十 MB，写文件、分享、恢复都变慢。跳过会让 [BackupFontPack]
  /// 多一条中文提示，由 UI 转达给用户。
  static const int maxFontBytes = 8 * 1024 * 1024;

  /// 导出：模型对象 → 备份 JSON 结构。
  /// 字段直接复用各模型的 toMap()，与数据库行内容一一对应，不引入第二套字段名。
  ///
  /// [fonts] 为已按体积过滤好的字体（见 [collectFonts]），不传就没有 fonts 段
  /// 之外的额外开销；这里不做任何体积判断，保持 encode 是纯组装。
  ///
  /// [settings] 里的 [secretSettingKeys] 一律剔除（见那里的说明）：手动导出与
  /// 启动自动备份都走这一个函数，两条路径天然一致，不存在「手动备份带密钥、
  /// 自动备份不带」这种靠人记的区别。
  static Map<String, dynamic> encode({
    required List<Semester> semesters,
    required List<TimeSlot> timeSlots,
    required List<Course> courses,
    required List<CourseOverride> overrides,
    required Map<String, String> settings,
    List<Note> notes = const [],
    List<BackupFont> fonts = const [],
    DateTime? now,
  }) =>
      {
        'app': appTag,
        'version': backupVersion,
        'exportedAt': (now ?? DateTime.now()).toIso8601String(),
        'semesters': [for (final s in semesters) s.toMap()],
        'timeSlots': [for (final t in timeSlots) t.toMap()],
        'courses': [for (final c in courses) c.toMap()],
        'courseOverrides': [for (final o in overrides) o.toMap()],
        'appSettings': stripSecretSettings(settings),
        'notes': [for (final n in notes) n.toMap()],
        'fonts': [for (final f in fonts) f.toJson()],
      };

  /// 按体积上限过滤待备份的字体：超过 [maxFontBytes] 的跳过，并在返回的
  /// [BackupFontPack.warnings] 里留下可直接展示给用户的中文提示。
  ///
  /// 与 encode 分开是为了单测能脱离数据库/文件系统直接验证「超限跳过」。
  static BackupFontPack collectFonts(
    List<BackupFont> fonts, {
    int maxBytes = maxFontBytes,
  }) {
    final kept = <BackupFont>[];
    final warnings = <String>[];
    final limitMb = maxBytes ~/ (1024 * 1024);
    for (final f in fonts) {
      if (f.bytes.lengthInBytes > maxBytes) {
        warnings.add('字体「${f.name}」超过 ${limitMb}MB，未写入备份');
        continue;
      }
      kept.add(f);
    }
    return (fonts: kept, warnings: warnings);
  }

  /// 解析 + 校验备份文本。任何问题抛 [BackupFormatException]，
  /// message 为可直接展示给用户的中文描述。
  static BackupData decode(String content) {
    final dynamic root;
    try {
      root = jsonDecode(content);
    } catch (_) {
      throw const BackupFormatException('文件不是有效的 JSON，可能已损坏或选错了文件');
    }
    if (root is! Map<String, dynamic>) {
      throw const BackupFormatException('备份文件结构不正确（顶层不是对象）');
    }

    // 版本检查：过新拒绝（用户需先升级 App），非法值视为不是本 App 的备份
    final version = root['version'];
    if (version is! int) {
      throw const BackupFormatException('缺少版本号字段，可能不是「小马课表」的备份文件');
    }
    if (version > backupVersion) {
      throw BackupFormatException(
          '备份文件版本过新（v$version），当前 App 只支持到 v$backupVersion，请先升级 App');
    }
    if (version < 1) {
      throw const BackupFormatException('版本号无法识别，可能不是「小马课表」的备份文件');
    }

    // 学期：必填且至少一条，否则整个备份没有意义
    final semesters = _parseList<Semester>(root['semesters'], '学期', (m) {
      final s = Semester.fromMap(m);
      if (s.name.trim().isEmpty) throw '学期名为空';
      if (DateTime.tryParse(s.startDate) == null) {
        throw '开学日期「${s.startDate}」无法识别';
      }
      return s;
    });
    if (semesters.isEmpty) {
      throw const BackupFormatException('备份文件中没有学期数据，可能不是「小马课表」的备份文件');
    }
    // 宽容处理：个别学期缺 id 时补一个不冲突的自造 id（第三方手改的备份可能没有）
    var nextId = semesters.fold(0, (m, s) => (s.id ?? 0) > m ? s.id! : m) + 1;
    final fixedSemesters = [
      for (final s in semesters)
        s.id == null ? s.copyWith(id: nextId++) : s,
    ];

    final semesterIds = fixedSemesters.map((s) => s.id!).toSet();
    final timeSlots =
        _parseList<TimeSlot>(root['timeSlots'], '节次时间', TimeSlot.fromMap);

    // 课程：id 必须有（调课记录要靠它映射），所属学期必须存在
    final courses = _parseList<Course>(root['courses'], '课程', (m) {
      final c = Course.fromMap(m);
      if (c.name.trim().isEmpty) throw '课程名为空';
      if (c.id == null) throw '缺少 id 字段';
      if (!semesterIds.contains(c.semesterId)) {
        throw '「${c.name}」所属学期(id=${c.semesterId})在备份中不存在，文件可能不完整';
      }
      return c;
    });
    final courseIds = courses.map((c) => c.id!).toSet();

    // 调课记录：对应课程必须存在
    final overrides = _parseList<CourseOverride>(
        root['courseOverrides'], '单次调课', (m) {
      final o = CourseOverride.fromMap(m);
      if (!courseIds.contains(o.courseId)) {
        throw '对应课程(id=${o.courseId})在备份中不存在，文件可能不完整';
      }
      return o;
    });

    // 应用设置：宽容处理，缺失或结构不对都按空处理（恢复后用默认设置）
    final settingsRaw = root['appSettings'];
    final settings = <String, String>{};
    if (settingsRaw is Map) {
      settingsRaw.forEach((k, v) {
        if (k is String) settings[k] = '$v';
      });
    }

    // 备注（v3 新增段）：与 fonts 段同一套兼容做法——旧备份没有这一段按空列表
    // 处理，单条结构不对（没有 date）只跳过那一条。少恢复一条备忘的代价，
    // 远小于一整份本来完好的课表备份恢复失败。
    final notes = <Note>[];
    final notesRaw = root['notes'];
    if (notesRaw is List) {
      for (var i = 0; i < notesRaw.length; i++) {
        final raw = notesRaw[i];
        if (raw is! Map || raw['date'] is! String) {
          debugPrint('备份中第 ${i + 1} 条备注数据无法识别，已跳过');
          continue;
        }
        notes.add(Note.fromMap(Map<String, dynamic>.from(raw)));
      }
    }

    // 自定义字体（v2 新增段）：旧备份没有这一段 → 空列表，照常恢复不报错。
    // 单条结构不对/base64 非法也只跳过那一条——字体丢了最多回退默认字体，
    // 不该让一整份本来完好的课表备份恢复失败。
    final fonts = <BackupFont>[];
    final fontsRaw = root['fonts'];
    if (fontsRaw is List) {
      for (var i = 0; i < fontsRaw.length; i++) {
        final f = BackupFont.fromJson(fontsRaw[i]);
        if (f == null) {
          debugPrint('备份中第 ${i + 1} 个字体数据无法识别，已跳过');
          continue;
        }
        fonts.add(f);
      }
    }

    return BackupData(
      semesters: _normalizeCurrent(fixedSemesters),
      timeSlots: timeSlots,
      courses: courses,
      courseOverrides: overrides,
      appSettings: settings,
      notes: notes,
      fonts: fonts,
    );
  }

  /// 解析 JSON 数组字段为模型列表；缺失按空列表处理（向前兼容新字段），
  /// 单条解析失败只报那一条，错误信息点名序号方便用户定位。
  static List<T> _parseList<T>(
    dynamic raw,
    String label,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw BackupFormatException('「$label」数据结构不正确（不是数组）');
    }
    final result = <T>[];
    for (var i = 0; i < raw.length; i++) {
      try {
        final item = raw[i];
        if (item is! Map) throw '条目不是对象';
        result.add(parse(Map<String, dynamic>.from(item)));
      } on BackupFormatException {
        rethrow; // 内层已给出可直接展示的中文信息，不再包一层
      } catch (e) {
        throw BackupFormatException('第 ${i + 1} 条$label数据有误：$e');
      }
    }
    return result;
  }

  /// 归一化 isCurrent：全局有且只有一个当前学期。
  /// 取备份中第一个标记为当前的；一个都没有时回退到第一个学期，
  /// 保证恢复后 currentSemesterProvider 一定能读到值。
  static List<Semester> _normalizeCurrent(List<Semester> semesters) {
    final target = semesters.indexWhere((s) => s.isCurrent);
    final idx = target >= 0 ? target : 0;
    return [
      for (var i = 0; i < semesters.length; i++)
        semesters[i].copyWith(isCurrent: i == idx),
    ];
  }

  /// 恢复入库：单个事务内清空五张表再按备份重灌，任一步失败整体回滚。
  /// 成功返回恢复统计，由 UI 层组装提示文案。
  static Future<RestoreSummary> restore(Database db, BackupData data) async {
    // 恢复时刻：courses/notes 补 updatedAt 用（见下方两处），整次恢复同一时刻
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      // 先删子表（调课/课程）再删父表（学期），与外键方向一致；
      // app_settings 一并覆盖——备份是全量语义，主题/提醒设置跟着备份走
      await txn.delete('course_overrides');
      await txn.delete('courses');
      // 备注与学期/课程无外键，但同样属于「备份里的全量数据」，一并清空重灌
      await txn.delete('notes');
      await txn.delete('time_slots');

      // 清空 app_settings 之前先留住本机凭据：它们不进备份，恢复也不该清掉
      // （备份里若被人手改塞了这四个键，同样以本机为准，见下面的重灌循环）
      final localSecrets = await _readLocalSecrets(txn);

      await txn.delete('app_settings');
      await txn.delete('semesters');

      // 旧 id → 新 id 映射表：插入时去掉原 id 让自增重新分配
      final semesterIdMap = <int, int>{};
      for (final s in data.semesters) {
        final map = s.toMap()..remove('id');
        final newId = await txn.insert('semesters', map);
        if (s.id != null) semesterIdMap[s.id!] = newId;
      }
      final courseIdMap = <int, int>{};
      for (final c in data.courses) {
        final map = c.toMap()..remove('id');
        map['semesterId'] = semesterIdMap[c.semesterId];
        // P0-5：恢复的课程补 updatedAt=now，云同步能按新时间参与后续上传
        map['updatedAt'] = nowMs;
        final newId = await txn.insert('courses', map);
        if (c.id != null) courseIdMap[c.id!] = newId;
      }
      for (final o in data.courseOverrides) {
        final map = o.toMap()..remove('id');
        map['courseId'] = courseIdMap[o.courseId];
        await txn.insert('course_overrides', map);
      }
      for (final t in data.timeSlots) {
        await txn.insert('time_slots', t.toMap());
      }
      for (final e in data.appSettings.entries) {
        // 备份里的凭据键一律忽略（哪怕是老版本备份或被人手改塞进来的）
        if (secretSettingKeys.contains(e.key)) continue;
        // 云同步水位不进备份生效：恢复后强制归零（见下面），这里跳过备份值
        if (e.key == syncWatermarkKey) continue;
        await txn.insert('app_settings', {'key': e.key, 'value': e.value});
      }
      // 写回恢复前读到的本机凭据（本机本来没存这个键就不写，保持「没配」状态）
      for (final e in localSecrets.entries) {
        await txn.insert('app_settings', {'key': e.key, 'value': e.value});
      }
      // P0-5：云同步水位归零——恢复后等价于重新首次迁移，下次同步全量上传，
      // upsert 幂等、不会重复污染云端；机密键仍以本机为准，不受这里影响。
      await txn.insert('app_settings', {'key': syncWatermarkKey, 'value': '0'});
      for (final n in data.notes) {
        // 与其它表一致：去掉 id 让自增重新分配，不照抄备份里的 id
        // P0-5：恢复的备注同样补 updatedAt=now，参与后续云同步上传
        await txn.insert('notes', n.toMap()..remove('id')..['updatedAt'] = nowMs);
      }
    });
    return RestoreSummary(
      semesters: data.semesters.length,
      timeSlots: data.timeSlots.length,
      courses: data.courses.length,
      courseOverrides: data.courseOverrides.length,
      notes: data.notes.length,
    );
  }

  /// 事务内读出本机 [secretSettingKeys] 的当前值（键不存在就不出现在结果里）
  static Future<Map<String, String>> _readLocalSecrets(
    DatabaseExecutor txn,
  ) async {
    final placeholders = List.filled(secretSettingKeys.length, '?').join(', ');
    final rows = await txn.query(
      'app_settings',
      where: 'key IN ($placeholders)',
      whereArgs: secretSettingKeys.toList(),
    );
    return {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
  }
}

/// 解析后的备份内容（decode 的产物，校验已通过，可放心交给 restore）
class BackupData {
  const BackupData({
    required this.semesters,
    required this.timeSlots,
    required this.courses,
    required this.courseOverrides,
    required this.appSettings,
    this.notes = const [],
    this.fonts = const [],
  });

  final List<Semester> semesters;
  final List<TimeSlot> timeSlots;
  final List<Course> courses;
  final List<CourseOverride> courseOverrides;

  /// 备份里的设置；[secretSettingKeys] 那四个键不在此列（不进备份、也不生效）
  final Map<String, String> appSettings;

  /// 备份里的备注（v3 起有；旧备份为空列表）
  final List<Note> notes;

  /// 备份里携带的自定义字体文件（v2 起有；旧备份为空列表）
  final List<BackupFont> fonts;
}

/// 字体收集结果：[fonts] 是可写进备份的字体，[warnings] 需要让用户知道
/// （目前只有「某字体超限被跳过」一种）。
typedef BackupFontPack = ({List<BackupFont> fonts, List<String> warnings});

/// 备份里的一个自定义字体文件（v2 / 1.3.5）
///
/// 只在用户自己的备份文件里以 base64 形式流转，不做任何网络上传。
/// [fileName] 形如 `imp_1700000000000.ttf`，恢复时据此还原字体 id 与扩展名，
/// 从而与 app_settings 里的 imported_fonts 注册表对上号。
class BackupFont {
  const BackupFont({
    required this.name,
    required this.fileName,
    required this.bytes,
  });

  /// 显示名（导入时的源文件名去掉扩展名）
  final String name;

  /// 字体文件名（含扩展名），与字体目录内的实际文件名一致
  final String fileName;

  /// 字体文件原始字节
  final Uint8List bytes;

  /// 备份 JSON 里的编码形式
  String get base64 => base64Encode(bytes);

  Map<String, dynamic> toJson() => {
        'name': name,
        'fileName': fileName,
        'base64': base64Encode(bytes),
      };

  /// 宽容解析：字段类型不对或 base64 非法都返回 null（坏条目跳过，
  /// 不连累整份备份）。
  static BackupFont? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final fileName = raw['fileName'];
    final encoded = raw['base64'];
    if (name is! String || fileName is! String || encoded is! String) {
      return null;
    }
    if (fileName.isEmpty || encoded.isEmpty) return null;
    try {
      return BackupFont(
        name: name,
        fileName: fileName,
        bytes: base64Decode(encoded),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 恢复统计（UI 组装「恢复完成：X 个学期、Y 门课程」用）
class RestoreSummary {
  const RestoreSummary({
    required this.semesters,
    required this.timeSlots,
    required this.courses,
    required this.courseOverrides,
    this.notes = 0,
  });

  final int semesters;
  final int timeSlots;
  final int courses;
  final int courseOverrides;

  /// 恢复的备注条数（v3 备份起才有；旧备份为 0）
  final int notes;
}

/// 备份格式异常：message 为可直接展示给用户的中文描述，
/// toString 直接返回 message，UI 里「$e」即为可读文案。
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
