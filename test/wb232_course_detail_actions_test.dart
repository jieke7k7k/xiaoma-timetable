import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/widgets/course_detail_sheet.dart';

/// WB_SPEC_232 第 2 节：详情页三个入口同级排列（删除 | 新增时段 | 编辑）
///
/// 覆盖规格第 9 节第 4 组验收：360dp 一行三个不溢出、
/// 删除仍弹确认框且取消不删、新增/编辑的跳转与预填与改前一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  Object? pushedArgs;
  String? pushedName;
  late int courseId;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    pushedArgs = null;
    pushedName = null;
    courseId = await Dao.instance.insertCourse(Course(
      semesterId: 1,
      name: '药理学',
      teacher: '张老师',
      classroom: '302',
      colorValue: 0xFF8FA3B0,
      dayOfWeek: 2,
      startSection: 1,
      endSection: 2,
      weeks: const [1, 2, 3, 4],
    ));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpSheet(WidgetTester tester, {double textScale = 1.0}) async {
    final course = (await tester.runAsync(
      () => Dao.instance.getCoursesBySemester(1),
    ))!
        .first;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => CourseDetailSheet(course: course),
            ),
          ),
          routes: {
            '/course-edit': (context) {
              pushedName = '/course-edit';
              pushedArgs = ModalRoute.of(context)?.settings.arguments;
              return const Scaffold(body: Text('EDIT_PAGE'));
            },
          },
        ),
      ),
    );
    await drain(tester);
  }

  testWidgets('360dp 一行装下三个按钮，文案与层级正确', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpSheet(tester);

    // 三个入口都在，旧的「新增本课其他时段」全宽按钮已删
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('新增时段'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('新增本课其他时段'), findsNothing);

    // 同级：三个按钮垂直中心一致（同一行）
    final delY = tester.getCenter(find.widgetWithText(TextButton, '删除')).dy;
    final addY = tester.getCenter(find.widgetWithText(TextButton, '新增时段')).dy;
    final editY = tester.getCenter(find.widgetWithText(TextButton, '编辑')).dy;
    expect(delY, addY);
    expect(addY, editY);

    // 统一 44dp 高
    for (final label in ['删除', '新增时段', '编辑']) {
      expect(tester.getSize(find.widgetWithText(TextButton, label)).height, 44,
          reason: '$label 应统一 44dp 高');
    }

    // 顺序：删除在最左、编辑在最右（flex 3:4:4 的布局结果）
    final delX = tester.getCenter(find.widgetWithText(TextButton, '删除')).dx;
    final addX = tester.getCenter(find.widgetWithText(TextButton, '新增时段')).dx;
    final editX = tester.getCenter(find.widgetWithText(TextButton, '编辑')).dx;
    expect(delX, lessThan(addX));
    expect(addX, lessThan(editX));

    // 360dp 下不溢出（改前中间四字会被挤出省略号/折行）
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除仍弹确认框；取消不删', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 230 定版的破坏性确认框
    expect(find.text('删除课程'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await drain(tester, rounds: 2);
    final left = await tester.runAsync(() => Dao.instance.getCoursesBySemester(1));
    expect(left!.length, 1, reason: '取消后课程必须还在');
  });

  testWidgets('确认删除后课程真的被删掉', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await drain(tester, rounds: 8);
    final left = await tester.runAsync(() => Dao.instance.getCoursesBySemester(1));
    expect(left, isEmpty);
    // 删课会触发通知链/小组件刷新（fire-and-forget）+ 10 秒锁警告定时器，
    // 抽干并销毁树，避免 teardown 报「Timer is still pending」
    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester, rounds: 4);
  });

  testWidgets('新增时段：跳转 /course-edit 并预填名称/老师/颜色', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('新增时段'));
    await drain(tester, rounds: 2);

    expect(pushedName, '/course-edit');
    expect(pushedArgs, isA<Map>());
    final args = pushedArgs as Map;
    expect(args['name'], '药理学');
    expect(args['teacher'], '张老师');
    expect(args['colorValue'], 0xFF8FA3B0);
  });

  testWidgets('编辑：跳转 /course-edit 并带上课程 id', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('编辑'));
    await drain(tester, rounds: 2);

    expect(pushedName, '/course-edit');
    expect(pushedArgs, courseId);
  });

  testWidgets('1.15 倍系统字体下三个按钮仍在一行、不折行', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpSheet(tester, textScale: 1.15);

    expect(tester.takeException(), isNull);
    final delY = tester.getCenter(find.widgetWithText(TextButton, '删除')).dy;
    final addY = tester.getCenter(find.widgetWithText(TextButton, '新增时段')).dy;
    final editY = tester.getCenter(find.widgetWithText(TextButton, '编辑')).dy;
    expect(delY, addY);
    expect(addY, editY);
    // 中间四字仍是单行（maxLines 1 + 省略号兜底，不折行）
    expect(
      tester.getSize(find.text('新增时段')).height,
      lessThan(tester.getSize(find.widgetWithText(TextButton, '新增时段')).height),
    );
  });
}
