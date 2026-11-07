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
import 'package:xiaoma_timetable/utils/ics_parser.dart';
import 'package:xiaoma_timetable/utils/slot_calibrator.dart';

/// WB_SPEC_227 测试：导入预览页的作息选择（架构 A+：全局作息、零迁移）。
///
/// 覆盖第 5 节：
/// - timeBlocks 为空（图片/PDF）无卡片；
/// - 预演 diff 为空时不渲染卡片；
/// - diff 非空时默认选中（空学期 → 用读取到的；有课程的学期 → 保持）；
/// - 差异可展开逐条看、切「保持」后收起并说明不改动；
/// - 选「仅导入课程」提交：作息表纹丝不动、完成弹窗不提作息；
/// - 选「使用读取到的作息」提交：逐节写入、完成弹窗只有一句话汇总。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late Semester target;

  /// 固定的 4 节现有作息（校准底表）
  const baseSlots = <TimeSlot>[
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
    TimeSlot(section: 3, startTime: '10:00', endTime: '10:45'),
    TimeSlot(section: 4, startTime: '10:55', endTime: '11:40'),
  ];

  /// 文件作息：与 baseSlots 不同，预演必然产生 diff
  final blocks = <IcsTimeBlock>[
    const IcsTimeBlock(
        startSection: 1, endSection: 1, startTime: '08:30', endTime: '09:15'),
    const IcsTimeBlock(
        startSection: 3, endSection: 3, startTime: '10:10', endTime: '10:55'),
  ];

  /// 时间值全非法的块：calibrate 逐节保留 baseSlots 原值 → 预演 diff 为空
  final noDiffBlocks = <IcsTimeBlock>[
    const IcsTimeBlock(
        startSection: 1, endSection: 1, startTime: '', endTime: '25:99'),
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
    // createSchema 自带默认学期与 12 节默认作息；清掉换成可控的固定数据
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

  Course draft() => Course(
        semesterId: target.id!,
        name: '导入课程A',
        colorValue: 0xFF8FA3B0,
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        weeks: const [1, 2, 3],
      );

  /// 播种一门目标学期已有课程（「有课程的学期默认保持」用例用）。
  /// 与 draft 时间/名称都不冲突，不影响提交用例的冲突预检。
  Future<void> seedExistingCourse() async {
    await Dao.instance.insertCourse(
      Course(
        semesterId: target.id!,
        name: '既有课程',
        colorValue: 0xFF8FA3B0,
        dayOfWeek: 6,
        startSection: 7,
        endSection: 8,
        weeks: const [1, 2],
      ),
    );
  }

  /// pump 预览页：runAsync 让 FFI 异步（读作息 / 查课程）与 provider future 完成
  Future<void> pumpReview(
    WidgetTester tester, {
    List<IcsTimeBlock> timeBlocks = const [],
    bool withExistingCourse = false,
  }) async {
    if (withExistingCourse) {
      await tester.runAsync(seedExistingCourse);
    }
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImportReviewPage(
              drafts: [draft()],
              targetSemester: target,
              timeBlocks: timeBlocks,
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

  /// 点「确认导入」并等到「导入完成」弹窗出现（事务/落库/重排全靠 runAsync 推进）
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

  /// 手动 pump 若帧（AnimatedSize 展开/收起动画走完，避开 pumpAndSettle 对
  /// FFI 异步不收敛的坑）
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<String> slotTexts(List<TimeSlot> slots) => [
        for (final s in slots) '${s.section}|${s.startTime}|${s.endTime}',
      ];

  /// 复现预演 diff 的节次数（新增或起止变化），用于完成弹窗一句话汇总断言
  int diffCount(List<TimeSlot> base, List<TimeSlot> calibrated) {
    var n = 0;
    for (final ns in calibrated) {
      TimeSlot? old;
      for (final s in base) {
        if (s.section == ns.section) {
          old = s;
          break;
        }
      }
      if (old == null ||
          old.startTime != ns.startTime ||
          old.endTime != ns.endTime) {
        n++;
      }
    }
    return n;
  }

  group('WB_SPEC_227：作息选择卡片渲染条件', () {
    testWidgets('图片/PDF（timeBlocks 为空）无卡片', (tester) async {
      await pumpReview(tester);
      expect(find.text('检测到课表自带作息时间'), findsNothing);
      expect(find.textContaining('处差异'), findsNothing);
    });

    testWidgets('预演 diff 为空时不渲染卡片', (tester) async {
      await pumpReview(tester, timeBlocks: noDiffBlocks);
      expect(find.text('检测到课表自带作息时间'), findsNothing);
      expect(find.textContaining('处差异'), findsNothing);
    });

    testWidgets('diff 非空时渲染卡片，标题与「查看 N 处差异」可见', (tester) async {
      await pumpReview(tester, timeBlocks: blocks);
      expect(find.text('检测到课表自带作息时间'), findsOneWidget);
      expect(find.textContaining('处差异'), findsOneWidget);
      expect(diffCount(baseSlots, SlotCalibrator.calibrate(baseSlots, blocks)),
          greaterThan(0));
    });
  });

  group('WB_SPEC_227：默认选中项（3.3 智能分流）', () {
    testWidgets('空学期：默认「使用读取到的作息」', (tester) async {
      await pumpReview(tester, timeBlocks: blocks);
      expect(find.text('同步更新全局节次时间'), findsOneWidget);
      expect(find.text('保持现有全局作息，上下课时间不作改动'), findsNothing);
    });

    testWidgets('有课程的学期：默认「保持现有作息」防误伤', (tester) async {
      await pumpReview(tester, timeBlocks: blocks, withExistingCourse: true);
      expect(find.text('保持现有全局作息，上下课时间不作改动'), findsOneWidget);
      expect(find.text('同步更新全局节次时间'), findsNothing);
    });
  });

  group('WB_SPEC_227：差异展示（3.5）', () {
    testWidgets('选「使用读取到的作息」展开逐条差异，切「保持」后收起',
        (tester) async {
      await pumpReview(tester, timeBlocks: blocks);
      // 初始收起：卡片里没有逐条差异文案
      expect(find.textContaining('第 1 节：'), findsNothing);

      await tester.tap(find.textContaining('处差异'));
      await settleFrames(tester);
      expect(find.textContaining('第 1 节：'), findsOneWidget);

      // 切到「保持现有作息」：差异区收起，说明变为不改动上下课时间
      await tester.tap(find.text('仅导入课程（保持现有作息）'));
      await settleFrames(tester);
      expect(find.text('保持现有全局作息，上下课时间不作改动'), findsOneWidget);
      expect(find.textContaining('第 1 节：'), findsNothing);
    });
  });

  group('WB_SPEC_227：提交时按选择写作息（3.5）', () {
    testWidgets('选「仅导入课程」提交：作息表纹丝不动，完成弹窗不提作息',
        (tester) async {
      await pumpReview(tester, timeBlocks: blocks);
      // 空学期默认是 useFile，这里手动切到 keepGlobal
      await tester.tap(find.text('仅导入课程（保持现有作息）'));
      await settleFrames(tester);

      await tapImportAndWaitDialog(tester);

      expect(find.text('导入完成'), findsOneWidget);
      // 完成弹窗既无逐条标题，也无一句话汇总（完全不提作息）
      expect(find.text('作息已按课表文件校准：'), findsNothing);
      expect(find.textContaining('已同步更新'), findsNothing);
      // 作息表逐节与底表一致
      final after = await tester.runAsync(() => Dao.instance.getTimeSlots());
      expect(slotTexts(after!), equals(slotTexts(baseSlots)));
      // 收尾：走完可能挂着的服务/动画定时器
      // 收尾：先让 fire-and-forget 的服务 FFI 操作在真实时间里跑完，
      // 再走完 fake clock 里挂着的数据库锁定时器，避免收尾报
      // 「A Timer is still pending」（与 import_target_default_new_test 同一处理）
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(seconds: 60));
    });

    testWidgets('选「使用读取到的作息」提交：逐节写入，完成弹窗只有一句话汇总',
        (tester) async {
      await pumpReview(tester, timeBlocks: blocks);
      // 空学期默认即 useFile
      expect(find.text('同步更新全局节次时间'), findsOneWidget);

      await tapImportAndWaitDialog(tester);

      expect(find.text('导入完成'), findsOneWidget);
      final calibrated = SlotCalibrator.calibrate(baseSlots, blocks);
      final n = diffCount(baseSlots, calibrated);
      expect(find.text('已同步更新 $n 个节次的默认上下课时间'), findsOneWidget);
      // 不再逐条罗列差异
      expect(find.text('作息已按课表文件校准：'), findsNothing);
      expect(find.textContaining('第 1 节：'), findsNothing);
      // 作息表逐节写入预演结果
      final after = await tester.runAsync(() => Dao.instance.getTimeSlots());
      expect(slotTexts(after!), equals(slotTexts(calibrated)));
      // 收尾：先让 fire-and-forget 的服务 FFI 操作在真实时间里跑完，
      // 再走完 fake clock 里挂着的数据库锁定时器，避免收尾报
      // 「A Timer is still pending」（与 import_target_default_new_test 同一处理）
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(seconds: 60));
    });
    testWidgets('预演完成前点「确认导入」：等预演完成再写库，不静默跳过（复审 Bug 1）',
        (tester) async {
      // 只 pump 一帧：initState 已触发预演，但读作息/查课程的 await 还没跑完；
      // 先断言卡片还没出现，确认测试确实落在预演完成前的时间窗口里。
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: ImportReviewPage(
                drafts: [draft()],
                targetSemester: target,
                timeBlocks: blocks,
              ),
            ),
          ),
        );
      });
      expect(find.text('检测到课表自带作息时间'), findsNothing);

      // 不等预演，直接点确认导入
      await tapImportAndWaitDialog(tester);

      expect(find.text('导入完成'), findsOneWidget);
      final calibrated = SlotCalibrator.calibrate(baseSlots, blocks);
      final n = diffCount(baseSlots, calibrated);
      expect(find.text('已同步更新 $n 个节次的默认上下课时间'), findsOneWidget);
      // 作息表逐节写入预演结果（不是静默跳过）
      final after = await tester.runAsync(() => Dao.instance.getTimeSlots());
      expect(slotTexts(after!), equals(slotTexts(calibrated)));
      // 收尾：先让 fire-and-forget 的服务 FFI 操作在真实时间里跑完，
      // 再走完 fake clock 里挂着的数据库锁定时器，避免收尾报
      // 「A Timer is still pending」（与 import_target_default_new_test 同一处理）
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump(const Duration(seconds: 60));
    });
  });
}
