import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/providers/providers.dart' show SegmentSettings;
import 'package:xiaoma_timetable/ui/app_select_field.dart';
import 'package:xiaoma_timetable/widgets/draft_edit_dialog.dart';

/// WB_SPEC_232 第 5 节：全站下拉换成 AppSelectField + 统一底部抽屉
///
/// 覆盖规格第 9 节第 2 组验收：父级换值后框内立刻跟新值（兄弟时段切换）、
/// 360dp 三个框并排不溢出、开始节次大于结束节次时结束自动顺延、
/// 结束抽屉里小于开始节次的行置灰、点触发框能正常拉起抽屉（先收键盘）、
/// 草稿弹窗节次上限跟学期实际节次数（不再写死 12）、抽屉在 Dialog 之上弹出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  Course course({
    required String name,
    required int day,
    required int start,
    required int end,
  }) {
    return Course(
      semesterId: 1,
      name: name,
      colorValue: 0xFF8FA3B0,
      dayOfWeek: day,
      startSection: start,
      endSection: end,
      weeks: const [1, 2, 3, 4, 5, 6, 7, 8],
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
    await db.close();
  });

  Future<void> drain(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester, int courseId) async {
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
        MaterialPageRoute<void>(builder: (_) => CourseEditPage(courseId: courseId)),
      );
    });
    await drain(tester);
  }

  Future<void> tapSelect(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(AppSelectField<int>, label));
    await tester.pumpAndSettle();
  }

  bool tileEnabled(WidgetTester tester, String label) {
    final f = find.ancestor(of: find.text(label), matching: find.byType(ListTile));
    return tester.widget<ListTile>(f.first).enabled;
  }

  testWidgets('受控：切换兄弟时段后三个框立刻显示新时段的值（不留旧值残影）',
      (tester) async {
    final ids = await tester.runAsync(() async => [
          await Dao.instance.insertCourse(
              course(name: '药理学', day: 2, start: 1, end: 2)),
          await Dao.instance.insertCourse(
              course(name: '药理学', day: 4, start: 3, end: 4)),
        ]);
    await openEditor(tester, ids![0]);

    // 初始：周二 第 1-2 节
    expect(find.text('周二'), findsOneWidget);
    expect(find.text('第 2 节'), findsOneWidget);

    // 点「其他时段」里的 周四 第3-4节，切过去
    await tester.tap(find.text('周四 第3-4节 · 1-8 周'));
    await drain(tester);

    // 新组件不缓存值：三个框必须立即跟到 周四 / 第 3 节 / 第 4 节
    expect(find.text('周四'), findsOneWidget);
    expect(find.text('第 3 节'), findsOneWidget);
    expect(find.text('第 4 节'), findsOneWidget);
    expect(find.text('周二'), findsNothing);
    expect(find.text('第 2 节'), findsNothing);
  });

  testWidgets('360dp 下三个选择框并排不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: AppSelectField<int>(
                    labelText: '星期',
                    value: 3,
                    options: buildWeekdayOptions(),
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSelectField<int>(
                    labelText: '开始节次',
                    value: 3,
                    options: [
                      for (var s = 1; s <= 13; s++)
                        AppSelectOption(value: s, shortLabel: '第 $s 节'),
                    ],
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSelectField<int>(
                    labelText: '结束节次',
                    value: 13,
                    options: [
                      for (var s = 1; s <= 13; s++)
                        AppSelectOption(value: s, shortLabel: '第 $s 节'),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 改前的 DropdownButtonFormField 在这里溢出 24px（RenderFlex overflowed）
    expect(tester.takeException(), isNull);
    // 框内短文案不被截断也能读：三个框都还在
    expect(find.byType(AppSelectField<int>), findsNWidgets(3));
  });

  testWidgets('点触发框能拉起抽屉（先收键盘），并回填选中值', (tester) async {
    final id = await tester.runAsync(() => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2)));
    await openEditor(tester, id!);

    // 先在文本框里点一下（有焦点/软键盘的场景），再点选择框
    await tester.tap(find.widgetWithText(TextFormField, '老师（可空）'));
    await tester.pump();

    await tapSelect(tester, '星期');
    // 抽屉正常弹出，7 行星期都在
    expect(find.text('周日'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);

    await tester.tap(find.text('周五'));
    await tester.pumpAndSettle();
    // 回填：框内只剩短文案「周五」
    expect(find.text('周五'), findsOneWidget);
    expect(find.text('周日'), findsNothing);
  });

  testWidgets('开始节次大于结束节次时，结束自动顺延到开始', (tester) async {
    final id = await tester.runAsync(() => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2)));
    await openEditor(tester, id!);

    await tapSelect(tester, '开始节次');
    await tester.tap(find.text('第 5 节'));
    await tester.pumpAndSettle();

    // 开始=5、结束被顺延成 5 → 两个框都显示「第 5 节」
    expect(find.text('第 5 节'), findsNWidgets(2));
  });

  testWidgets('结束节次抽屉里，小于开始节次的行置灰不可点（不是藏掉）', (tester) async {
    final id = await tester.runAsync(() => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 5, end: 6)));
    await openEditor(tester, id!);

    await tapSelect(tester, '结束节次');
    // 1–4 节置灰；5 及以后可选
    for (final s in [1, 2, 3, 4]) {
      expect(tileEnabled(tester, '第 $s 节'), isFalse, reason: '第 $s 节应置灰');
    }
    expect(tileEnabled(tester, '第 5 节'), isTrue);
    expect(tileEnabled(tester, '第 6 节'), isTrue);
    // 置灰行仍然显示（用户要知道为什么点不了）
    expect(find.text('第 3 节'), findsOneWidget);
  });

  testWidgets('节次抽屉带时间与午休/晚餐分隔行（三处表单共用的构造器）',
      (tester) async {
    final id = await tester.runAsync(() => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2)));
    await openEditor(tester, id!);

    await tapSelect(tester, '开始节次');
    // 第 5 节行右侧带上下课时间
    expect(find.text('11:20 – 12:00'), findsOneWidget);
    // 第 5 节后有午休分隔行、第 9 节后有晚餐分隔行
    expect(find.text('— 午休 (12:00–14:00) —'), findsOneWidget);
    expect(find.text('— 晚餐 (17:10–18:00) —'), findsOneWidget);
  });

  testWidgets('草稿弹窗：节次上限跟学期实际节次数（13），抽屉盖在 Dialog 之上',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navKey,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showDraftEditDialog(
                    context,
                    course(name: '药理学', day: 2, start: 1, end: 2),
                  ),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        ),
      );
    });
    await drain(tester, rounds: 2);
    await tester.tap(find.text('OPEN'));
    await drain(tester);
    expect(find.text('编辑导入课程'), findsOneWidget);

    await tapSelect(tester, '开始节次');
    // 旧实现写死 12：第 13 节根本不在列表里（latent bug）
    expect(find.text('第 13 节'), findsOneWidget);
    // 抽屉在 Dialog 之上弹出：Dialog 仍然在树里，没被顶掉/裁剪
    expect(find.text('编辑导入课程'), findsOneWidget);

    await tester.ensureVisible(find.text('第 13 节'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 13 节'));
    await tester.pumpAndSettle();
    // 已回填：开始节次是 13，结束节次被防倒挂逻辑顺延成 13 → 两个框都显示它
    expect(find.text('第 13 节'), findsNWidgets(2));
  });

  group('节次抽屉行（第 7 节：列表带时间＋分隔行）', () {
    List<TimeSlot> slots13() => [
          for (var s = 1; s <= 13; s++)
            TimeSlot(
              section: s,
              startTime: '0${8 + s ~/ 6}:00',
              endTime: '0${8 + s ~/ 6}:40',
            ),
        ];

    test('默认分段点：第 5 节后午休、第 9 节后晚餐，时间取相邻两节边界', () {
      final opts = buildSectionOptions(slots: const [
        TimeSlot(section: 5, startTime: '11:20', endTime: '12:00'),
        TimeSlot(section: 6, startTime: '14:00', endTime: '14:40'),
        TimeSlot(section: 9, startTime: '16:30', endTime: '17:10'),
        TimeSlot(section: 10, startTime: '18:00', endTime: '18:40'),
        TimeSlot(section: 11, startTime: '18:50', endTime: '19:30'),
      ]);
      final labels = opts.map((o) => o.label).toList();
      expect(labels.contains('— 午休 (12:00–14:00) —'), isTrue);
      expect(labels.contains('— 晚餐 (17:10–18:00) —'), isTrue);
      // 分隔行紧跟在对应节次之后
      final lunchIdx = labels.indexOf('— 午休 (12:00–14:00) —');
      expect(opts[lunchIdx].isDivider, isTrue);
      expect(labels[lunchIdx - 1], '第 5 节');
      // 行里带时间、框内短语不带时间
      final row5 = opts.firstWhere((o) => o.value == 5);
      expect(row5.subLabel, '11:20 – 12:00');
      expect(row5.shortLabel, '第 5 节');
    });

    test('作息页把午休改到第 4 节后，分隔行跟着挪到第 4 节', () {
      final opts = buildSectionOptions(
        slots: const [
          TimeSlot(section: 4, startTime: '10:30', endTime: '11:10'),
          TimeSlot(section: 5, startTime: '11:20', endTime: '12:00'),
          TimeSlot(section: 6, startTime: '14:00', endTime: '14:40'),
        ],
        seg: const SegmentSettings(lunchAfterSection: 4, dinnerAfterSection: 9),
      );
      final labels = opts.map((o) => o.label).toList();
      expect(labels.contains('— 午休 (11:10–11:20) —'), isTrue);
      expect(labels.indexOf('— 午休 (11:10–11:20) —'), 1); // 紧跟第 4 节
    });

    test('结束节次抽屉：小于开始节次的置灰但仍在列表里', () {
      final opts = buildSectionOptions(
        slots: slots13(),
        minSection: 3,
      ).where((o) => !o.isDivider).toList();
      expect(opts.firstWhere((o) => o.value == 1).enabled, isFalse);
      expect(opts.firstWhere((o) => o.value == 2).enabled, isFalse);
      expect(opts.firstWhere((o) => o.value == 3).enabled, isTrue);
    });
  });

  testWidgets('编辑页组头有「在课表上选」，点开是迷你周视图，确认后三个框一起更新',
      (tester) async {
    final id = await tester.runAsync(() => Dao.instance.insertCourse(
        course(name: '药理学', day: 2, start: 1, end: 2)));
    await openEditor(tester, id!);

    expect(find.text('星期与节次'), findsOneWidget);
    expect(find.text('在课表上选'), findsOneWidget);

    await tester.tap(find.text('在课表上选'));
    await tester.pump();
    await drain(tester, rounds: 4);
    expect(find.text('选择上课时间'), findsOneWidget);

    // 点两格定一段：周四 第 6–7 节
    await tester.tap(find.byKey(const ValueKey('mini-cell-4-6')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mini-cell-4-7')));
    await tester.pump();
    await tester.tap(find.text('确认选定'));
    await tester.pumpAndSettle();
    await drain(tester, rounds: 3);

    // 写回后三个框立即刷新（受控组件 + setState）
    expect(find.text('周四'), findsOneWidget);
    expect(find.text('第 6 节'), findsOneWidget);
    expect(find.text('第 7 节'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester, rounds: 2);
  });

  testWidgets('360dp 下外观页两个设置行（课程配色 / 显示字体）不溢出，点开是抽屉',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppearanceSettingsPage()),
      ),
    );
    await drain(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('课程配色'), findsWidgets);
    expect(find.text('显示字体'), findsWidgets);

    // 旧下拉不再存在，两处都是标准 56dp 设置行
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(AppSelectSettingRow<String>), findsNWidgets(2));

    // 点课程配色行 → 统一抽屉，10 套方案都在
    await tester.tap(find.text('课程配色').first);
    await tester.pumpAndSettle();
    expect(find.text('莫兰迪·高级灰'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester, rounds: 2);
  });
}
