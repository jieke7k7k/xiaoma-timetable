import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/services/supabase_sync_service.dart';
import 'package:xiaoma_timetable/utils/supabase_codec.dart';

/// Supabase 云同步纯函数 + 服务离线兜底测试（WB_SPEC_211 第 5 节）。
///
/// 所有映射/冲突/水位/去重都是纯函数断言；「离线失败不丢本地数据」用注入的
/// fake CloudStore 抛异常模拟，**不真连 Supabase**，也不出现任何真实 URL/key
/// （URL/key 走 --dart-define，本文件只用占位对象）。

void main() {
  Course course({
    int? id,
    int semesterId = 3,
    String name = '药理学',
    int? examDate,
    String? examEndTime,
    String? examPlace,
  }) =>
      Course(
        id: id,
        semesterId: semesterId,
        name: name,
        teacher: '周老师',
        classroom: '教3-201',
        colorValue: 0xFF123456,
        dayOfWeek: 2,
        startSection: 3,
        endSection: 4,
        weeks: const [1, 3, 5],
        weekType: 1,
        note: '带实验服',
        examDate: examDate,
        examEndTime: examEndTime,
        examPlace: examPlace,
      );

  group('Course ↔ courses 行映射（含考试字段）', () {
    test('courseToRemoteRow：蛇形列名 + 远程 id + 考试字段', () {
      final row = courseToRemoteRow(
        course(
          id: 7,
          examDate: DateTime(2026, 11, 5, 9, 30).millisecondsSinceEpoch,
          examEndTime: '11:00',
          examPlace: '教学楼A101',
        ),
      );
      expect(row['id'], 'course:3:7');
      expect(row['semester_id'], 3);
      expect(row['name'], '药理学');
      expect(row['teacher'], '周老师');
      expect(row['classroom'], '教3-201');
      expect(row['color_value'], 0xFF123456);
      expect(row['day_of_week'], 2);
      expect(row['start_section'], 3);
      expect(row['end_section'], 4);
      expect(row['weeks_json'], '[1,3,5]');
      expect(row['week_type'], 1);
      expect(row['note'], '带实验服');
      expect(
        row['exam_date_ms'],
        DateTime(2026, 11, 5, 9, 30).millisecondsSinceEpoch,
      );
      expect(row['exam_end_time'], '11:00');
      expect(row['exam_place'], '教学楼A101');
    });

    test('courseFromRemoteRow：解析远程 id 还原 localId/semesterId 与考试字段', () {
      final c = courseFromRemoteRow({
        'id': 'course:3:7',
        'semester_id': 3,
        'name': '有机化学',
        'teacher': '李老师',
        'classroom': '实验楼402',
        'color_value': 0xFF654321,
        'day_of_week': 4,
        'start_section': 5,
        'end_section': 6,
        'weeks_json': '[2,4]',
        'week_type': 2,
        'note': '提前到',
        'exam_date_ms': 123456,
        'exam_end_time': '16:00',
        'exam_place': '实验楼402',
      })!;
      expect(c.id, 7);
      expect(c.semesterId, 3);
      expect(c.name, '有机化学');
      expect(c.weeks, [2, 4]);
      expect(c.examDate, 123456);
      expect(c.examEndTime, '16:00');
      expect(c.examPlace, '实验楼402');
    });

    test('courseFromRemoteRow：非法 id 返回 null', () {
      expect(courseFromRemoteRow({'id': 'bad'}), isNull);
      expect(courseFromRemoteRow({'id': 42}), isNull);
      expect(courseFromRemoteRow({'id': 'note:1'}), isNull);
    });
  });

  group('Note ↔ notes 行映射', () {
    test('noteToRemoteRow：远程 id + created_at_ms', () {
      final row = noteToRemoteRow(
        Note(id: 9, date: '2026-09-07', content: '带实验服', createdAt: 1000),
      );
      expect(row['id'], 'note:9');
      expect(row['date'], '2026-09-07');
      expect(row['content'], '带实验服');
      expect(row['created_at_ms'], 1000);
    });

    test('noteFromRemoteRow：解析远程 id 还原 localId', () {
      final n = noteFromRemoteRow({
        'id': 'note:9',
        'date': '2026-09-07',
        'content': '带实验服',
        'created_at_ms': 1000,
      })!;
      expect(n.id, 9);
      expect(n.date, '2026-09-07');
      expect(n.content, '带实验服');
      expect(n.createdAt, 1000);
    });

    test('noteFromRemoteRow：非法 id 返回 null', () {
      expect(noteFromRemoteRow({'id': 'x'}), isNull);
      expect(noteFromRemoteRow({'id': 'course:1:2'}), isNull);
    });
  });

  group('exams 镜像映射', () {
    test('有考试日期才生成镜像，字段与 id 对齐', () {
      final row = examMirrorRow(
        course(
          id: 5,
          semesterId: 2,
          examDate: DateTime(2026, 11, 5, 9, 30).millisecondsSinceEpoch,
          examEndTime: '11:00',
          examPlace: '教1-101',
        ),
      )!;
      expect(row['id'], 'exam:2:5');
      expect(row['course_remote_id'], 'course:2:5');
      expect(row['date'], '2026-11-05');
      expect(row['start_time'], '09:30');
      expect(row['end_time'], '11:00');
      expect(row['place'], '教1-101');
    });

    test('无考试日期返回 null（不生成镜像）', () {
      expect(examMirrorRow(course(id: 5)), isNull);
    });

    test('考试日期为纯日期（0 点）时 start_time 为 null', () {
      final row = examMirrorRow(
        course(id: 5, examDate: DateTime(2026, 11, 5).millisecondsSinceEpoch),
      )!;
      expect(row['date'], '2026-11-05');
      expect(row['start_time'], isNull);
    });
  });

  group('冲突取新', () {
    test('云端更新 → 云端赢', () {
      expect(resolveConflict(1000, 2000), SyncWinner.cloud);
    });
    test('本地更新 → 本地赢', () {
      expect(resolveConflict(2000, 1000), SyncWinner.local);
    });
    test('相等 → 不动', () {
      expect(resolveConflict(1000, 1000), SyncWinner.none);
    });
    test('本地旧数据（null）→ 云端赢', () {
      expect(resolveConflict(null, 1000), SyncWinner.cloud);
    });
    test('云端无时间 → 不动', () {
      expect(resolveConflict(1000, null), SyncWinner.none);
    });
  });

  group('水位过滤', () {
    test('早于/等于水位的云端行不下载（孤儿行天然跳过）', () {
      expect(cloudRowAfterWatermark(1000, 2000), isFalse);
      expect(cloudRowAfterWatermark(2000, 2000), isFalse);
      expect(cloudRowAfterWatermark(2001, 2000), isTrue);
      expect(cloudRowAfterWatermark(null, 2000), isFalse);
    });

    test('上传过滤：首次迁移全量，之后只传晚于水位的行', () {
      expect(shouldUpload(null, 0), isTrue); // 旧数据首次迁移也传
      expect(shouldUpload(1000, 0), isTrue);
      expect(shouldUpload(1000, 2000), isFalse);
      expect(shouldUpload(null, 2000), isFalse); // 旧数据首次之后不再传
      expect(shouldUpload(2001, 2000), isTrue);
    });
  });

  group('日期备注去重迁移', () {
    test('date+content 完全相同只留 createdAt 最早一条，其余进清单', () {
      final notes = [
        Note(id: 1, date: '2026-09-08', content: '药理学实验 二楼', createdAt: 3000),
        Note(id: 2, date: '2026-09-08', content: '药理学实验 二楼', createdAt: 1000),
        Note(id: 3, date: '2026-09-08', content: '别的', createdAt: 2000),
      ];
      final r = dedupeNotes(notes);
      expect(r.kept.map((n) => n.id).toSet(), {2, 3});
      expect(r.removed.length, 1);
      expect(r.removed.single, contains('药理学实验 二楼'));
      expect(r.removed.single, contains('id=1'));
    });

    test('不同内容不去重，同内容不同日期不去重', () {
      final notes = [
        Note(id: 1, date: '2026-09-08', content: '药理学实验 二楼', createdAt: 1),
        Note(id: 2, date: '2026-09-09', content: '药理学实验 二楼', createdAt: 2),
        Note(id: 3, date: '2026-09-08', content: '药理学实验 三楼', createdAt: 3),
      ];
      final r = dedupeNotes(notes);
      expect(r.kept.length, 3);
      expect(r.removed, isEmpty);
    });
  });

  group('P0-2 水位与上传时间统一用 started（mock 断言，不真连 Supabase）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    tearDown(() {
      SupabaseSyncService.instance.resetForTest();
    });

    test('上传 updated_at 与水位推进取同一同步开始时刻', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(db);

      await Dao.instance.insertCourse(course(id: null, name: '药理学'));
      await Dao.instance.insertNote(
        Note(date: '2026-09-07', content: '带实验服', createdAt: 1),
      );
      await Dao.instance.setSetting(SupabaseSyncService.lastSyncAtKey, '0');

      final store = _RecordingStore();
      SupabaseSyncService.instance.overrideStoreForTest(store);

      final outcome = await SupabaseSyncService.instance.syncNow();
      expect(outcome.status, SupabaseSyncStatus.completed);

      // 课程与备注上传的 updated_at 完全一致（同一个 started）
      expect(store.courseUpdatedAt, isNotNull);
      expect(store.noteUpdatedAt, store.courseUpdatedAt);
      expect(store.courseUpdatedAt, endsWith('Z')); // UTC ISO

      // 水位推进到 started 的毫秒值 == 上传 updated_at 解析出的毫秒值
      final watermark = await Dao.instance
          .getSettingInt(SupabaseSyncService.lastSyncAtKey, -1);
      final uploadMs = parseCloudUpdatedAt(store.courseUpdatedAt)!;
      expect((watermark - uploadMs).abs(), lessThan(2));

      await db.close();
    });
  });

  group('离线失败不丢本地数据（mock 断言，不真连 Supabase）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    tearDown(() {
      SupabaseSyncService.instance.resetForTest();
    });

    test('云端抛异常时返回 failed，本地课程/备注原样保留', () async {
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(db);

      // 本地先有 1 门课程 + 1 条备注
      await Dao.instance.insertCourse(course(id: null, name: '药理学'));
      await Dao.instance.insertNote(
        Note(date: '2026-09-07', content: '带实验服', createdAt: 1),
      );

      // 注入一个「网络不可用」的 fake store，模拟离线
      SupabaseSyncService.instance.overrideStoreForTest(_OfflineStore());
      // 水位归零（首次迁移），确保走上传路径
      await Dao.instance.setSetting(SupabaseSyncService.lastSyncAtKey, '0');

      final outcome = await SupabaseSyncService.instance.syncNow();

      expect(outcome.status, SupabaseSyncStatus.failed);
      expect(outcome.changed, isFalse);
      expect(outcome.summary, contains('同步失败'));

      // 本地数据一条不少、内容不变
      final courses = await Dao.instance.getAllCourses();
      final notes = await Dao.instance.getAllNotes();
      expect(courses.length, 1);
      expect(courses.single.name, '药理学');
      expect(notes.length, 1);
      expect(notes.single.content, '带实验服');

      await db.close();
    });
  });
}

