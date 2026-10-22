import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 备注 Dao 测试（真实 SQL，跑在 sqflite_common_ffi 内存库上）
///
/// 与 semester_manage_test 同一套路：每个用例一个全新内存库，
/// createSchema 与生产共用一套 SQL（含 v3 的 notes 表）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
  });

  tearDown(() async {
    await db.close();
  });

  Note note(
    String date,
    String content, {
    int? id,
    int createdAt = 1000,
  }) =>
      Note(id: id, date: date, content: content, createdAt: createdAt);

  group('增删查', () {
    test('新增后可按日期取回，字段往返一致', () async {
      final id = await Dao.instance.insertNote(note('2026-09-07', '带实验服'));

      final list = await Dao.instance.getNotesByDate('2026-09-07');
      expect(list.length, 1);
      expect(list.first.id, id);
      expect(list.first.date, '2026-09-07');
      expect(list.first.content, '带实验服');
      expect(list.first.createdAt, 1000);
    });

    test('同一天多条按写入顺序返回，不同日期互不干扰', () async {
      await Dao.instance.insertNote(note('2026-09-07', '第一条', createdAt: 1));
      await Dao.instance.insertNote(note('2026-09-07', '第二条', createdAt: 2));
      await Dao.instance.insertNote(note('2026-09-08', '明天的'));

      final today = await Dao.instance.getNotesByDate('2026-09-07');
      expect(today.map((n) => n.content).toList(), ['第一条', '第二条']);
      final tomorrow = await Dao.instance.getNotesByDate('2026-09-08');
      expect(tomorrow.map((n) => n.content).toList(), ['明天的']);
      // 没有备注的日期返回空列表
      expect(await Dao.instance.getNotesByDate('2026-09-09'), isEmpty);
    });

    test('查全部按日期升序（同日按写入顺序）', () async {
      await Dao.instance.insertNote(note('2026-09-10', '后写的'));
      await Dao.instance.insertNote(note('2026-09-08', '中间'));
      await Dao.instance.insertNote(note('2026-09-07', '最早的'));

      final all = await Dao.instance.getAllNotes();
      expect(all.map((n) => n.date).toList(),
          ['2026-09-07', '2026-09-08', '2026-09-10']);
    });

    test('编辑内容/日期后即时生效', () async {
      final id = await Dao.instance.insertNote(note('2026-09-07', '原始内容'));
      await Dao.instance.updateNote(
        note('2026-09-09', '改过的', id: id),
      );

      expect(await Dao.instance.getNotesByDate('2026-09-07'), isEmpty);
      final moved = await Dao.instance.getNotesByDate('2026-09-09');
      expect(moved.single.content, '改过的');
    });

    test('删除返回受影响行数，重复删除返回 0', () async {
      final id = await Dao.instance.insertNote(note('2026-09-07', '待删除'));

      expect(await Dao.instance.deleteNote(id), 1);
      expect(await Dao.instance.getNotesByDate('2026-09-07'), isEmpty);
      // 再删一次：没有这一行，返回 0 而不是抛异常
      expect(await Dao.instance.deleteNote(id), 0);
    });
  });

  group('批量按日期取（小组件用）', () {
    test('一次取多个日期，缺失的日期不报错', () async {
      await Dao.instance.insertNote(note('2026-09-07', '今天'));
      await Dao.instance.insertNote(note('2026-09-09', '后天'));
      await Dao.instance.insertNote(note('2026-10-01', '窗口外'));

      final list = await Dao.instance.getNotesByDates(
        ['2026-09-07', '2026-09-08', '2026-09-09'],
      );
      expect(list.map((n) => n.content).toList(), ['今天', '后天']);
    });

    test('空日期列表返回空结果，不会拼出非法 SQL', () async {
      expect(await Dao.instance.getNotesByDates([]), isEmpty);
    });
  });
}
