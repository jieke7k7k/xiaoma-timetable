import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/pages/import_review_page.dart';

/// 2.14.2 复审 Bug 1（高）：导入时读到不同作息，点「去修改作息」要先应用
/// 读到的作息，再跳转到作息时间页微调——读到的作息不能被丢掉。
/// （他定：先应用读到的，再去微调。）
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late Semester target;

  /// 库里现有的作息（浙师大式前两节）
  const baseSlots = <TimeSlot>[
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:40'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:30'),
  ];

  /// 本次导入读到的作息（与库里不同）
  const incomingSlots = <TimeSlot>[
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
  ];

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    // createSchema 自带默认学期与默认作息；清掉换成可控的固定数据
    await db.delete('semesters');
    await db.delete('time_slots');
    final id = await Dao.instance.insertSemester(const Semester(
      name: '测试学期',
      startDate: '2026-09-07',
      totalWeeks: 20,
    ));
    await Dao.instance.setCurrentSemester(id);
    target = (await Dao.instance.getCurrentSemester())!;
    for (final s in baseSlots) {
      await Dao.instance.updateTimeSlot(s);
    }
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(
      () => db.close(),
    );
  });

  Future<void> pumpReview(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            routes: {
              '/time-settings': (_) =>
                  const Scaffold(body: Text('作息时间页')),
            },
            home: ImportReviewPage(
              drafts: [
                Course(
                  semesterId: target.id!,
                  name: '导入课程A',
                  colorValue: 0xFF8FA3B0,
                  dayOfWeek: 1,
                  startSection: 1,
                  endSection: 2,
                  weeks: const [1, 2, 3],
                ),
              ],
              targetSemester: target,
              webTimeSlots: incomingSlots,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 点「确认导入」并等到「导入完成」弹窗出现
  Future<void> tapImportAndWaitDialog(WidgetTester tester) async {
    await tester.tap(find.text('确认导入'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('导入完成').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 等某个文案出现（弹窗/跳转都靠 runAsync 推进真实异步）
  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
    }
    fail('等不到文案：$text');
  }

  testWidgets('点「去修改作息」：先应用读到的作息，再打开作息时间页',
      (tester) async {
    await pumpReview(tester);

    await tapImportAndWaitDialog(tester);
    expect(find.text('导入完成'), findsOneWidget);

    await tester.tap(find.text('好的'));
    await waitForText(tester, '发现作息时间不同');

    await tester.tap(find.text('去修改作息'));
    await waitForText(tester, '作息时间页');

    // 读到的作息已写库（不是丢掉后让用户从旧作息手动改）
    final after = await tester.runAsync(() => Dao.instance.getTimeSlots());
    final first = after!.firstWhere((s) => s.section == 1);
    expect(first.endTime, '08:45');
    final second = after.firstWhere((s) => s.section == 2);
    expect(second.endTime, '09:35');

    // 收尾：让 fire-and-forget 的服务 FFI 操作在真实时间里跑完，
    // 再走完 fake clock 里挂着的数据库锁定时器
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump(const Duration(seconds: 60));
  });
}