/// 模拟离线：任何云端读写都抛异常（不真连 Supabase）。
class _OfflineStore implements CloudStore {
  @override
  Future<List<Map<String, dynamic>>> fetchCoursesAfter(int watermarkMs) async =>
      throw Exception('网络不可用');

  @override
  Future<List<Map<String, dynamic>>> fetchNotesAfter(int watermarkMs) async =>
      throw Exception('网络不可用');

  @override
  Future<void> upsertCourses(List<Map<String, dynamic>> rows) async =>
      throw Exception('网络不可用');

  @override
  Future<void> upsertNotes(List<Map<String, dynamic>> rows) async =>
      throw Exception('网络不可用');

  @override
  Future<void> upsertExams(List<Map<String, dynamic>> rows) async =>
      throw Exception('网络不可用');
}

/// 记录实际上传的 updated_at，用于断言「上传时间 = 水位」同源（不真连 Supabase）。
class _RecordingStore implements CloudStore {
  String? courseUpdatedAt;
  String? noteUpdatedAt;

  @override
  Future<List<Map<String, dynamic>>> fetchCoursesAfter(int watermarkMs) async =>
      [];

  @override
  Future<List<Map<String, dynamic>>> fetchNotesAfter(int watermarkMs) async =>
      [];

  @override
  Future<void> upsertCourses(List<Map<String, dynamic>> rows) async {
    if (rows.isNotEmpty) courseUpdatedAt = rows.first['updated_at'] as String?;
  }

  @override
  Future<void> upsertNotes(List<Map<String, dynamic>> rows) async {
    if (rows.isNotEmpty) noteUpdatedAt = rows.first['updated_at'] as String?;
  }

  @override
  Future<void> upsertExams(List<Map<String, dynamic>> rows) async {}
}
