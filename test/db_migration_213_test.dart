import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';

/// 2.1.3 数据库迁移测试（WB_SPEC_214 第 2 节）
///
/// 用一个**文件库**（不是内存库）模拟真实升级路径：先按 2.1.2 的 v5 结构建库并
/// 灌入「两张表有假数据 + 十个遗留键 + 正常课表数据 + 非 AI 设置键」，再用版本 6
/// 重新打开，让 sqflite 触发 [DbHelper.upgradeSchema]，最后断言：
/// 1. 两张表已不存在（新装路径也不建）；
/// 2. 十个遗留设置键已被删空，非 AI 设置键原样保留；
/// 3. 学期 / 节次 / 课程 / 调课 / 备注数据一行不丢、字段不变；
/// 4. 极早期老库（v1，从未有这两张表）升到 6 也不报错（DROP IF EXISTS）；
/// 5. 清理只在「升到 6」那一次发生，之后再启动不会反复清（避免把用户后来
///    手动恢复的旧备份数据每隔一次启动就删掉）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String dbPath;

  setUp(() {
    dbPath = p.join(
      Directory.systemTemp.path,
      'xiaoma_migration_${DateTime.now().microsecondsSinceEpoch}.db',
    );
  });

  tearDown(() async {
    // 文件库用完整路径建，测试结束删掉（不存在时 deleteDatabase 也安全）
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {
      // 清理失败不影响断言结果
    }
  });

  /// 2.1.2（v5）的建库语句：与当时的 createSchema 逐字一致，含两张待删的表、
  /// courses 的三个 v5 新列、notes 的 updatedAt。
  ///
  /// 刻意在测试里抄一份而不是调 lib 的 createSchema：迁移测试要固定「升级前的
  /// 样子」，如果复用今天已经被改过的建表代码，测的就不是老库了。
  Future<void> createLegacy212Schema(Database db) async {
    await db.execute('''
      CREATE TABLE semesters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        startDate TEXT NOT NULL,
        totalWeeks INTEGER NOT NULL DEFAULT 20,
        isCurrent INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE time_slots (
        section INTEGER PRIMARY KEY,
        startTime TEXT NOT NULL,
        endTime TEXT NOT NULL
      )
    ''');
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
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        content TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_notes_date ON notes(date)');
    // 下面两张就是本版要删掉的表（2.1.2 时还在）
    await db.execute('''
      CREATE TABLE chat_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        messagesJson TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE operation_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        createdAt INTEGER NOT NULL,
        source TEXT NOT NULL,
        summary TEXT NOT NULL,
        snapshotJson TEXT NOT NULL,
        undone INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// 灌入「2.1.2 用户」的典型数据：业务数据 + 十个遗留键 + 普通设置键
  Future<void> seedLegacyData(Database db) async {
    await db.insert('semesters', {
      'name': '2026 秋',
      'startDate': '2026-09-07',
      'totalWeeks': 20,
      'isCurrent': 1,
    });
    await db.insert('time_slots', {
      'section': 1,
      'startTime': '08:00',
      'endTime': '08:40',
    });
    await db.insert('time_slots', {
      'section': 2,
      'startTime': '08:50',
      'endTime': '09:30',
    });
    await db.insert('courses', {
      'semesterId': 1,
      'name': '线性代数',
      'teacher': '李老师',
      'classroom': 'B203',
      'colorValue': 0xFF6B8E7B,
      'dayOfWeek': 2,
      'startSection': 1,
      'endSection': 2,
      'weeksJson': '[1,2,3,4,5]',
      'weekType': 0,
      'note': '带计算器',
      'examDate': 1790000000000,
      'examEndTime': '11:00',
      'examPlace': '教三 201',
      'updatedAt': 1790000000000,
    });
    await db.insert('course_overrides', {
      'courseId': 1,
      'originalWeek': 3,
      'targetWeek': 4,
    });
    await db.insert('notes', {
      'date': '2026-10-23',
      'content': '交作业',
      'createdAt': 1000,
      'updatedAt': 1000,
    });
    // 两张待删表里的假数据：迁移后必须连表带数据一起消失
    await db.insert('chat_sessions', {
      'title': '旧对话',
      'createdAt': 1000,
      'updatedAt': 2000,
      'messagesJson': '[]',
    });
    await db.insert('operation_log', {
      'createdAt': 1000,
      'source': 'ai',
      'summary': '新增课程',
      'snapshotJson': '{}',
      'undone': 0,
    });
    // 十个遗留键（exact key）
    const legacy = {
      'ai_base_url': 'https://api.example.com/v1',
      'ai_model': 'glm-4-flash',
      'ai_api_key': 'sk-legacy-value',
      'developer_options_unlocked': '1',
      'bridge_owner': 'someone',
      'bridge_repo': 'mailbox',
      'bridge_token': 'ghp_legacy',
      'processed_command_ids': '["c1","c2"]',
      'bridge_pending': '[]',
      'last_bridge_sync': '1790000000000',
    };
    for (final e in legacy.entries) {
      await db.insert('app_settings', {'key': e.key, 'value': e.value});
    }
    // 与 AI 无关、必须活下来的设置键
    const kept = {
      'theme_mode': 'dark',
      'reminder_enabled': '1',
      'reminder_advance_minutes': '15',
      'ongoing_enabled': '0',
      'lunch_after_section': '5',
      'ui_settings': '{"showBottomBar":true}',
      'onboarding_done': '1',
    };
    for (final e in kept.entries) {
      await db.insert('app_settings', {'key': e.key, 'value': e.value});
    }
  }

  /// 按 App 的方式打开：onCreate / onUpgrade 都指向 DbHelper 里的同一份实现
  Future<Database> openAt(int version) => databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, v) => DbHelper.instance.createSchema(db),
      onUpgrade: (db, from, to) =>
          DbHelper.instance.upgradeSchema(db, from, to),
    ),
  );

  Future<bool> tableExists(Database db, String name) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [name],
    );
    return rows.isNotEmpty;
  }

  test('2.1.2（v5）升 2.1.3（v6）：两张表删除、十个遗留键清空、业务数据完好', () async {
    final legacyDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, v) => createLegacy212Schema(db),
      ),
    );
    await seedLegacyData(legacyDb);
    // 升级前先确认假数据真的写进去了（否则下面的「已删除」断言没有意义）
    expect(await tableExists(legacyDb, 'chat_sessions'), isTrue);
    expect(await tableExists(legacyDb, 'operation_log'), isTrue);
    await legacyDb.close();

    final db = await openAt(6);

    // 1) 两张表已不存在（连表带数据一起没了）
    expect(await tableExists(db, 'chat_sessions'), isFalse);
    expect(await tableExists(db, 'operation_log'), isFalse);

    // 2) 十个遗留键已删空
    for (final key in DbHelper.retiredSettingKeys) {
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      expect(rows, isEmpty, reason: '遗留键「$key」应被迁移清掉');
    }
    // 非 AI 设置键一个不少、值不变
    final settings = await db.query('app_settings');
    expect(settings.length, 7);
    final byKey = {
      for (final r in settings) r['key'] as String: r['value'] as String,
    };
    expect(byKey['theme_mode'], 'dark');
    expect(byKey['reminder_enabled'], '1');
    expect(byKey['reminder_advance_minutes'], '15');
    expect(byKey['ongoing_enabled'], '0');
    expect(byKey['lunch_after_section'], '5');
    expect(byKey['ui_settings'], '{"showBottomBar":true}');
    expect(byKey['onboarding_done'], '1');

    // 3) 业务数据一行不丢、字段不变
    final semesters = await db.query('semesters');
    expect(semesters.length, 1);
    expect(semesters.single['name'], '2026 秋');
    expect(semesters.single['isCurrent'], 1);
    final slots = await db.query('time_slots', orderBy: 'section ASC');
    expect(slots.length, 2);
    expect(slots.first['startTime'], '08:00');
    final courses = await db.query('courses');
    expect(courses.length, 1);
    expect(courses.single['name'], '线性代数');
    expect(courses.single['teacher'], '李老师');
    expect(courses.single['examPlace'], '教三 201');
    expect(courses.single['note'], '带计算器');
    final overrides = await db.query('course_overrides');
    expect(overrides.length, 1);
    expect(overrides.single['targetWeek'], 4);
    final notes = await db.query('notes');
    expect(notes.length, 1);
    expect(notes.single['content'], '交作业');

    await db.close();
  });

  test('新装（v6）不再建这两张表', () async {
    final db = await openAt(6);
    // 新装走 createSchema：默认学期与默认节次同时就位
    final semesters = await db.query('semesters');
    expect(semesters.length, 1);
    expect(await tableExists(db, 'chat_sessions'), isFalse);
    expect(await tableExists(db, 'operation_log'), isFalse);
    await db.close();
  });

  test('极早期老库（v1，从未有这两张表）升 6：不报错、其它表补建完整', () async {
    final v1 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          // v1 只有这四张业务表，没有 app_settings、没有 notes、没有待删表
          await db.execute('''
            CREATE TABLE semesters (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              startDate TEXT NOT NULL,
              totalWeeks INTEGER NOT NULL DEFAULT 20,
              isCurrent INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE time_slots (
              section INTEGER PRIMARY KEY,
              startTime TEXT NOT NULL,
              endTime TEXT NOT NULL
            )
          ''');
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
              examDate INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE course_overrides (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              courseId INTEGER NOT NULL,
              originalWeek INTEGER NOT NULL,
              targetWeek INTEGER NOT NULL,
              targetDayOfWeek INTEGER,
              targetStartSection INTEGER,
              targetEndSection INTEGER,
              targetClassroom TEXT
            )
          ''');
        },
      ),
    );
    await v1.insert('semesters', {
      'name': '老学期',
      'startDate': '2025-09-01',
      'totalWeeks': 18,
      'isCurrent': 1,
    });
    await v1.close();

    // 1 → 6 走完整升级链：<2 补 app_settings、<3 补 notes、<5 补列、<6 删表清键。
    // 待删表从未存在过，DROP IF EXISTS 保证这里不会抛「no such table」。
    final db = await openAt(6);
    expect(await tableExists(db, 'app_settings'), isTrue);
    expect(await tableExists(db, 'notes'), isTrue);
    expect(await tableExists(db, 'chat_sessions'), isFalse);
    expect(await tableExists(db, 'operation_log'), isFalse);
    final semesters = await db.query('semesters');
    expect(semesters.single['name'], '老学期');
    await db.close();
  });

  test('清理只跑一次：升到 6 之后再过一次启动，不会重复删', () async {
    final legacyDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, v) => createLegacy212Schema(db),
      ),
    );
    await seedLegacyData(legacyDb);
    await legacyDb.close();

    final upgraded = await openAt(6);
    await upgraded.close();

    // 模拟「升级完成后用户又恢复了一份带遗留键的旧备份」：这些键会落库，
    // 但它们不会再被启动流程删掉——迁移只在 oldVersion < 6 时执行一次。
    final reopened = await openAt(6);
    await reopened.insert('app_settings', {
      'key': 'ai_api_key',
      'value': 'restored-from-old-backup',
    });
    await reopened.close();

    final db = await openAt(6);
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['ai_api_key'],
    );
    expect(rows.length, 1, reason: '清理是升版一次性动作，不能每次启动都跑');
    await db.close();
  });
}
