import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/widgets/course_detail_sheet.dart';

/// WB_SPEC_232 第 2 节 + WB_SPEC_256 §6.1：详情页入口（删除右上角 + 底部双键）
///
/// 覆盖规格第 9 节第 4 组验收：360dp 底部双键不溢出、删除 48×48、
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
    // 测试面默认是 800×600 逻辑（DPR 3.0 → 物理 2400×1800）：modal 弹层只给
    // 约一半屏高（约 305），装不下 314 高的详情内容，会溢出 8.5px。
    // 真机屏都比这高，这里统一按手机屏（360×800）测。
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
              builder: (context) => ElevatedButton(
                onPressed: () => CourseDetailSheet.show(context, course),
                child: const Text('OPEN_SHEET'),
              ),
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
    // WB_SPEC_256 §6.1：详情弹层按真实用法以 BottomSheet 形态打开（不再直接当
    // 首页 body 拼），这样删除流程里的「先关弹层再弹确认」走的是真实 pop，
    // parentContext 落在 Scaffold 内，确认后的 SnackBar 才有地方落。
    await tester.tap(find.text('OPEN_SHEET'));
    await drain(tester);
  }

  testWidgets('360dp 底部双键一行，删除在右上角', (tester) async {
    await pumpSheet(tester);

    // WB_SPEC_256 §6.1：删除移出底部行，改为标题行右上角 error 色 IconButton；
    // 底部只剩双键（新增时段 | 编辑）
    expect(find.byTooltip('删除课程'), findsOneWidget);
    expect(find.text('删除'), findsNothing);
    expect(find.text('新增时段'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('新增本课其他时段'), findsNothing);

    // 删除按钮 48×48 命中区（IconButton 默认 padded，不写显式约束）
    expect(
      tester.getSize(find.byTooltip('删除课程')),
      const Size(48, 48),
      reason: '删除 IconButton 应为 48×48dp 命中区',
    );

    // 底部双键同级：两个按钮垂直中心一致（同一行），统一 48dp 高
    final addY =
        tester.getCenter(find.widgetWithText(OutlinedButton, '新增时段')).dy;
    final editY =
        tester.getCenter(find.widgetWithText(FilledButton, '编辑')).dy;
    expect(addY, editY);
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, '新增时段')).height,
      48,
      reason: '新增时段应为 48dp 高',
    );
    expect(
      tester.getSize(find.widgetWithText(FilledButton, '编辑')).height,
      48,
      reason: '编辑应为 48dp 高',
    );

    // 顺序：新增时段在左、编辑在右（flex 4:5 的布局结果）
    final addX =
        tester.getCenter(find.widgetWithText(OutlinedButton, '新增时段')).dx;
    final editX =
        tester.getCenter(find.widgetWithText(FilledButton, '编辑')).dx;
    expect(addX, lessThan(editX));

    // 删除在标题行（高于底部双键）
    final delY = tester.getCenter(find.byTooltip('删除课程')).dy;
    expect(delY, lessThan(addY));

    // 360dp 下不溢出
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除仍弹确认框；取消不删', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byTooltip('删除课程'));
    await drain(tester);
    // 230 定版的破坏性确认框（256 起先关弹层再弹确认）
    expect(find.text('删除课程'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await drain(tester, rounds: 2);
    final left = await tester.runAsync(() => Dao.instance.getCoursesBySemester(1));
    expect(left!.length, 1, reason: '取消后课程必须还在');
  });

  testWidgets('确认删除后课程真的被删掉', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byTooltip('删除课程'));
    await drain(tester);
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

  testWidgets('1.15 倍系统字体下底部双键仍在一行、不折行', (tester) async {
    await pumpSheet(tester, textScale: 1.15);

    expect(tester.takeException(), isNull);
    final addY =
        tester.getCenter(find.widgetWithText(OutlinedButton, '新增时段')).dy;
    final editY =
        tester.getCenter(find.widgetWithText(FilledButton, '编辑')).dy;
    expect(addY, editY);
    // 新增时段仍是单行（maxLines 1 + 省略号兜底，不折行）
    expect(
      tester.getSize(find.text('新增时段')).height,
      lessThan(tester.getSize(find.widgetWithText(OutlinedButton, '新增时段')).height),
    );
  });
}
