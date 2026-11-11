import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';

/// WB_SPEC_231 第 3.3 节：空周占位分两种情况。
///
/// - 情况 A（当前学期课程总数为 0）：文字 + 「导入课表」「手动加课」两个按钮；
/// - 情况 B（学期有课、只是这一周没课）：纯文本，一个按钮都不放
///   （否则用户在第 18 周会误以为要重新导入，把整学期弄乱）。
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
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.3.0',
      buildNumber: '37',
      buildSignature: '',
    );
    sundayDialogNow = () => DateTime.now().subtract(const Duration(days: 1));
    // 学期从 17 周前开学：今天正好是第 18 周（考试周，通常没课）
    final start = DateTime.now().subtract(const Duration(days: 17 * 7));
    String two(int v) => v.toString().padLeft(2, '0');
    final existing = await Dao.instance.getCurrentSemester();
    if (existing != null) {
      await Dao.instance.updateSemester(
        existing.copyWith(
          startDate: '${start.year}-${two(start.month)}-${two(start.day)}',
          totalWeeks: 20,
        ),
      );
    }
  });

  tearDown(() async {
    sundayDialogNow = DateTime.now;
    await db.close();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            const ProviderScope(child: MaterialApp(home: HomeShell())),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final ready = find.byType(WeekViewPage).evaluate().isNotEmpty &&
          find
              .descendant(
                of: find.byType(WeekViewPage),
                matching: find.byType(SingleChildScrollView),
              )
              .evaluate()
              .isNotEmpty;
      if (ready) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// 收尾：主页启动联动里有延时任务，把假时钟往前推一段再结束，
  /// 避免 teardown 报「A Timer is still pending」
  Future<void> finish(WidgetTester tester) async {
    // 先把树换掉触发 dispose（周视图的 30 秒状态条周期表要在 dispose 里取消），
    // 再把启动联动的延时任务推完，避免 teardown 报「A Timer is still pending」
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 11));
  }

  testWidgets('情况 A：学期里一门课都没有 → 有「导入课表」「手动加课」两个按钮', (tester) async {
    await pumpHome(tester);

    expect(find.text('本周没有课程'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '导入课表'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '手动加课'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('情况 B：学期有课但本周没课（第 18 周）→ 纯文本、无按钮', (tester) async {
    // 只排第 1-2 周的课：今天第 18 周，本周必然一门课都没有
    await tester.runAsync(
      () => Dao.instance.insertCourse(
        Course(
          semesterId: 1,
          name: '药理学',
          colorValue: 0xFF8FA3B0,
          dayOfWeek: 2,
          startSection: 1,
          endSection: 2,
          weeks: const [1, 2],
        ),
      ),
    );

    await pumpHome(tester);

    expect(find.text('本周没有课程'), findsOneWidget);
    expect(find.text('导入课表'), findsNothing, reason: '情况 B 不允许出现导入按钮');
    expect(find.text('手动加课'), findsNothing);
    await finish(tester);
  });
}
