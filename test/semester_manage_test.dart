import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/week_calc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 学期管理与切换联动测试
///
/// 使用 sqflite_common_ffi 的内存库跑真实 SQL（与生产同一套 createSchema），
/// 验证：切换事务保证 isCurrent 唯一、coursesProvider/todayWeekProvider 联动刷新、
/// 级联删除、不允许删除当前激活学期。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late ProviderContainer container;

  setUp(() async {
    // 每个用例一个全新的内存库，互不干扰
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Course _course({
    required int semesterId,
    String name = '课程',
    List<int> weeks = const [1, 2],
  }) =>
      Course(
        semesterId: semesterId,
        name: name,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        weeks: weeks,
      );

  group('首启默认数据', () {
    test('createSchema 内置一个 isCurrent=1 的默认学期', () async {
      final current = await Dao.instance.getCurrentSemester();
      expect(current, isNotNull);
      expect(current!.isCurrent, isTrue);
    });
  });

  group('切换激活学期', () {
    test('事务后全局有且仅有一个 isCurrent=1', () async {
      final secondId = await Dao.instance
          .insertSemester(const Semester(name: '下学期', startDate: '2027-03-01'));

      await Dao.instance.setCurrentSemester(secondId);

      final all = await Dao.instance.getAllSemesters();
      expect(all.where((s) => s.isCurrent).length, 1);
      expect(all.firstWhere((s) => s.isCurrent).id, secondId);
    });

    test('switchTo 后 coursesProvider / todayWeekProvider 联动刷新', () async {
      final first = (await Dao.instance.getCurrentSemester())!;
      final secondId = await Dao.instance.insertSemester(
          const Semester(name: '下学期', startDate: '2027-03-01', totalWeeks: 18));
      await Dao.instance.insertCourse(_course(semesterId: secondId, name: '新学期课'));

      // 初始状态：读到的是第一学期的课程（默认学期无课程）
      expect(await container.read(coursesProvider.future), isEmpty);

      await container.read(semestersProvider.notifier).switchTo(secondId);

      // 课程列表联动为新学期的课程
      final courses = await container.read(coursesProvider.future);
      expect(courses.length, 1);
      expect(courses.first.name, '新学期课');
      expect(courses.first.semesterId, secondId);

      // 当前学期对象联动
      final current = container.read(currentSemesterProvider).value;
      expect(current?.id, secondId);
      expect(current?.totalWeeks, 18);

      // todayWeekProvider 联动：2027-03-01 未开学 → 0
      expect(container.read(todayWeekProvider), 0);

      // 学期列表的 isCurrent 标记同步刷新
      final semesters = container.read(semestersProvider).value!;
      expect(semesters.firstWhere((s) => s.id == secondId).isCurrent, isTrue);
      expect(
          semesters.firstWhere((s) => s.id == first.id).isCurrent, isFalse);
    });

    test('switchTo 后浏览周重置（displayWeekProvider 回到新学期本周）', () async {
      final secondId = await Dao.instance
          .insertSemester(const Semester(name: '下学期', startDate: '2027-03-01'));
      container.read(displayWeekProvider.notifier).setWeek(5);

      await container.read(semestersProvider.notifier).switchTo(secondId);

      // 新学期 2027-03-01 未开学 → todayWeek=0 → 浏览周重置为 1
      expect(container.read(displayWeekProvider), 1);
    });
  });

  group('删除学期', () {
    test('级联删除该学期下的课程与调课记录', () async {
      final secondId = await Dao.instance
          .insertSemester(const Semester(name: '旧学期', startDate: '2025-03-03'));
      final courseId = await Dao.instance
          .insertCourse(_course(semesterId: secondId, name: '要被级联删除的课'));
      await Dao.instance.upsertOverride(CourseOverride(
        courseId: courseId,
        originalWeek: 3,
        targetWeek: -1,
      ));

      await Dao.instance.deleteSemester(secondId);

      final overrides =
          await Dao.instance.getOverridesBySemester(secondId);
      expect(overrides.where((o) => o.courseId == courseId), isEmpty);
      final remaining = await Dao.instance.getAllSemesters();
      expect(remaining.any((s) => s.id == secondId), isFalse);
    });

    test('不允许删除当前激活学期（DAO 层由 UI/Notifier 拦截，这里验证 Notifier 兜底）',
        () async {
      final current = (await Dao.instance.getCurrentSemester())!;
      expect(
        () => container
            .read(semestersProvider.notifier)
            .deleteSemester(current.id!),
        throwsA(isA<Exception>()),
      );
      // 确认没有真的删掉
      expect(await Dao.instance.getCurrentSemester(), isNotNull);
    });

    test('删除非当前学期成功且列表刷新', () async {
      final secondId = await Dao.instance
          .insertSemester(const Semester(name: '旧学期', startDate: '2025-03-03'));
      await Dao.instance.insertCourse(_course(semesterId: secondId));

      await container.read(semestersProvider.notifier).deleteSemester(secondId);

      final semesters = await container.read(semestersProvider.future);
      expect(semesters.any((s) => s.id == secondId), isFalse);
      // 当前学期未受影响
      expect((await Dao.instance.getCurrentSemester())!.id, isNot(secondId));
    });
  });

  group('编辑学期', () {
    test('编辑当前学期后内存同步：周次与浏览周立即按新日期/新总周数工作', () async {
      final current = (await Dao.instance.getCurrentSemester())!;
      // 页面里由 watch 保证已加载，测试里显式等它就绪
      await container.read(currentSemesterProvider.future);
      // 浏览周定在第 20 周（原总周数 20 的上限），改小总周数后必须被钳回来
      container.read(displayWeekProvider.notifier).setWeek(20);

      // 开学日期改成「本周周一」→ 今天恒为第 1 周（与运行日期无关）
      final monday = DateFormat('yyyy-MM-dd')
          .format(WeekCalc.alignToMonday(DateTime.now()));
      await container
          .read(semestersProvider.notifier)
          .updateSemester(current.copyWith(
            name: '改名后的学期',
            startDate: monday,
            totalWeeks: 8,
          ));

      // 当前学期内存对象同步（todayWeekProvider / 周视图 / 提醒都读它）
      final now = container.read(currentSemesterProvider).value!;
      expect(now.id, current.id);
      expect(now.name, '改名后的学期');
      expect(now.startDate, monday);
      expect(now.totalWeeks, 8);

      // 下游联动：今天 = 第 1 周；浏览周从 20 被钳到 8（PageView 页码不越界）
      expect(container.read(todayWeekProvider), 1);
      expect(container.read(displayWeekProvider), 8);

      // 落库与列表也同步，且 isCurrent 仍然唯一
      final inDb = (await Dao.instance.getCurrentSemester())!;
      expect(inDb.name, '改名后的学期');
      expect(inDb.totalWeeks, 8);
      final list = await container.read(semestersProvider.future);
      expect(list.where((s) => s.isCurrent).length, 1);
      expect(list.firstWhere((s) => s.id == current.id).name, '改名后的学期');
    });

    test('编辑非当前学期：只改库与列表，当前学期状态不受影响', () async {
      final current = (await Dao.instance.getCurrentSemester())!;
      await container.read(currentSemesterProvider.future);
      final secondId = await Dao.instance.insertSemester(
          const Semester(name: '下学期', startDate: '2027-03-01', totalWeeks: 18));

      final target = (await Dao.instance.getAllSemesters())
          .firstWhere((s) => s.id == secondId);
      await container
          .read(semestersProvider.notifier)
          .updateSemester(target.copyWith(name: '下学期改名', totalWeeks: 16));

      // 目标学期已改
      final inDb = (await Dao.instance.getAllSemesters())
          .firstWhere((s) => s.id == secondId);
      expect(inDb.name, '下学期改名');
      expect(inDb.totalWeeks, 16);
      final list = await container.read(semestersProvider.future);
      expect(list.firstWhere((s) => s.id == secondId).totalWeeks, 16);

      // 当前学期与它的周次不受影响
      final now = container.read(currentSemesterProvider).value!;
      expect(now.id, current.id);
      expect(now.name, current.name);
      expect(now.totalWeeks, current.totalWeeks);
      expect(now.isCurrent, isTrue);
      expect(inDb.isCurrent, isFalse);
    });
  });
}
