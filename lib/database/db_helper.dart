import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/time_slot.dart';

/// SQLite 数据库管理（单例）
///
/// 设计说明：四张表在建库时一次性建好（含阶段五才用到的 course_overrides），
/// 避免后期新增字段触发 onUpgrade 迁移，降低维护成本。
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static const _dbName = 'simple_timetable.db';
  static const _dbVersion = 2;

  /// 应用设置键值表 SQL（阶段四：提醒开关/提前分钟等轻量偏好持久化）
  static const _createSettingsTableSql = '''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''';

  Database? _db;

  /// 仅测试用：注入外部数据库实例（如 sqflite_common_ffi 的内存库），
  /// 注入后 [database] 直接返回它，不再走正常的打开流程
  @visibleForTesting
  void useDatabaseForTest(Database db) => _db = db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// 恢复出厂（1.2.4 数据管理页）：关库并删除数据库文件。
  /// 下次访问 [database] 时会重新建库，createSchema 自动写入首启默认数据
  /// （默认学期 + 默认节次时间），等于回到刚安装好的状态。
  Future<void> resetAllData() async {
    await _db?.close();
    _db = null;
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, _dbName));
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) => createSchema(db),
      // v1 -> v2：新增 app_settings 键值表（阶段四提醒设置持久化）
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS app_settings ('
            'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        }
      },
    );
  }

  /// 建表 + 首启默认数据（默认学期、12 节默认节次时间）。
  /// 公开出来供单元测试在内存库上复用同一套 SQL，避免测试与生产 schema 脱节。
  @visibleForTesting
  Future<void> createSchema(Database db) async {
    // 学期表
    await db.execute('''
      CREATE TABLE semesters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        startDate TEXT NOT NULL,
        totalWeeks INTEGER NOT NULL DEFAULT 20,
        isCurrent INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 节次时间表（section 作为主键，每个学期暂共用一套，阶段四多学期再评估拆分）
    await db.execute('''
      CREATE TABLE time_slots (
        section INTEGER PRIMARY KEY,
        startTime TEXT NOT NULL,
        endTime TEXT NOT NULL
      )
    ''');

    // 课程表
    await db.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        semesterId INTEGER NOT NULL,
        name TEXT NOT NULL,
        teacher TEXT,
        classroom TEXT,
        colorValue INTEGER NOT NULL,
        dayOfWeek INTEGER NOT NULL,
        startSection INTEGER NOT NULL,
        endSection INTEGER NOT NULL,
        weeksJson TEXT NOT NULL,
        weekType INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        examDate INTEGER,
        FOREIGN KEY (semesterId) REFERENCES semesters(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_courses_semester ON courses(semesterId, dayOfWeek)',
    );

    // 单次调课表（阶段五预留，先建表避免迁移）
    await db.execute('''
      CREATE TABLE course_overrides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER NOT NULL,
        originalWeek INTEGER NOT NULL,
        targetWeek INTEGER NOT NULL,
        targetDayOfWeek INTEGER,
        targetStartSection INTEGER,
        targetEndSection INTEGER,
        targetClassroom TEXT,
        FOREIGN KEY (courseId) REFERENCES courses(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_overrides_course ON course_overrides(courseId, originalWeek)',
    );

    // 应用设置键值表（阶段四：上课提醒开关、提前分钟等）
    await db.execute(_createSettingsTableSql);

    // 首次启动：创建默认学期（开学日期 2026-09-07，当天恰好是周一）和默认节次时间
    await db.insert('semesters', {
      'name': '默认学期',
      'startDate': '2026-09-07',
      'totalWeeks': 20,
      'isCurrent': 1,
    });
    for (final slot in defaultTimeSlots) {
      await db.insert('time_slots', slot.toMap());
    }
  }
}

/// 内置默认节次时间（13 节，上午 5 节 + 下午 4 节 + 晚上 4 节，每节 40 分钟）
/// 与分段默认点（午休在第 5 节后、晚餐在第 9 节后）对齐；
/// 导入课表文件后会按文件自动校准，用户也可在设置页逐节修改
final List<TimeSlot> defaultTimeSlots = [
  const TimeSlot(section: 1, startTime: '08:00', endTime: '08:40'),
  const TimeSlot(section: 2, startTime: '08:50', endTime: '09:30'),
  const TimeSlot(section: 3, startTime: '09:40', endTime: '10:20'),
  const TimeSlot(section: 4, startTime: '10:30', endTime: '11:10'),
  const TimeSlot(section: 5, startTime: '11:20', endTime: '12:00'),
  const TimeSlot(section: 6, startTime: '14:00', endTime: '14:40'),
  const TimeSlot(section: 7, startTime: '14:50', endTime: '15:30'),
  const TimeSlot(section: 8, startTime: '15:40', endTime: '16:20'),
  const TimeSlot(section: 9, startTime: '16:30', endTime: '17:10'),
  const TimeSlot(section: 10, startTime: '18:00', endTime: '18:40'),
  const TimeSlot(section: 11, startTime: '18:50', endTime: '19:30'),
  const TimeSlot(section: 12, startTime: '19:40', endTime: '20:20'),
  const TimeSlot(section: 13, startTime: '20:30', endTime: '21:10'),
];
