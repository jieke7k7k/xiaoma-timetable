import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/time_slot.dart';

/// SQLite 数据库管理（单例）
///
/// 设计说明：v2 的 app_settings、v3 的 notes 走版本升级补建外，其余业务表在建库时
/// 一次性建好（含阶段五才用到的 course_overrides），尽量避免迁移，降低维护成本。
///
/// 2.1.3（WB_SPEC_214 第 2 节）反向做了一次收缩：v4 引入的两张表随对应功能整体
/// 移除，v6 的升级分支只做「删表 + 清键」，不再新建任何表。
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  static const _dbName = 'simple_timetable.db';
  /// v3（2026-10-22）：新增 notes 备注表。
  /// v4（2026-10-24）：新增两张表（对话历史、操作记录）。
  /// v5（2.1.0）：courses 加 examEndTime/examPlace/updatedAt、notes 加 updatedAt
  /// （云同步水位与冲突判断用）。升级路径见 [upgradeSchema]——老库只补列，数据零改动。
  /// v6（2.1.3）：上述 v4 的两张表整体移除（DROP），并一次性清掉十个遗留设置键。
  /// 新装用户由 [createSchema] 直接建成 v6 结构，不含这两张表。
  static const _dbVersion = 6;

  /// v6 升级时一次性删除的遗留表（2.1.3 WB_SPEC_214 第 2 节）。
  ///
  /// 集中成一份名单是为了「升级分支只写一遍 DROP 循环」，迁移测试也可以直接遍历
  /// 它做断言，lib 里不会有第二处引用。顺序与建表顺序相反（后建的先删）；两表之间
  /// 无外键关联，先后其实不影响结果，只是保持习惯。
  static const List<String> retiredTables = ['operation_log', 'chat_sessions'];

  /// v6 升级时一次性清掉的遗留设置键（2.1.3 WB_SPEC_214 第 2 节，exact key）。
  ///
  /// 三类：内置对话功能的接口配置三项、解锁开关一项、外部信箱同步的六项。
  /// 这些键只在「升到 2.1.3」的这一次升级里被 DELETE，之后启动代码不再碰它们——
  /// 出厂重置、重装都不会重新写回（写它们的功能已经不存在了）。
  ///
  /// 说明：这是**唯一**还会出现这些键名的地方，且只出现在 DELETE 的 where 参数里，
  /// 没有任何读写路径；静态扫描门禁搜到的就是本名单，属于规格第 2 节要求的
  /// 「按 exact key 清理」的必要常量，不是残留功能。
  static const List<String> retiredSettingKeys = [
    'ai_base_url',
    'ai_model',
    'ai_api_key',
    'developer_options_unlocked',
    'bridge_owner',
    'bridge_repo',
    'bridge_token',
    'processed_command_ids',
    'bridge_pending',
    'last_bridge_sync',
  ];

  /// 应用设置键值表 SQL（阶段四：提醒开关/提前分钟等轻量偏好持久化）
  static const _createSettingsTableSql = '''
    CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''';

  /// 备注表 SQL（v3 的历史建表语句）：按日期组织的短备注，供备注页/常驻通知/
  /// 桌面小部件使用。仅供 onUpgrade 的老库补建（v2 → v3 路径）复用，
  /// updatedAt 列由 v5 的 ALTER 统一补上（见 onUpgrade）。
  ///
  /// 带 `IF NOT EXISTS`：老库升级时若表已存在（比如手工改过库），没有它会直接
  /// 抛错、让整个打开流程失败——与 app_settings 那条补建 SQL 同一写法。
  static const _createNotesTableSql = '''
    CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      content TEXT NOT NULL,
      createdAt INTEGER NOT NULL
    )
  ''';

  /// 备注表 SQL（新装，v5 起）：在 v3 结构上多一列 updatedAt（云同步水位用）。
  /// 只被 [createSchema] 使用，onUpgrade 的老库补建仍走 [_createNotesTableSql]，
  /// 再由 v5 分支 ALTER 补列，避免「建表已含列 + ALTER 再加」的重复列冲突。
  static const _createNotesTableSyncSql = '''
    CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL,
      content TEXT NOT NULL,
      createdAt INTEGER NOT NULL,
      updatedAt INTEGER
    )
  ''';

  Database? _db;

  /// 打开数据库的共享 Future（2.0.0 复审 C1）。
  ///
  /// 目的是**缓存打开失败**：升级 SQL 报错、磁盘满、库文件损坏时，旧写法
  /// `_db ??= await _open()` 会让每个调用点（启动瞬间十几个 provider 同时读库）
  /// 各自再跑一次 openDatabase → 再跑一遍 onUpgrade，错误刷屏且可能越修越坏。
  /// 共享 Future 之后「第一次失败即定论」，后续调用拿到同一个错误，不再重试。
  Future<Database>? _opening;

  /// 仅测试用：注入外部数据库实例（如 sqflite_common_ffi 的内存库），
  /// 注入后 [database] 直接返回它，不再走正常的打开流程
  @visibleForTesting
  void useDatabaseForTest(Database db) => _db = db;

  Future<Database> get database {
    final db = _db;
    if (db != null) return Future<Database>.value(db);
    return _opening ??= _open();
  }

  /// 恢复出厂（1.2.4 数据管理页）：关库并删除数据库文件。
  /// 下次访问 [database] 时会重新建库，createSchema 自动写入首启默认数据
  /// （默认学期 + 默认节次时间），等于回到刚安装好的状态。
  Future<void> resetAllData() async {
    await _db?.close();
    _db = null;
    // 缓存的打开结果（哪怕是个错误）一起作废：库都删了，下次必须重新打开
    _opening = null;
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, _dbName));
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) => createSchema(db),
      // 老库升级统一走 [upgradeSchema]（抽出来是为了让迁移测试能直接驱动同一份 SQL）。
      onUpgrade: upgradeSchema,
      // 降级（装回旧版本 App）时**不删库**（2.0.0 复审 C1）。
      // 默认的 onDatabaseDowngradeDelete 会直接把数据库文件删掉——一份课表是
      // 用户几小时的录入成果，只为「版本号比 App 预期的低」就清空，代价太大。
      // 取舍：旧版 App 读不动新版才有的表/键（v3 的 notes、后来的设置键），
      // 但本项目一路只做「新增表 + 新增键值」，旧版忽略未知列即可正常跑，
      // 风险远小于删库。真要重置，用户有「数据管理 → 恢复出厂」这个显式入口。
      onDowngrade: (db, oldVersion, newVersion) async {},
    );
    _db = db;
    return db;
  }

  /// 老库升级路径（v1 → v6 共用一条链，按 oldVersion 逐级补齐）。
  ///
  /// 公开给测试是为了让「2.1.2 库升 2.1.3」的迁移测试跑**真实**的这一份 SQL，
  /// 而不是测试里另抄一份——抄一份就失去了「测的就是线上代码」的意义。
  ///
  /// sqflite 已把 onCreate / onUpgrade 包在同一个事务里（失败整体回滚），
  /// 所以本方法内部不再自己开事务：删表与清键天然同事务，不会留下
  /// 「表删了、键还在」的中间态。
  @visibleForTesting
  Future<void> upgradeSchema(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    // v1 -> v2：新增 app_settings 键值表（阶段四提醒设置持久化）
    if (oldVersion < 2) {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS app_settings ('
        'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    }
    // v2 -> v3：新增 notes 备注表（老用户无感升级）
    if (oldVersion < 3) {
      await db.execute(_createNotesTableSql);
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_date ON notes(date)',
      );
    }
    // 原 v3 -> v4 分支（补建两张表）随 2.1.3 删除：这两张表已整体移除，
    // 升级链上没有再补建它们的理由；v3 老库升到 6 时直接由下方分支删干净。
    // v4 -> v5（2.1.0 云同步）：courses 补考试结束时间/地点与 updatedAt 水位列，
    // notes 补 updatedAt 水位列。全部可空，旧数据保持 null、一行不丢。
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE courses ADD COLUMN examEndTime TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN examPlace TEXT');
      await db.execute('ALTER TABLE courses ADD COLUMN updatedAt INTEGER');
      await db.execute('ALTER TABLE notes ADD COLUMN updatedAt INTEGER');
    }
    // v5 -> v6（2.1.3 WB_SPEC_214 第 2 节）：一次性删除两张遗留表并清掉十个
    // 遗留设置键。DROP 带 IF EXISTS：极早期老库（v1/v2，从未建过这两张表）直接
    // 升到 6 时不会报「no such table」；键清理用 exact key 名单，不误伤其它设置。
    if (oldVersion < 6) {
      for (final table in retiredTables) {
        await db.execute('DROP TABLE IF EXISTS $table');
      }
      final placeholders = List.filled(retiredSettingKeys.length, '?').join(', ');
      await db.delete(
        'app_settings',
        where: 'key IN ($placeholders)',
        whereArgs: retiredSettingKeys,
      );
    }
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
        examEndTime TEXT,
        examPlace TEXT,
        updatedAt INTEGER,
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

    // 备注表（v3：按日期的短备注，常驻通知与小组件按日取用；v5 起含 updatedAt）
    await db.execute(_createNotesTableSyncSql);
    await db.execute('CREATE INDEX idx_notes_date ON notes(date)');

    // 2.1.3：v4 的两张表已整体移除，新装用户直接建成没有它们的样子。

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
