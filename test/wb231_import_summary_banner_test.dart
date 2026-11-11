import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/pages/import_review_page.dart';

/// WB_SPEC_231 第 5.4 节：抓取成功后的结果确认条（常驻横幅，不做假三步进度）。
///
/// - 只有网页抓取来源才传汇总文案、横幅才出现；ICS / 图片 / PDF 导入不传、不出现；
/// - 横幅里的 N 与 AppBar 标题的「N 门」必须是同一个数字。
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
    await db.close();
  });

  final semester = Semester(
    id: 1,
    name: '默认学期',
    startDate: '2026-09-07',
    totalWeeks: 20,
    isCurrent: true,
  );

  List<Course> drafts() => [
        Course(
          semesterId: 1,
          name: '药理学',
          colorValue: 0xFF8FA3B0,
          dayOfWeek: 2,
          startSection: 1,
          endSection: 2,
          weeks: const [1, 2, 3],
        ),
        Course(
          semesterId: 1,
          name: '药物分析',
          colorValue: 0xFFAFC3BB,
          dayOfWeek: 3,
          startSection: 3,
          endSection: 4,
          weeks: const [1, 2, 3],
        ),
      ];

  Future<void> pumpReview(
    WidgetTester tester, {
    String? summary,
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImportReviewPage(
              drafts: drafts(),
              targetSemester: semester,
              webImportSummary: summary,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('网页抓取来源：顶部常驻横幅显示 N 门 / M 个排课节次', (tester) async {
    await pumpReview(
      tester,
      summary: '已从当前页面识别出 2 门课程（共 4 个排课节次）',
    );

    expect(find.byKey(const Key('import-web-summary-banner')), findsOneWidget);
    expect(find.text('已从当前页面识别出 2 门课程（共 4 个排课节次）'), findsOneWidget);
    // N 与标题门数是同一个数字
    expect(find.text('核对导入结果（2 门）'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('非网页来源：不传汇总文案就没有横幅', (tester) async {
    await pumpReview(tester);

    expect(find.byKey(const Key('import-web-summary-banner')), findsNothing);
    expect(find.textContaining('已从当前页面识别出'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
