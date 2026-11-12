import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/utils/morandi_palette.dart';

/// §12 第二批：颜色撞色提示（不弹窗）＋输入框文字垂直对齐。
///
/// 撞色提示覆盖：
/// - 被别的课占用的色块右下角带 4dp 小圆点（点前就看得见）；
/// - 点中被占用的色块，色块下方出现内联提示行，文案带占用课程名；
/// - 多门占用时文案是「等 N 门课程」；
/// - 同名时段（本课自己）不算占用，不出提示、没有小圆点；
/// - 提示不拦保存，点保存直接能存。
/// 对齐覆盖：三处单行输入框 textAlignVertical 都是 y:0.45（字沉回框正中央，
/// 不再跟浮起的标签撞在一起）；多行备注框保持默认（多行文本本来就贴顶排，
/// 不存在单行居中偏高的问题，不加）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  final colorA = MorandiPalette.colors[0];
  final colorB = MorandiPalette.colors[1];
  final colorC = MorandiPalette.colors[8];

  Course course({
    required String name,
    required int day,
    required int start,
    required int end,
    int? colorValue,
  }) {
    return Course(
      semesterId: 1,
      name: name,
      colorValue: colorValue ?? colorA,
      dayOfWeek: day,
      startSection: start,
      endSection: end,
      weeks: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
    );
  }

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
    Dao.debugBeforeUpdateCourse = null;
    await db.close();
  });

  Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  /// 打开编辑页：画布拉高到 2400（逻辑像素），ListView 只建可见子项，
  /// 画布不够高时色板行会被回收，断言就找不到小圆点了。
  Future<void> openEditor(WidgetTester tester, int courseId) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final navKey = GlobalKey<NavigatorState>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            home: const Scaffold(body: Text('HOME_PAGE')),
          ),
        ),
      );
    });
    await drain(tester, rounds: 2);
    await tester.runAsync(() async {
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => CourseEditPage(courseId: courseId),
        ),
      );
    });
    await drain(tester);
  }

  Future<void> tapColor(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(ValueKey('color-dot-$index')));
    await tester.pumpAndSettle();
  }

  /// 第 [index] 颗色块上有没有占用小圆点
  bool hasOccupiedDot(WidgetTester tester, int index) {
    return find
        .descendant(
          of: find.byKey(ValueKey('color-dot-$index')),
          matching: find.byKey(const ValueKey('color-occupied-dot')),
        )
        .evaluate()
        .isNotEmpty;
  }

  bool collisionHintVisible() =>
      find.textContaining('该颜色已用于').evaluate().isNotEmpty;

  testWidgets('被别的课占用的色块带小圆点，没被占用的没有', (tester) async {
    final pharma = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2, colorValue: colorA),
      ),
    );
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '高等数学', day: 3, start: 1, end: 2, colorValue: colorC),
      ),
    );
    await openEditor(tester, pharma!);

    expect(hasOccupiedDot(tester, 8), isTrue, reason: '第 8 颗是高等数学的颜色');
    expect(hasOccupiedDot(tester, 1), isFalse, reason: '第 1 颗没被任何课占用');
    expect(hasOccupiedDot(tester, 0), isFalse, reason: '本课自己的颜色不算占用');
    expect(collisionHintVisible(), isFalse, reason: '进页面还没改色，不出提示行');
  });

  testWidgets('点中被占用的色块：出现提示行，点空闲色块提示收起', (tester) async {
    final pharma = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2, colorValue: colorA),
      ),
    );
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '高等数学', day: 3, start: 1, end: 2, colorValue: colorC),
      ),
    );
    await openEditor(tester, pharma!);

    await tapColor(tester, 8);
    expect(collisionHintVisible(), isTrue);
    expect(find.text('该颜色已用于『高等数学』，仍可继续使用'), findsOneWidget);
    // 选中后小圆点藏起来（中央是对勾，占用信息由提示行说）
    expect(hasOccupiedDot(tester, 8), isFalse);

    await tapColor(tester, 1);
    expect(collisionHintVisible(), isFalse, reason: '点到空闲色块，提示自动收起');
    expect(hasOccupiedDot(tester, 8), isTrue, reason: '切走后小圆点回来');
  });

  testWidgets('多门占用：文案是「等 N 门课程」', (tester) async {
    final pharma = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2, colorValue: colorA),
      ),
    );
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '高等数学', day: 3, start: 1, end: 2, colorValue: colorC),
      ),
    );
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '大学英语', day: 4, start: 1, end: 2, colorValue: colorC),
      ),
    );
    await openEditor(tester, pharma!);

    await tapColor(tester, 8);
    expect(
      find.text('该颜色已用于『大学英语』等 2 门课程，仍可继续使用'),
      findsOneWidget,
    );
  });

  testWidgets('同名时段不算占用：兄弟的颜色没有小圆点、不出提示', (tester) async {
    final a = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2, colorValue: colorA),
      ),
    );
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 4, start: 3, end: 4, colorValue: colorB),
      ),
    );
    await openEditor(tester, a!);

    expect(hasOccupiedDot(tester, 1), isFalse, reason: '第 1 颗是兄弟时段的颜色，是自己人');
    await tapColor(tester, 1);
    expect(collisionHintVisible(), isFalse);
  });

  testWidgets('提示不拦保存：点中撞色保存，落盘就是选中的颜色', (tester) async {
    final pharma = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2, colorValue: colorA),
      ),
    );
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '高等数学', day: 3, start: 1, end: 2, colorValue: colorC),
      ),
    );
    await openEditor(tester, pharma!);

    await tapColor(tester, 8);
    expect(collisionHintVisible(), isTrue);
    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await tester.runAsync<List<Course>>(
      () => Dao.instance.getCoursesBySemester(1),
    );
    expect(list!.firstWhere((c) => c.id == pharma).colorValue, colorC);
    expect(find.text('课程已更新'), findsOneWidget, reason: '单时段课保存成功说「课程已更新」');

    await drain(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester, rounds: 2);
  });

  testWidgets('三处单行输入框 textAlignVertical 都是 y:0.45，备注框保持默认', (tester) async {
    final pharma = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2, colorValue: colorA),
      ),
    );
    await openEditor(tester, pharma!);

    // TextFormField 本身不暴露 textAlignVertical/maxLines，读它内部建的 TextField。
    // （TextFormField 在树里是 4 个：课程名、老师、教室、备注；周次选择器的
    // TextField 是另一个，与 TextFormField 无关，不影响这里的下标。）
    TextField innerField(int index) {
      return tester.widget<TextField>(
        find.descendant(
          of: find.byType(TextFormField).at(index),
          matching: find.byType(TextField),
        ),
      );
    }

    // 顺序：课程名、老师、教室、备注
    const expected = TextAlignVertical(y: 0.45);
    for (var i = 0; i < 3; i++) {
      expect(innerField(i).textAlignVertical, expected,
          reason: '第 $i 处单行框文字要沉回框正中央');
    }
    final note = innerField(3);
    expect(note.maxLines, 2);
    expect(note.textAlignVertical, isNull,
        reason: '备注是多行框，文本本来就贴顶排，不存在单行居中偏高的问题，不加');
  });
}
