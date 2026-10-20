import 'package:sqflite/sqflite.dart';

import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import 'db_helper.dart';

/// 数据访问对象：封装四张表的增删改查
/// 所有数据库异常在此处统一捕获并向上抛出带中文信息的异常，由 UI 层友好提示
class Dao {
  Dao._();
  static final Dao instance = Dao._();

  Future<Database> get _db async => DbHelper.instance.database;

  // ---------- 学期 ----------

  Future<List<Semester>> getAllSemesters() async {
    final db = await _db;
    final rows = await db.query('semesters', orderBy: 'id ASC');
    return rows.map(Semester.fromMap).toList();
  }

  /// 获取当前激活学期；若无（理论上不会发生）则返回 null
  Future<Semester?> getCurrentSemester() async {
    final db = await _db;
    final rows =
        await db.query('semesters', where: 'isCurrent = 1', limit: 1);
    if (rows.isEmpty) return null;
    return Semester.fromMap(rows.first);
  }

  Future<int> insertSemester(Semester s) async {
    final db = await _db;
    return db.insert('semesters', s.toMap());
  }

  Future<int> updateSemester(Semester s) async {
    final db = await _db;
    return db.update('semesters', s.toMap(),
        where: 'id = ?', whereArgs: [s.id]);
  }

  /// 切换当前学期：事务内先把所有学期置为非当前，再激活目标学期
  Future<void> setCurrentSemester(int semesterId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update('semesters', {'isCurrent': 0});
      await txn.update('semesters', {'isCurrent': 1},
          where: 'id = ?', whereArgs: [semesterId]);
    });
  }

  Future<int> deleteSemester(int id) async {
    final db = await _db;
    // 先手动删除该学期下的课程与调课记录（部分 Android 版本外键级联未必开启）
    await db.transaction((txn) async {
      final courseRows = await txn
          .query('courses', columns: ['id'], where: 'semesterId = ?', whereArgs: [id]);
      for (final row in courseRows) {
        await txn.delete('course_overrides',
            where: 'courseId = ?', whereArgs: [row['id']]);
      }
      await txn.delete('courses', where: 'semesterId = ?', whereArgs: [id]);
      await txn.delete('semesters', where: 'id = ?', whereArgs: [id]);
    });
    return 1;
  }

  // ---------- 节次时间 ----------

  Future<List<TimeSlot>> getTimeSlots() async {
    final db = await _db;
    final rows = await db.query('time_slots', orderBy: 'section ASC');
    return rows.map(TimeSlot.fromMap).toList();
  }

  /// 保存节次时间：已有节次则更新，没有则插入。
  /// 导入校准可能扩出新节次（如第 13 节），纯 update 会静默丢弃，
  /// 故用 insert + replace 主键冲突策略实现 upsert。
  Future<void> updateTimeSlot(TimeSlot slot) async {
    final db = await _db;
    await db.insert('time_slots', slot.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- 课程 ----------

  Future<List<Course>> getCoursesBySemester(int semesterId) async {
    final db = await _db;
    final rows = await db.query('courses',
        where: 'semesterId = ?', whereArgs: [semesterId]);
    return rows.map(Course.fromMap).toList();
  }

  Future<int> insertCourse(Course c) async {
    final db = await _db;
    return db.insert('courses', c.toMap());
  }

  Future<int> updateCourse(Course c) async {
    final db = await _db;
    return db.update('courses', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<int> deleteCourse(int id) async {
    final db = await _db;
    await db.delete('course_overrides', where: 'courseId = ?', whereArgs: [id]);
    return db.delete('courses', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 备份导出（阶段五：跨学期全量读取） ----------

  /// 全部学期的所有课程（JSON 全量备份用，与 getCoursesBySemester 不同）
  Future<List<Course>> getAllCourses() async {
    final db = await _db;
    final rows = await db.query('courses');
    return rows.map(Course.fromMap).toList();
  }

  /// 全部单次调课记录（JSON 全量备份用）
  Future<List<CourseOverride>> getAllOverrides() async {
    final db = await _db;
    final rows = await db.query('course_overrides');
    return rows.map(CourseOverride.fromMap).toList();
  }

  // ---------- 单次调课（阶段五·节假日调课） ----------

  /// 某学期的全部单次调课记录（JOIN courses 按学期过滤）。
  /// 周视图渲染 / 提醒重排 / 常驻通知 / 小组件都按当前学期取这份数据。
  Future<List<CourseOverride>> getOverridesBySemester(int semesterId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT o.* FROM course_overrides o '
      'INNER JOIN courses c ON o.courseId = c.id '
      'WHERE c.semesterId = ?',
      [semesterId],
    );
    return rows.map(CourseOverride.fromMap).toList();
  }

  /// 保存单次调课（同一 (courseId, originalWeek) 至多一条）：
  /// 事务内先删旧记录再插入，重复调整等同覆盖，不会残留两条。
  Future<int> upsertOverride(CourseOverride o) async {
    final db = await _db;
    return db.transaction((txn) async {
      await txn.delete('course_overrides',
          where: 'courseId = ? AND originalWeek = ?',
          whereArgs: [o.courseId, o.originalWeek]);
      return txn.insert('course_overrides', o.toMap());
    });
  }

  Future<int> deleteOverride(int id) async {
    final db = await _db;
    return db.delete('course_overrides', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 应用设置（键值对，阶段四：提醒开关/提前分钟等） ----------

  Future<String?> getSetting(String key) async {
    final db = await _db;
    final rows =
        await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// 写入/覆盖设置项（键为 PRIMARY KEY，重复写走 replace）
  Future<void> setSetting(String key, String value) async {
    final db = await _db;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 读取布尔型设置（约定存 "1"/"0"）
  Future<bool> getSettingBool(String key, bool defaultValue) async {
    final v = await getSetting(key);
    if (v == null) return defaultValue;
    return v == '1' || v.toLowerCase() == 'true';
  }

  /// 读取整型设置（解析失败回退默认值）
  Future<int> getSettingInt(String key, int defaultValue) async {
    final v = await getSetting(key);
    return int.tryParse(v ?? '') ?? defaultValue;
  }

  /// 全部应用设置键值对（JSON 全量备份用）
  Future<Map<String, String>> getAllSettings() async {
    final db = await _db;
    final rows = await db.query('app_settings');
    return {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
  }
}
