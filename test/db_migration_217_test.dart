import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';

/// 2.1.7 数据库迁移测试（WB_SPEC_218 第 ③ 节）。
///
/// 2.1.7 把 Supabase 云同步整条线删除，升级路径新增 v6 → v7：一次性清掉
/// 两个云同步遗留设置键（`supabase_last_sync_at` / `supabase_last_sync_summary`）。
/// 用一个**文件库**模拟真实升级：先按 v6 打开并灌入「两个同步键 + 正常设置键」，
/// 再按 v7 重新打开触发 [DbHelper.upgradeSchema]，断言：
/// 1. 两个同步遗留键已删空；
/// 2. 其它设置键原样保留、业务数据（默认学期/节次）不丢；
/// 3. 清理只在「升到 7」那一次发生，之后再启动不会反复清。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late String dbPath;

  setUp(() {
    dbPath = p.join(
      Directory.systemTemp.path,
      'xiaoma_migration_217_${DateTime.now().microsecondsSinceEpoch}.db',
    );
  });

  tearDown(() async {
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {
      // 清理失败不影响断言结果
    }
  });

  /// 按 App 的方式打开：onCreate / onUpgrade 都指向 DbHelper 里的同一份实现；
  /// onConfigure 与生产 _open（db_helper.dart:147）同一行，外键开关
  /// 必须随库一起开——M3（DeepSeek 264 复审 B 段）断言的正是这条生产路径。
  Future<Database> openAt(int version) => databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) => DbHelper.instance.createSchema(db),
      onUpgrade: (db, from, to) =>
          DbHelper.instance.upgradeSchema(db, from, to),
    ),
  );

  test('2.1.6（v6）升 2.1.7（v7）：两个云同步键清空、其它设置与数据完好', () async {
    // 先按 v6 建库（createSchema 建的是当前 v7 表结构，v6/v7 表结构相同，
    // 差异只在 app_settings 的遗留键，故用 createSchema 建 v6 库是安全的），
    // 再手动种入两个云同步键 + 正常设置键
    final v6 = await openAt(6);
    await v6.insert('app_settings', {
      'key': 'supabase_last_sync_at',
      'value': '1750000000000',
    });
    await v6.insert('app_settings', {
      'key': 'supabase_last_sync_summary',
      'value': '{\"pushed\": 3}',
    });
    await v6.insert('app_settings', {'key': 'theme_mode', 'value': 'dark'});
    await v6.insert('app_settings', {'key': 'reminder_enabled', 'value': '1'});
    await v6.close();

    // 升级到 v7：触发 v6 -> v7 迁移
    final db = await openAt(7);

    // 1) 两个云同步遗留键已删空
    for (final key in DbHelper.retiredSyncKeys) {
      final rows = await db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      expect(rows, isEmpty, reason: '云同步遗留键「$key」应被 v7 迁移清掉');
    }

    // 2) 非同步设置键一个不少、值不变
    final byKey = {
      for (final r in await db.query('app_settings'))
        r['key'] as String: r['value'] as String,
    };
    expect(byKey['theme_mode'], 'dark');
    expect(byKey['reminder_enabled'], '1');

    // 3) 默认业务数据完好（createSchema 首启就位，升级不碰）
    final semesters = await db.query('semesters');
    expect(semesters.length, 1);
    final slots = await db.query('time_slots');
    expect(slots.length, greaterThanOrEqualTo(1));

    await db.close();
  });

  test('清理只在升到 v7 那一次发生：升级后重新种入的同步键不再被删', () async {
    final v6 = await openAt(6);
    await v6.insert('app_settings', {
      'key': 'supabase_last_sync_at',
      'value': '1750000000000',
    });
    await v6.close();

    // 第一次升到 v7：同步键被清掉
    final db = await openAt(7);
    expect(
      await db.query('app_settings', where: 'key = ?',
          whereArgs: ['supabase_last_sync_at']),
      isEmpty,
    );

    // 用户后来手动恢复了旧备份、把同步键又带回来：再启动（同版本 7）不触发
    // 迁移，键不会被反复清掉（与 2.1.3 v6 清理「只在升到 6 那一次」同一原则）
    await db.insert('app_settings', {
      'key': 'supabase_last_sync_at',
      'value': '999999999',
    });
    await db.close();
    final again = await openAt(7);
    final rows = await again.query('app_settings',
        where: 'key = ?', whereArgs: ['supabase_last_sync_at']);
    expect(rows, isNotEmpty, reason: '同版本重启不重复清理');
    expect(rows.single['value'], '999999999');
    await again.close();
  });

  test('早期 v1 库（无 app_settings / 无 notes / courses 无 v5 扩展列）跨级升至 v7', () async {
    // 构造真实 v1 schema（不含 app_settings、notes 与 v5 新增列）
    final v1 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
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
          await db.insert('semesters', {
            'name': '大一上学期',
            'startDate': '2024-09-02',
            'totalWeeks': 20,
            'isCurrent': 1,
          });
          await db.insert('courses', {
            'semesterId': 1,
            'name': '高等数学',
            'colorValue': 0xFF6B8E7B,
            'dayOfWeek': 1,
            'startSection': 1,
            'endSection': 2,
            'weeksJson': '[1,2,3]',
            'weekType': 0,
          });
        },
      ),
    );
    await v1.close();

    // 跨级升至 v7：依次补建 app_settings、notes、courses/notes v5 扩展列，不丢旧数据
    final db = await openAt(7);
    // M3（DeepSeek 264 复审 B 段）：外键开关必须走生产 DbHelper._open 的 onConfigure，
    // 不能只靠 DAO 测试自带的 PRAGMA；这里直接断言生产路径打开的库外键已开启
    final fk = await db.rawQuery('PRAGMA foreign_keys');
    expect(fk.single['foreign_keys'], 1);
    final tables = {
      for (final r in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
        r['name'] as String,
    };
    expect(tables, containsAll(['semesters', 'time_slots', 'courses', 'course_overrides', 'app_settings', 'notes']));

    final courseCols = {
      for (final r in await db.rawQuery('PRAGMA table_info(courses)'))
        r['name'] as String,
    };
    expect(courseCols, containsAll(['examEndTime', 'examPlace', 'updatedAt']));

    final noteCols = {
      for (final r in await db.rawQuery('PRAGMA table_info(notes)'))
        r['name'] as String,
    };
    expect(noteCols, contains('updatedAt'));

    // 历史课程数据完好且可正常写入新列与 notes 表
    final courses = await db.query('courses');
    expect(courses.length, 1);
    expect(courses.first['name'], '高等数学');
    await db.insert('notes', {
      'date': '2026-11-25',
      'content': '升级后新建备注',
      'createdAt': 1700000000000,
      'updatedAt': 1700000000000,
    });
    expect((await db.query('notes')).length, 1);
    await db.close();
  });

  test('v4 库（含已退役表与遗留键）升至 v7 后表清键净，且重复跑 v4→v7 幂等不报错', () async {
    final v4 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, v) async {
          await DbHelper.instance.createSchema(db);
          for (final table in DbHelper.retiredTables) {
            await db.execute('CREATE TABLE $table (id INTEGER PRIMARY KEY)');
          }
          for (final key in [...DbHelper.retiredSettingKeys, ...DbHelper.retiredSyncKeys]) {
            await db.insert('app_settings', {'key': key, 'value': 'legacy'});
          }
          await db.insert('app_settings', {'key': 'theme_mode', 'value': 'light'});
        },
      ),
    );
    await v4.close();

    // 升至 v7（createSchema 已含 v5 列，顺带验证 C1 的 PRAGMA table_info 防重加列）
    final db = await openAt(7);
    final tables = {
      for (final r in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
        r['name'] as String,
    };
    for (final retired in DbHelper.retiredTables) {
      expect(tables, isNot(contains(retired)));
    }
    final remainingKeys = {
      for (final r in await db.query('app_settings')) r['key'] as String,
    };
    for (final key in [...DbHelper.retiredSettingKeys, ...DbHelper.retiredSyncKeys]) {
      expect(remainingKeys, isNot(contains(key)));
    }
    expect(remainingKeys, contains('theme_mode'));
    // L9（DeepSeek 264 复审 B 段）：用例名里的「重复跑 v4→v7 幂等」要真跑第二次——
    // 直接重调同一段迁移，退役表不复活、保留键不丢、重复加列不报错
    await DbHelper.instance.upgradeSchema(db, 4, 7);
    final tablesAfterSecond = {
      for (final r in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
        r['name'] as String,
    };
    for (final retired in DbHelper.retiredTables) {
      expect(tablesAfterSecond, isNot(contains(retired)));
    }
    final keysAfterSecond = {
      for (final r in await db.query('app_settings')) r['key'] as String,
    };
    expect(keysAfterSecond, contains('theme_mode'));
    await db.close();
  });
}
