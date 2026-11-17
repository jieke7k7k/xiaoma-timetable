import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/pages/today_view_page.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

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
    todayViewNow = () => DateTime.now();
    await db.close();
  });

  test('WB_SPEC_238 §4：当日课程过滤、调课生效与正在上课/已上完/未开始三态', () {
    // 锁定时间为周二 10:00（第 1–2 节已上完，第 3–4 节 09:40-11:10 正在上课，下午第 6–7 节未开始）
    final now = DateTime(2026, 11, 17, 10, 0);
    final courses = [
      Course(
        id: 1,
        semesterId: 1,
        name: '药物化学',
        classroom: '16-102',
        teacher: '林老师',
        colorValue: 0xFF6B8E7B,
        dayOfWeek: 2,
        startSection: 1,
        endSection: 2,
        weeks: [1, 2, 3],
      ),
      Course(
        id: 2,
        semesterId: 1,
        name: '药剂学',
        classroom: '16-204',
        teacher: '陈老师',
        colorValue: 0xFF7E9BB5,
        dayOfWeek: 2,
        startSection: 3,
        endSection: 4,
        weeks: [1, 2, 3],
      ),
      Course(
        id: 3,
        semesterId: 1,
        name: '药理学实验',
        classroom: '实验楼301',
        colorValue: 0xFF8A9A7A,
        dayOfWeek: 2,
        startSection: 6,
        endSection: 7,
        weeks: [1, 2, 3],
      ),
      // 周三的课，默认不在周二显示，但通过 CourseOverride 调入周二第 10-11 节
      Course(
        id: 4,
        semesterId: 1,
        name: '药事管理学',
        classroom: '12-401',
        colorValue: 0xFFD8A47F,
        dayOfWeek: 3,
        startSection: 1,
        endSection: 2,
        weeks: [1, 2, 3],
      ),
    ];

    final overrides = [
      CourseOverride(
        id: 10,
        courseId: 4,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 2,
        targetStartSection: 10,
        targetEndSection: 11,
        targetClassroom: '阶梯202',
      ),
    ];

    final items = buildTodayItems(
      allCourses: courses,
      overrides: overrides,
      slots: defaultTimeSlots,
      currentWeek: 1,
      todayWeekday: 2,
      now: now,
    );

    expect(items.length, 4);
    expect(items[0].course.name, '药物化学');
    expect(items[0].status, TodayCourseStatus.finished);

    expect(items[1].course.name, '药剂学');
    expect(items[1].status, TodayCourseStatus.ongoing);

    expect(items[2].course.name, '药理学实验');
    expect(items[2].status, TodayCourseStatus.upcoming);

    expect(items[3].course.name, '药事管理学');
    expect(items[3].effectiveClassroom, '阶梯202');
    expect(items[3].status, TodayCourseStatus.upcoming);
  });

  /// 反复「真实等待 + 推进假时钟」直到目标出现：provider 首帧是真实异步
  /// 读库，单次 pump 拿不到数据。runAsync 里的真实等待让 FFI 操作跑完
  /// 并释放 sqflite 锁警告定时器（见 home_shell_test 头注释）。
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int rounds = 25,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    fail('pumpUntil 超时：$finder 未出现');
  }

  testWidgets('WB_SPEC_238 §2 & §3：底栏三键（今日/课表/我的）与今日视图空状态渲染', (tester) async {
    HomeShellTab selected = HomeShellTab.schedule;
    // 首帧放进 runAsync 里让真实的 FFI 数据库操作跑完（否则 sqflite 的
    // 锁警告定时器会挂在假时钟上导致「Timer is still pending」，
    // 见 home_shell_test 头注释）。
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TodayViewPage(
                onNavigateToSchedule: () => selected = HomeShellTab.schedule,
              ),
              bottomNavigationBar: StatefulBuilder(
                builder: (ctx, setStateBar) => HomeTabBar(
                  activeTab: selected,
                  onSelectTab: (t) => setStateBar(() => selected = t),
                  onTapSchedule: () =>
                      setStateBar(() => selected = HomeShellTab.schedule),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    await tester.pump();
    await pumpUntil(tester, find.text('今天没有课程安排'));

    // 底栏三键文案断言
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('设置'), findsNothing);

    // 空状态断言
    expect(find.text('今天没有课程安排'), findsOneWidget);
  });
}
