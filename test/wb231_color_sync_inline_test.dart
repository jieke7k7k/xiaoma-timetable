import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/utils/color_schemes.dart';
import 'package:xiaoma_timetable/utils/morandi_palette.dart';

/// WB_SPEC_231 第 12.2 节：改颜色「内联行提示 + 颜色按需同步」（不弹窗）。
///
/// 覆盖规格第 12.2 节列出的全部测试点：
/// - 内联行仅在「多时段 + 本次改了颜色」时出现；
/// - 默认选「应用到本课全部」；
/// - 切「仅改本节」后兄弟颜色不动、当前时段变色；
/// - 只改老师不改颜色时兄弟颜色不动（防「颜色被洗掉」回归）；
/// - Toast 文案（含「颜色仅应用于当前时段」）；
/// - 「其他时段」小圆点跟随选择实时变色；
/// - 切换时段后内联行回到默认态。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  /// 两时段样例课的 id：[0] 周二 1-2（颜色 A），[1] 周四 3-4（颜色 B）
  late List<int> ids;

  /// 两条时段各自的莫兰迪色位（取值都在色板内，避免出现「历史自定义色」那一颗）
  final colorA = MorandiPalette.colors[0];
  final colorB = MorandiPalette.colors[4];
  final colorC = MorandiPalette.colors[8];

  /// 存储色 → 屏幕显示色（与页面同一口径：先按配色方案映射，测试里是浅色不降饱和）
  Color display(int stored) =>
      Color(mapCourseColor(stored, const UiSettings().colorScheme));

  Course course({
    required String name,
    required int day,
    required int start,
    required int end,
    String? teacher,
    String? classroom,
    int? colorValue,
  }) {
    return Course(
      semesterId: 1,
      name: name,
      teacher: teacher,
      classroom: classroom,
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

  /// 给真实异步多轮窗口（写库、provider reload 都是真实 Future）
  Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  /// 打开编辑页：挂在 HOME 之上，保存成功后 pop 回 HOME（不黑屏）
  ///
  /// 画布拉高到 2400（逻辑像素）：内联行展开后页面更长，ListView 只建可见子项，
  /// 画布不够高时「其他时段」行会被回收，断言就找不到小圆点了。
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

  Future<List<Course>> allCourses(WidgetTester tester) async {
    final list = await tester.runAsync<List<Course>>(
      () => Dao.instance.getCoursesBySemester(1),
    );
    return list ?? const [];
  }

  Course byId(List<Course> list, int id) => list.firstWhere((c) => c.id == id);

  Future<void> seedTwoSlots() async {
    final a = course(
      name: '药理学',
      day: 2,
      start: 1,
      end: 2,
      teacher: '张老师',
      classroom: '302',
      colorValue: colorA,
    );
    final b = course(
      name: '药理学',
      day: 4,
      start: 3,
      end: 4,
      teacher: '张老师',
      classroom: '105',
      colorValue: colorB,
    );
    ids = [
      await Dao.instance.insertCourse(a),
      await Dao.instance.insertCourse(b),
    ];
  }

  /// 点色板第 [index] 颗色块（画布够高，不需要滚动）
  Future<void> tapColor(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(ValueKey('color-dot-$index')));
    await tester.pumpAndSettle();
  }

  /// 点内联行的某个选项
  Future<void> tapChoice(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  /// 内联行某个选项当前是否选中（实心圆点 = 选中）
  bool choiceSelected(WidgetTester tester, String key) {
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Icon),
      ),
    );
    return icon.icon == Icons.radio_button_checked;
  }

  /// 「其他时段」行首那颗 10dp 小圆点当前的颜色
  Color siblingDot(WidgetTester tester, int courseId) {
    final container = tester.widget<Container>(
      find.byKey(ValueKey('sibling-dot-$courseId')),
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  bool colorRowVisible() =>
      find.textContaining('已更改颜色').evaluate().isNotEmpty;

  testWidgets('多时段改色：色块下方展开内联行，默认「应用到本课全部」', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    // 进页面还没改色 → 不展开
    expect(colorRowVisible(), isFalse);

    await tapColor(tester, 4);

    expect(colorRowVisible(), isTrue);
    expect(find.text('应用到本课全部 2 个时段'), findsOneWidget);
    expect(find.text('仅改本节'), findsOneWidget);
    expect(choiceSelected(tester, 'color-sync-all'), isTrue, reason: '默认应用到全部');
    expect(choiceSelected(tester, 'color-sync-current'), isFalse);
  });

  testWidgets('单时段课改色：不展开内联行（只有一个时段，没得选）', (tester) async {
    final id = await tester.runAsync(
      () => Dao.instance.insertCourse(
        course(name: '单时段课', day: 1, start: 1, end: 2),
      ),
    );
    await openEditor(tester, id!);

    await tapColor(tester, 4);

    expect(find.text('其他时段（同一门课）'), findsNothing);
    expect(colorRowVisible(), isFalse);
  });

  testWidgets('多时段课不改颜色：不展开内联行', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    // 只改老师，颜色一个字没动
    await tester.enterText(find.byType(TextFormField).at(1), '李老师');
    await tester.pumpAndSettle();

    expect(colorRowVisible(), isFalse);
  });

  testWidgets('默认「应用到全部」保存：兄弟时段一起换色 + Toast 常规同步文案', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tapColor(tester, 8);
    expect(choiceSelected(tester, 'color-sync-all'), isTrue);

    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).colorValue, colorC, reason: '当前时段用新色');
    expect(byId(list, ids[1]).colorValue, colorC, reason: '选了全部，兄弟时段一起换');
    expect(find.text('已同步到本课共 2 个时段'), findsOneWidget);

    await drain(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester, rounds: 2);
  });

  testWidgets('切「仅改本节」保存：兄弟颜色不动、当前时段变色 + Toast 说明', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tapColor(tester, 8);
    await tapChoice(tester, 'color-sync-current');
    expect(choiceSelected(tester, 'color-sync-current'), isTrue);
    expect(choiceSelected(tester, 'color-sync-all'), isFalse);

    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).colorValue, colorC, reason: '当前时段换成新色');
    expect(byId(list, ids[1]).colorValue, colorB,
        reason: '仅改本节：兄弟时段保留自己库里的颜色，不能被顺手改成新色');
    expect(find.text('已保存（颜色仅应用于当前时段）'), findsOneWidget);

    await drain(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester, rounds: 2);
  });

  testWidgets('只改老师不改颜色：兄弟颜色不被洗掉（回归）', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tester.enterText(find.byType(TextFormField).at(1), '李老师');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).teacher, '李老师');
    expect(byId(list, ids[1]).teacher, '李老师');
    expect(byId(list, ids[0]).colorValue, colorA);
    expect(byId(list, ids[1]).colorValue, colorB,
        reason: '没改颜色时兄弟时段的颜色必须原样保留，不能跟着当前时段被洗成 A');
    expect(find.text('已同步到本课共 2 个时段'), findsOneWidget);

    await drain(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester, rounds: 2);
  });

  testWidgets('其他时段小圆点：初始是自己的颜色，跟随内联行选择实时联动', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    // 初始：兄弟时段显示自己的原色
    expect(siblingDot(tester, ids[1]), display(colorB));

    // 改色（默认应用到全部）→ 圆点跟着变新色
    await tapColor(tester, 8);
    expect(siblingDot(tester, ids[1]), display(colorC),
        reason: '选了「应用到全部」，兄弟时段将来就是这个颜色');

    // 切「仅改本节」→ 圆点回到兄弟自己的原色
    await tapChoice(tester, 'color-sync-current');
    expect(siblingDot(tester, ids[1]), display(colorB));

    // 再点别的色块试颜色：选择保持「仅改本节」，圆点仍是兄弟原色
    await tapColor(tester, 12);
    expect(choiceSelected(tester, 'color-sync-current'), isTrue,
        reason: '再次试色不重置用户的选择');
    expect(siblingDot(tester, ids[1]), display(colorB));

    // 切回「应用到全部」→ 圆点立刻跟到最新试的那个颜色
    await tapChoice(tester, 'color-sync-all');
    expect(siblingDot(tester, ids[1]), display(MorandiPalette.colors[12]));
  });

  testWidgets('切换时段后：内联行按新时段的初始颜色重算，回到默认态', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    // 改了颜色但先不保存 → 直接切会被三选框拦住，这里先「放弃」
    await tapColor(tester, 8);
    expect(colorRowVisible(), isTrue);
    await tester.tap(find.text('周四 第3-4节 · 1-16 周'));
    await drain(tester);
    expect(find.text('当前时段有未保存的改动'), findsOneWidget);
    await tester.tap(find.text('放弃'));
    await drain(tester);

    // 切到周四那条：颜色跟着表单换成 B，等于「没改颜色」→ 内联行收起
    expect(find.text('105'), findsOneWidget);
    expect(colorRowVisible(), isFalse);
    expect(siblingDot(tester, ids[0]), display(colorA));

    // 再改一次色 → 内联行重新展开且是默认的「应用到全部」
    await tapColor(tester, 8);
    expect(colorRowVisible(), isTrue);
    expect(choiceSelected(tester, 'color-sync-all'), isTrue,
        reason: '切时段后选择回到默认态');
    expect(siblingDot(tester, ids[0]), display(colorC));
  });

  // 注：本想在 360dp 真机宽度下直接验「内联行折行不溢出」，实测发现编辑页
  // 「开始/结束节次」两个下拉框在 360dp 下本身就溢出 24px（基线代码的旧问题，
  // 与 §12 无关，已记档、未在本轮修），整页 pump 必然报错。改锁结构：内联行
  // 必须是 Wrap（不是 Row）——Wrap 天生折行不溢出；再断言最小高 36。
  testWidgets('内联行用 Wrap + 最小高 36（窄屏折行不溢出，自报#5 的兜底）', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tapColor(tester, 8);
    expect(colorRowVisible(), isTrue);

    final wrap = find.ancestor(
      of: find.textContaining('已更改颜色'),
      matching: find.byType(Wrap),
    );
    expect(wrap, findsOneWidget, reason: '内联行必须是 Wrap，Row 在窄屏会报溢出');
    final container = tester.widget<Container>(
      find.ancestor(of: wrap, matching: find.byType(Container)).first,
    );
    expect(container.constraints?.minHeight, 36,
        reason: '正常宽度下仍是一行 36dp');
    expect(tester.takeException(), isNull);
  });

  testWidgets('改色后点回原始色：内联行收起，落盘等同未改色', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    await tapColor(tester, 8);
    expect(colorRowVisible(), isTrue);
    await tapChoice(tester, 'color-sync-current');
    // 点回原来的色位（colorA 是第 0 颗）
    await tapColor(tester, 0);
    expect(colorRowVisible(), isFalse, reason: '颜色改回原值，等于没改过色');

    await tester.tap(find.text('保存'));
    await drain(tester);

    final list = await allCourses(tester);
    expect(byId(list, ids[0]).colorValue, colorA);
    expect(byId(list, ids[1]).colorValue, colorB);
    expect(find.text('已同步到本课共 2 个时段'), findsOneWidget);

    await drain(tester, rounds: 4);
    await tester.pump(const Duration(seconds: 5));
    await drain(tester, rounds: 2);
  });

  testWidgets('底部文案改成「颜色按上方选择同步」', (tester) async {
    await tester.runAsync(seedTwoSlots);
    await openEditor(tester, ids[0]);

    expect(
      find.text('改课程名、老师、教室、备注会同步到本课全部时段；颜色按上方选择同步；时间与周次只改这一条。'),
      findsOneWidget,
    );
  });
}
