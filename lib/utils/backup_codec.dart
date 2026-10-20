import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/course.dart';
import '../models/course_override.dart';
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
///   "version": 1,
///   "exportedAt": "2026-10-15T12:00:00.000",
///   "semesters": [...], "timeSlots": [...],
///   "courses": [...], "courseOverrides": [...],
///   "appSettings": { "key": "value" }
/// }
/// ```
/// version 字段用于未来字段变更时的兼容判断：导入比当前 App 更新的版本时
/// 直接拒绝并提示升级，避免把新格式解析成错误数据。
class BackupCodec {
  BackupCodec._();

  /// 当前备份格式版本。未来若字段变更（增/删/改含义）必须 +1，
  /// 并在 [decode] 里为旧版本写兼容分支。
  static const int backupVersion = 1;

  /// 备份文件归属标记（信息性字段，version 才是格式判断依据）
  static const String appTag = 'simple_timetable';

  /// 导出：模型对象 → 备份 JSON 结构。
  /// 字段直接复用各模型的 toMap()，与数据库行内容一一对应，不引入第二套字段名。
  static Map<String, dynamic> encode({
    required List<Semester> semesters,
    required List<TimeSlot> timeSlots,
    required List<Course> courses,
    required List<CourseOverride> overrides,
    required Map<String, String> settings,
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
        'appSettings': settings,
      };

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

    return BackupData(
      semesters: _normalizeCurrent(fixedSemesters),
      timeSlots: timeSlots,
      courses: courses,
      courseOverrides: overrides,
      appSettings: settings,
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
    await db.transaction((txn) async {
      // 先删子表（调课/课程）再删父表（学期），与外键方向一致；
      // app_settings 一并覆盖——备份是全量语义，主题/提醒设置跟着备份走
      await txn.delete('course_overrides');
      await txn.delete('courses');
      await txn.delete('time_slots');
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
        await txn.insert('app_settings', {'key': e.key, 'value': e.value});
      }
    });
    return RestoreSummary(
      semesters: data.semesters.length,
      timeSlots: data.timeSlots.length,
      courses: data.courses.length,
      courseOverrides: data.courseOverrides.length,
    );
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
  });

  final List<Semester> semesters;
  final List<TimeSlot> timeSlots;
  final List<Course> courses;
  final List<CourseOverride> courseOverrides;
  final Map<String, String> appSettings;
}

/// 恢复统计（UI 组装「恢复完成：X 个学期、Y 门课程」用）
class RestoreSummary {
  const RestoreSummary({
    required this.semesters,
    required this.timeSlots,
    required this.courses,
    required this.courseOverrides,
  });

  final int semesters;
  final int timeSlots;
  final int courses;
  final int courseOverrides;
}

/// 备份格式异常：message 为可直接展示给用户的中文描述，
/// toString 直接返回 message，UI 里「$e」即为可读文案。
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
