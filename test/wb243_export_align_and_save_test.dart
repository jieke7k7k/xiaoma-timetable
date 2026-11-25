import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';

/// 固定浏览周次，避免依赖真实时钟算出来的「本周」
class _FixedWeek extends DisplayWeekNotifier {
  @override
  int build() => 3;
}

/// WB_SPEC_243：导出风格二次对齐 + 导出后保存到本地
///
/// §1：分隔带只写「午间」「晚间」名称，不写居中时间段；课卡教室与老师
/// 分行显示，不拼单行截断。
/// §2：本周导出页双按钮（保存到本地 / 分享图片），保存中置灰防连点，
/// 成功/失败均有 SnackBar 提示；整学期导出 BottomSheet 含保存行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SaveImageToGalleryHandler originalSaveHandler;
  late WeekPngRenderer originalRenderer;

  setUp(() async {
    originalSaveHandler = saveImageToGalleryHandler;
    originalRenderer = weekPngRenderer;
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
    saveImageToGalleryHandler = originalSaveHandler;
    weekPngRenderer = originalRenderer;
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

  group('WB_SPEC_243 §1 风格二次对齐', () {
    testWidgets('分隔带只写「午间」「晚间」名称，不写居中时间段；课卡教室与老师分行显示',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semester = Semester(
        id: 1,
        name: '大三下学期',
        startDate: '2026-09-07',
        isCurrent: true,
      );
      final courses = [
        Course(
          semesterId: 1,
          name: '药剂学',
          classroom: '16-204',
          teacher: '林老师',
          colorValue: 0xFFD8EAD3,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 3, // 3 节高 106dp，显示教室与老师
          weeks: List.generate(16, (i) => i + 1),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemesterSingleImageSheet(
                semester: semester,
                courses: courses,
                slots: defaultTimeSlots,
                bands: computeActiveBands(
                  lunchAfter: 5,
                  dinnerAfter: 9,
                  sectionCount: 14,
                  settings: const BandSettings(),
                ),
                ui: const UiSettings(),
                displayDays: const [1, 2, 3, 4, 5, 6, 7],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 分隔带：轴列有「午间」「晚间」，不再出现带时间段的居中文字
      expect(find.text('午间'), findsOneWidget);
      expect(find.text('晚间'), findsOneWidget);
      expect(find.textContaining('午间 12:00'), findsNothing);
      expect(find.textContaining('晚间 17:10'), findsNothing);

      // 2. 课卡：Text.rich 换行展示课名、教室、老师，不再用 ' · ' 拼在一行截断
      expect(find.textContaining('16-204 · 林老师'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('药剂学\n16-204\n林老师'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('P0-1 复审修正：52dp 单双周半格课卡仍显示教室与老师两行',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 单双周对：1–3 节共 106dp，两门各分 52.25dp；旧公式只给 2 行会
      // 截掉老师，新公式按名行/元数据行分开计给 3 行（课名 1 行 + 教室 + 老师）。
      final semester = Semester(
        id: 1,
        name: '大三下学期',
        startDate: '2026-09-07',
        isCurrent: true,
      );
      final courses = [
        Course(
          semesterId: 1,
          name: '单周课',
          classroom: '16-204',
          teacher: '林老师',
          colorValue: 0xFFD8EAD3,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 3,
          weeks: List.generate(16, (i) => i + 1),
          weekType: 1,
        ),
        Course(
          semesterId: 1,
          name: '双周课',
          classroom: '16-204',
          teacher: '林老师',
          colorValue: 0xFFD2EBE7,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 3,
          weeks: List.generate(16, (i) => i + 1),
          weekType: 2,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemesterSingleImageSheet(
                semester: semester,
                courses: courses,
                slots: defaultTimeSlots,
                bands: computeActiveBands(
                  lunchAfter: 5,
                  dinnerAfter: 9,
                  sectionCount: 14,
                  settings: const BandSettings(),
                ),
                ui: const UiSettings(),
                displayDays: const [1, 2, 3, 4, 5, 6, 7],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // toPlainText 含被截内容，断言 maxLines 与实际渲染高度才有区分度：
      // 3 行实高约 32dp（名 12 + 教室 10 + 老师 10），旧公式 2 行只有约 22dp。
      for (final name in ['单周课', '双周课']) {
        final rich = find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('$name\n16-204\n林老师'),
        );
        expect(rich, findsOneWidget);
        expect(tester.widget<RichText>(rich).maxLines, 3);
        expect(tester.getSize(rich).height, greaterThan(30.0));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('WB_SPEC_243 §2 保存到本地', () {
    testWidgets('本周导出页：双按钮存在、保存中置灰防连点、成功与失败均有 SnackBar 提示',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // FFI 写库须走 runAsync：testWidgets 的 FakeAsync 区里直接 await
      // 真实异步的 FFI Future 永远等不到完成（见 import_schedule_choice 测试注释）。
      await tester.runAsync(
        () => Dao.instance.insertCourse(
          Course(
            semesterId: 1,
            name: '药物分析',
            classroom: '16-102',
            teacher: '张老师',
            colorValue: 0xFFD2EBE7,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3, 4],
          ),
        ),
      );

      final completer = Completer<void>();
      String? savedName;
      Uint8List? savedBytes;
      // 渲染走假字节：flutter_tester 里调真实 toImage 会死等（WB_SPEC_239
      // 测试注释），只验保存流程，不验真实光栅化。
      var renderCalls = 0;
      weekPngRenderer = (boundary, ratio) async {
        renderCalls++;
        return Uint8List.fromList(List.filled(1024, 0x89));
      };
      saveImageToGalleryHandler = (Uint8List bytes, {required String name}) {
        savedName = name;
        savedBytes = bytes;
        return completer.future;
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [displayWeekProvider.overrideWith(_FixedWeek.new)],
          child: const MaterialApp(home: ShareImagePage()),
        ),
      );
      await drain(tester);

      // WB_SPEC_243 §1（P1-3 复审质疑的覆盖缺口）：本周导出预览的带子
      // 轴列仍写「午间」「晚间」，名称没有消失——_ExportSheet 只删了
      // 网格区居中文字，轴列 Positioned 的标签原样保留。
      expect(find.text('午间'), findsOneWidget);
      expect(find.text('晚间'), findsOneWidget);

      // 左右双按钮均存在
      final saveBtn = find.byKey(const ValueKey<String>('btn_save_week_png'));
      final shareBtn =
          find.byKey(const ValueKey<String>('btn_share_week_png'));
      expect(saveBtn, findsOneWidget);
      expect(shareBtn, findsOneWidget);
      expect(find.text('保存到本地'), findsOneWidget);
      expect(find.text('分享图片'), findsOneWidget);

      // 点击「保存到本地」，进入保存中状态，按钮置灰且文案变为「保存中…」
      await tester.tap(saveBtn);
      await tester.pump();
      expect(find.text('保存中…'), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(saveBtn).onPressed, isNull);
      // 分享按钮在保存期间也禁用（共用同一份渲染，不并行跑两次）
      expect(tester.widget<ButtonStyleButton>(shareBtn).onPressed, isNull);

      // 等渲染完成、保存处理器被调用
      for (var i = 0; i < 10 && savedName == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // gal 收到的是不带扩展名的 name（它自己按字节拼 .png），提示里
      // 显示的才是带 .png 的完整文件名。
      expect(savedName, '小马课表-第3周');
      expect(savedBytes, isNotNull);
      expect(savedBytes!.lengthInBytes, greaterThan(0));

      // 完成保存，断言成功 SnackBar
      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('已保存到相册：小马课表-第3周.png'), findsOneWidget);

      // 模拟保存失败，断言弹出失败原因 SnackBar（缓存命中，不重新渲染）。
      // 先清掉成功提示：它盖在底部按钮上，不清点不到保存按钮。
      saveImageToGalleryHandler =
          (Uint8List bytes, {required String name}) async {
        throw StateError('相册写入受阻');
      };
      ScaffoldMessenger.of(tester.element(saveBtn)).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('保存失败：'), findsOneWidget);
      // 两次点保存只渲染了一次（第二次走缓存，同一份字节）
      expect(renderCalls, 1);
    });

    testWidgets('整学期导出 BottomSheet：包含「保存整学期课表到本地」行及副标题',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [displayWeekProvider.overrideWith(_FixedWeek.new)],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ExportBottomSheetContent(
                  displayWeek: 3,
                  parentContext: ctx,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('导出整学期课表（图片）'), findsOneWidget);
      expect(find.text('保存整学期课表到本地'), findsOneWidget);
      expect(find.text('保存至手机相册，随时查看'), findsOneWidget);
    });
  });
}
