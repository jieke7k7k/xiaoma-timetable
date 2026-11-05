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
}
