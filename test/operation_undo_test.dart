import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/services/command_executor.dart';
import 'package:xiaoma_timetable/services/operation_log_service.dart';

/// 撤回操作往返测试（2.0.5 第 4 节）
///
/// 执行（带来源 → 落操作记录）→ 撤回（按快照还原）的完整链路，
/// 覆盖规格点名的三类：add_course（撤回后课消失）、delete_note（撤回后备注回来）、
/// set_course_remark（撤回后备注恢复旧值）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late CommandExecutor ex;
  late int semesterId;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    ex = CommandExecutor();
    semesterId = (await Dao.instance.getCurrentSemester())!.id!;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> undoFirst() async {
    final logs = await OperationLogService.instance.list();
    expect(logs, isNotEmpty);
    final error = await OperationLogService.instance.undo(logs.first);
    expect(error, isNull, reason: '撤回失败：$error');
  }

  test('add_course：撤回后课程消失', () async {
    final r = await ex.execute({
      'type': 'add_course',
      'name': '高等数学',
      'dayOfWeek': 1,
      'startSection': 1,
      'endSection': 2,
      'weeks': '1-8',
    }, source: CommandSource.ai);
    expect(r.success, isTrue);
    expect(await Dao.instance.getCoursesBySemester(semesterId), hasLength(1));

    await undoFirst();
    expect(await Dao.instance.getCoursesBySemester(semesterId), isEmpty);
  });

  test('delete_note：撤回后备注回来（含原 id 与内容）', () async {
    final noteId = await Dao.instance.insertNote(Note(
      date: '2026-10-22',
      content: '交作业',
      createdAt: 1,
    ));

    final r = await ex.execute({
      'type': 'delete_note',
      'id': noteId,
    }, source: CommandSource.ai);
    expect(r.success, isTrue);
    expect(await Dao.instance.getAllNotes(), isEmpty);

    await undoFirst();
    final notes = await Dao.instance.getAllNotes();
    expect(notes, hasLength(1));
    expect(notes.single.id, noteId);
    expect(notes.single.date, '2026-10-22');
    expect(notes.single.content, '交作业');
  });

  test('set_course_remark：撤回后备注恢复旧值', () async {
    final id = await Dao.instance.insertCourse(Course(
      semesterId: semesterId,
      name: '药理学实验',
      colorValue: 0xFF6B8E7B,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: const [1, 2, 3],
      note: '旧备注',
    ));

    final r = await ex.execute({
      'type': 'set_course_remark',
      'courseId': id,
      'remark': '二楼',
    }, source: CommandSource.ai);
    expect(r.success, isTrue);
    expect((await Dao.instance.getCoursesBySemester(semesterId)).single.note, '二楼');

    await undoFirst();
    expect((await Dao.instance.getCoursesBySemester(semesterId)).single.note, '旧备注');
  });

  test('撤回后再查记录已被标记为已撤回，且不产生新可撤回记录', () async {
    await ex.execute({
      'type': 'add_course',
      'name': '大学英语',
      'dayOfWeek': 2,
      'startSection': 3,
      'endSection': 4,
      'weeks': '1-16',
    }, source: CommandSource.ai);

    final before = await OperationLogService.instance.list();
    expect(before, hasLength(1));
    await OperationLogService.instance.undo(before.first);

    final after = await OperationLogService.instance.list();
    expect(after, hasLength(1)); // 撤回本身不新增记录
    expect(after.single.undone, isTrue);
  });
}
