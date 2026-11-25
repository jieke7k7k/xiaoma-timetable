import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';

/// 单次调课 DAO 独立测试（WB_SPEC_264 T15）：
/// 覆盖 upsertOverride 同周覆盖幂等性、按学期联表过滤、deleteOverride、
/// 以及 deleteSemester 批量子查询级联清理（C20）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    // 注意：这里直接开内存库，onConfigure 的 PRAGMA 只是复刻生产
    // DbHelper._open 的同一行（db_helper.dart:147）；生产开关本身是否生效，
    // 由 db_migration_217_test（走 openAt 生产路径）断言 PRAGMA foreign_keys == 1。
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedCourse({int semesterId = 1, String name = '药剂学'}) =>
      Dao.instance.insertCourse(
        Course(
          semesterId: semesterId,
          name: name,
          colorValue: 0xFF7E9BB5,
          dayOfWeek: 2,
          startSection: 3,
          endSection: 4,
          weeks: const [1, 2, 3, 4],
        ),
      );

  group('CourseOverride CRUD 与学期隔离', () {
    test('upsertOverride 同 (courseId, originalWeek) 重复写入仅留最新一条', () async {
      final cid = await seedCourse();
      await Dao.instance.upsertOverride(
        CourseOverride(
          courseId: cid,
          originalWeek: 2,
          targetWeek: 2,
          targetDayOfWeek: 3,
          targetStartSection: 5,
          targetEndSection: 6,
          targetClassroom: 'A101',
        ),
      );
      await Dao.instance.upsertOverride(
        CourseOverride(
          courseId: cid,
          originalWeek: 2,
          targetWeek: CourseOverride.cancelFlag,
        ),
      );
      final list = await Dao.instance.getOverridesBySemester(1);
      expect(list.length, 1);
      expect(list.first.isCancellation, isTrue);
    });

    test('getOverridesBySemester 仅返回目标学期的调课记录', () async {
      final sem2 = await Dao.instance.insertSemester(
        const Semester(name: '第二学期', startDate: '2027-03-01'),
      );
      final c1 = await seedCourse(semesterId: 1);
      final c2 = await seedCourse(semesterId: sem2);
      await Dao.instance.upsertOverride(
        CourseOverride(courseId: c1, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      );
      await Dao.instance.upsertOverride(
        CourseOverride(courseId: c2, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      );
      final list = await Dao.instance.getOverridesBySemester(sem2);
      expect(list.map((o) => o.courseId), [c2]);
    });

    test('deleteOverride 精准撤销单条调课记录', () async {
      final cid = await seedCourse();
      final id1 = await Dao.instance.upsertOverride(
        CourseOverride(courseId: cid, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      );
      await Dao.instance.upsertOverride(
        CourseOverride(courseId: cid, originalWeek: 2, targetWeek: CourseOverride.cancelFlag),
      );
      await Dao.instance.deleteOverride(id1);
      final list = await Dao.instance.getOverridesBySemester(1);
      expect(list.length, 1);
      expect(list.first.originalWeek, 2);
    });

    test('deleteSemester 批量子查询清理该学期全部课程与调课记录（C20）', () async {
      final sem2 = await Dao.instance.insertSemester(
        const Semester(name: '第二学期', startDate: '2027-03-01'),
      );
      final c1 = await seedCourse(semesterId: 1);
      final c2 = await seedCourse(semesterId: sem2);
      await Dao.instance.upsertOverride(
        CourseOverride(courseId: c1, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      );
      await Dao.instance.upsertOverride(
        CourseOverride(courseId: c2, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      );
      await Dao.instance.deleteSemester(sem2);
      expect(await Dao.instance.getCoursesBySemester(sem2), isEmpty);
      expect(await Dao.instance.getOverridesBySemester(sem2), isEmpty);
      // 当前学期不受影响
      expect((await Dao.instance.getCoursesBySemester(1)).length, 1);
      expect((await Dao.instance.getOverridesBySemester(1)).length, 1);
    });
  });
}
