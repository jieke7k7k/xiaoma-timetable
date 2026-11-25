import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';

/// 课程 DAO 独立测试（WB_SPEC_264 T15）：
/// 覆盖 Course CRUD、id 为空校验、删除级联清理调课记录、批量导入覆盖事务原子性。
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

  Course sampleCourse({
    int? id,
    int semesterId = 1,
    String name = '药理学',
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 2,
  }) =>
      Course(
        id: id,
        semesterId: semesterId,
        name: name,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        weeks: const [1, 2, 3, 4],
      );

  group('Course CRUD 与排序', () {
    test('insertCourse / getCoursesBySemester 按 id ASC 稳定返回', () async {
      // M4（DeepSeek 264 复审 B 段）：按自增顺序插，rowid 顺序与 id 顺序恒一致，
      // 咬不住 ORDER BY；改让 id 顺序与 (semesterId, dayOfWeek) 索引顺序相反——
      // 先插周五的课（id 小），再插周一的课（id 大），无 ORDER BY 时索引扫描会先返回周一的课
      final id1 = await Dao.instance.insertCourse(
        sampleCourse(name: '课程A', dayOfWeek: 5),
      );
      final id2 = await Dao.instance.insertCourse(
        sampleCourse(name: '课程B', dayOfWeek: 1),
      );
      final list = await Dao.instance.getCoursesBySemester(1);
      expect(list.map((c) => c.id), [id1, id2]);
    });

    test('updateCourse 缺少 id 时抛 ArgumentError（C15）', () async {
      await expectLater(
        Dao.instance.updateCourse(sampleCourse(id: null)),
        throwsArgumentError,
      );
    });

    test('deleteCourse 事务内级联清理关联 course_overrides', () async {
      final cid = await Dao.instance.insertCourse(sampleCourse());
      await Dao.instance.upsertOverride(
        CourseOverride(courseId: cid, originalWeek: 1, targetWeek: -1),
      );
      await Dao.instance.deleteCourse(cid);
      expect(await Dao.instance.getCoursesBySemester(1), isEmpty);
      expect(await Dao.instance.getOverridesBySemester(1), isEmpty);
    });
  });

  group('批量导入覆盖事务', () {
    test('runInTransaction 内中途抛错整体回滚（旧课不丢、新课不残留）', () async {
      final oldId = await Dao.instance.insertCourse(sampleCourse(name: '旧课'));
      await expectLater(
        Dao.instance.runInTransaction((txn) async {
          await Dao.instance.deleteCourse(oldId, txn: txn);
          await Dao.instance.insertCourse(
            sampleCourse(name: '新课'),
            txn: txn,
          );
          throw StateError('模拟导入中途失败');
        }),
        throwsStateError,
      );
      final list = await Dao.instance.getCoursesBySemester(1);
      expect(list.map((c) => c.name), ['旧课']);
    });
  });
}
