import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/pages/import_conflicts_page.dart';
import 'package:xiaoma_timetable/pages/import_page.dart';
import 'package:xiaoma_timetable/pages/import_review_page.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/conflict_detector.dart';
import 'package:xiaoma_timetable/utils/import_planner.dart';
import 'package:xiaoma_timetable/widgets/app_dialog.dart';
import 'package:xiaoma_timetable/widgets/course_detail_sheet.dart';
import 'package:xiaoma_timetable/widgets/select_time_sheet.dart';
import 'package:xiaoma_timetable/widgets/update_download_dialog.dart';
import 'package:xiaoma_timetable/widgets/week_picker.dart';

/// WB_SPEC_256 §10 手动泵法（严禁使用 pumpAndSettle）
///
/// 落盘补：Neon 原稿每轮只在开头做一次 runAsync，之后各轮纯 pump；
/// DB 查询（sqflite 的 txnSynchronized 自带 10 秒锁超时 Timer）若在
/// pump 的假时钟里触发，会留下 pending 的 FakeTimer，收尾断言必挂，
/// 且 provider 的 future 得不到真实时间窗口、页面会卡在 loading。
/// 按仓库惯例（wb232/wb231 的 drain）每轮都先 runAsync 再 pump。
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Course _sampleCourse({
  int id = 1,
  int semesterId = 1,
  String name = '药理学',
  int dayOfWeek = 1,
  int startSection = 1,
  int endSection = 2,
}) {
  return Course(
    id: id,
    semesterId: semesterId,
    name: name,
    teacher: '周老师',
    classroom: '教3-201',
    colorValue: 0xFF8FA3B0,
    dayOfWeek: dayOfWeek,
    startSection: startSection,
    endSection: endSection,
    weeks: const [1, 2, 3, 4],
  );
}

Semester _sampleSemester({
  int id = 1,
  String name = '2026秋',
  bool isCurrent = true,
}) {
  return Semester(
    id: id,
    name: name,
    startDate: '2026-09-07',
    totalWeeks: 20,
    isCurrent: isCurrent,
  );
}

List<TimeSlot> _sampleSlots() => [
      for (var i = 1; i <= 10; i++)
        TimeSlot(
          section: i,
          startTime: '${(7 + i).toString().padLeft(2, '0')}:00',
          endTime: '${(7 + i).toString().padLeft(2, '0')}:45',
        ),
    ];

/// WB_SPEC_256 复审 #34 用：读课程即抛错，触发导出失败分支。
class _ThrowingCoursesNotifier extends CoursesNotifier {
  @override
  Future<List<Course>> build() async => throw Exception('模拟读取课表失败');
}

Widget _wrapWithTheme(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E7B67)),
      ),
      home: child,
    ),
  );
}

void main() {
  // 落盘补：Neon 原稿缺 FFI 初始化，泵 DB 驱动页会报 databaseFactory 未初始化。
  // 按仓库惯例（wb231_import_summary_banner_test）接内存库。
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

  group('WB_SPEC_256 §10 静态源码红线验收', () {
    test('§10.5 全仓 grep AlertDialog( 仅允许出现在 app_dialog.dart 内部封装', () {
      final libDir = Directory('lib');
      final hits = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalized = entity.path.replaceAll('\\', '/');
        if (normalized.endsWith('lib/widgets/app_dialog.dart')) continue;
        final content = entity.readAsStringSync();
        if (content.contains('AlertDialog(')) {
          hits.add(normalized);
        }
      }
      expect(
        hits,
        isEmpty,
        reason: '发现未迁移的原生 AlertDialog：$hits',
      );

      final updateDialogCode =
          File('lib/widgets/update_download_dialog.dart').readAsStringSync();
      expect(
        updateDialogCode.contains('AppDialog('),
        isTrue,
        reason: 'UpdateDownloadDialog 必须改用 AppDialog 作为外壳',
      );
    });

    test('§10.6 全仓按钮处禁止 shrinkWrap 与 visualDensity.compact', () {
      // 落盘补（DeepSeek 复审 #32）：原只查 5 个文件。现全仓扫描 lib/ 全部 .dart，
      // 但 Chip 徽章（3 处）与 Checkbox（1 处）不是按钮（§10.6 只管按钮控件），
      // 允许保留；判定方法是看命中行往上 15 行内是否出现 Chip(/Checkbox(。
      // SegmentedButton 是按钮控件，已在 settings_sections 里清掉，不得再出现。
      final libDir = Directory('lib');
      final violations = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!line.contains('MaterialTapTargetSize.shrinkWrap') &&
              !line.contains('VisualDensity.compact')) {
            continue;
          }
          final start = i - 15 < 0 ? 0 : i - 15;
          final context = lines.sublist(start, i + 1).join('\n');
          if (context.contains('Chip(') || context.contains('Checkbox(')) {
            continue;
          }
          violations.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '按钮处残留 shrinkWrap/compact：$violations',
      );
    });
  });

  group('WB_SPEC_256 §10 组件与交互验收', () {
    testWidgets('§10.1 & §10.7 详情弹层双键 48dp + 右上角 error 色删除图标',
        (tester) async {
      // 落盘补：默认测试面 800×600 时 modal 弹层只给约 305dp 高，314 高的
      // 详情内容会溢出 8.5px（wb232 同款坑），按手机屏 360×800 测。
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final course = _sampleCourse();
      await tester.pumpWidget(
        _wrapWithTheme(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CourseDetailSheet.show(context, course),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      );
      await _drain(tester);

      await tester.tap(find.text('打开详情'));
      await _drain(tester);

      final addSlotBtn = find.widgetWithText(OutlinedButton, '新增时段');
      final editBtn = find.widgetWithText(FilledButton, '编辑');
      expect(addSlotBtn, findsOneWidget);
      expect(editBtn, findsOneWidget);
      expect(tester.getSize(addSlotBtn).height, equals(48.0));
      expect(tester.getSize(editBtn).height, equals(48.0));

      final deleteIconBtnFinder = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '删除课程',
      );
      expect(deleteIconBtnFinder, findsOneWidget);
      final deleteBtn = tester.widget<IconButton>(deleteIconBtnFinder);
      final scheme =
          Theme.of(tester.element(deleteIconBtnFinder)).colorScheme;
      expect(deleteBtn.color, equals(scheme.error));
      expect(
        tester.getSize(deleteIconBtnFinder).height,
        equals(48.0),
      );
    });

    testWidgets('§10.10 详情弹层删课先关弹层再弹 AppDialog 确认', (tester) async {
      // 落盘补：同 §10.1，手机屏 360×800，防 8.5px 溢出。
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final course = _sampleCourse();
      await tester.pumpWidget(
        _wrapWithTheme(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CourseDetailSheet.show(context, course),
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      );
      await _drain(tester);

      await tester.tap(find.text('打开详情'));
      await _drain(tester);
      expect(find.byType(CourseDetailSheet), findsOneWidget);

      await tester.tap(find.byTooltip('删除课程'));
      await _drain(tester);

      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(CourseDetailSheet), findsNothing);
    });

    testWidgets('§10.10 导出失败先关弹层再弹 AppDialog', (tester) async {
      // 不用再插学期：createSchema 已播种当前学期（id 1），
      // displayWeek/currentSemester 有数据即可；重插会撞 UNIQUE constraint。
      // 导出失败发生在读课程处（_ThrowingCoursesNotifier 抛错），与学期无关。
      await tester.pumpWidget(
        _wrapWithTheme(
          Scaffold(
            body: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showExportBottomSheet(context, ref),
                  child: const Text('打开导出'),
                ),
              ),
            ),
          ),
          overrides: [
            coursesProvider.overrideWith(() => _ThrowingCoursesNotifier()),
          ],
        ),
      );
      await _drain(tester);

      await tester.tap(find.text('打开导出'));
      await _drain(tester);
      expect(find.text('导出整学期完整课表（图片）'), findsOneWidget);

      await tester.tap(find.text('导出整学期完整课表（图片）'));
      await _drain(tester);

      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.text('导出失败'), findsOneWidget);
      expect(find.byType(ExportBottomSheetContent), findsNothing);
    });

    testWidgets('§10.3 设置页无顶栏 ⋮ 菜单且底部有关于小马课表入口行', (tester) async {
      // 落盘补：设置页是 ListView 懒构建，默认 800×600 只建出首屏行，
      // 底部的「关于小马课表」行根本不在树上；按 settings_page_test 同款
      // 高面 1200×4200 一次建全。
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrapWithTheme(const SettingsPage()));
      await _drain(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      expect(find.text('关于小马课表'), findsOneWidget);
    });

    testWidgets('§10.7 周数选择小芯片命中容器 ≥48×48dp 且相邻中心距 ≥48dp',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          Scaffold(
            body: SingleChildScrollView(
              child: WeekPicker(
                initialWeeks: const [1, 2],
                initialWeekType: 0,
                onChanged: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await _drain(tester);

      final chip1 = find.byKey(const ValueKey('week-chip-1'));
      final chip2 = find.byKey(const ValueKey('week-chip-2'));
      expect(chip1, findsOneWidget);
      expect(chip2, findsOneWidget);

      final size1 = tester.getSize(chip1);
      expect(size1.width, greaterThanOrEqualTo(48.0));
      expect(size1.height, greaterThanOrEqualTo(48.0));

      final center1 = tester.getCenter(chip1);
      final center2 = tester.getCenter(chip2);
      expect((center2.dx - center1.dx).abs(), greaterThanOrEqualTo(48.0));
    });

    testWidgets('§10.8 课程编辑页无顶栏保存按钮，底部主按钮 48dp', (tester) async {
      await tester.pumpWidget(_wrapWithTheme(const CourseEditPage()));
      await _drain(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.widgetWithText(TextButton, '保存'),
        ),
        findsNothing,
      );
      final bottomSave = find.widgetWithText(FilledButton, '添加课程');
      expect(bottomSave, findsOneWidget);
      expect(tester.getSize(bottomSave).height, equals(48.0));
    });

    testWidgets('§6.2 保存按钮随键盘顶起（复审 #81）', (tester) async {
      // 落盘补：Scaffold.bottomNavigationBar 不随键盘顶起，
      // AnimatedPadding 随 viewInsets.bottom 把保存按钮顶到键盘上方。
      await tester.pumpWidget(
        _wrapWithTheme(const CourseEditPage()),
      );
      await _drain(tester);
      final saveBtn = find.widgetWithText(FilledButton, '添加课程');
      expect(saveBtn, findsOneWidget);
      final bottomNoKeyboard = tester.getBottomLeft(saveBtn).dy;

      // 模拟键盘弹出 300dp（默认测试面高 600）。
      // 注意：FakeViewPadding 的单位是物理像素，默认 devicePixelRatio 3.0
      // 会把 300 物理像素折成 100 逻辑像素；须把 DPR 置 1.0，同时把
      // physicalSize 也写成 800×600（只改 DPR 不改 physicalSize 的话，
      // 逻辑面会胀成 2400×1800，按钮底边就跑到 1484 去了）。
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await _drain(tester);
      final bottomWithKeyboard = tester.getBottomLeft(saveBtn).dy;
      // 按钮底边应顶到键盘上方（600 - 300 = 300），而不是被键盘盖住。
      expect(bottomWithKeyboard, lessThanOrEqualTo(300.0));
      expect(bottomWithKeyboard, lessThan(bottomNoKeyboard));
    });

    testWidgets('§10.9 底部操作栏按钮高度为 48dp（核对页 / 冲突页 / 选时段弹层）',
        (tester) async {
      final semester = _sampleSemester();
      final courseA = _sampleCourse(id: 1, name: '高数');
      final courseB = _sampleCourse(id: 2, name: '线代');

      // 1. 导入核对页：手动补录 + 确认导入
      await tester.pumpWidget(
        _wrapWithTheme(
          ImportReviewPage(
            drafts: [courseA],
            targetSemester: semester,
          ),
        ),
      );
      await _drain(tester);

      final addDraftBtn = find.widgetWithText(OutlinedButton, '手动补录');
      final confirmImportBtn = find.widgetWithText(FilledButton, '确认导入');
      expect(tester.getSize(addDraftBtn).height, equals(48.0));
      expect(
        tester.getSize(confirmImportBtn).height,
        equals(48.0),
      );

      // 2. 导入冲突页：按此处理并导入 + 顶部批量操作已降级为 TextButton
      final conflict = CourseConflict(
        courseA: courseA,
        courseB: courseB,
        overlapWeeks: const [1, 2],
        overlapSections: const [1, 2],
      );
      await tester.pumpWidget(
        _wrapWithTheme(
          ImportConflictsPage(
            drafts: [courseA],
            items: [
              ImportConflictItem(
                draftIndex: 0,
                conflict: conflict,
                otherIsDraft: false,
                otherDraftIndex: -1,
              ),
            ],
          ),
        ),
      );
      await _drain(tester);

      final batchApplyBtn = find.byType(FilledButton).last;
      expect(tester.getSize(batchApplyBtn).height, equals(48.0));
      expect(find.widgetWithText(TextButton, '全部跳过'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '全部跳过'), findsNothing);

      // 3. 选时段弹层：确认选定
      await tester.pumpWidget(
        _wrapWithTheme(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSelectTimeSheet(
                  context: context,
                  dayOfWeek: 1,
                  startSection: 1,
                  endSection: 2,
                ),
                child: const Text('选时段'),
              ),
            ),
          ),
        ),
      );
      await _drain(tester);

      await tester.tap(find.text('选时段'));
      await _drain(tester);
      final confirmSlotBtn = find.widgetWithText(FilledButton, '确认选定');
      expect(confirmSlotBtn, findsOneWidget);
      expect(
        tester.getSize(confirmSlotBtn).height,
        equals(48.0),
      );
    });

    testWidgets('§10.9 导出页两按钮高度为 48dp（保存到本地 / 分享图片）',
        (tester) async {
      // 落盘补（DeepSeek 复审 #33）：§10.9 的 7 处里导出页两按钮此前无渲染断言。
      // createSchema 已播种一个当前学期（id 1，2026秋）；直接用它挂课，
      // 再插一份 _sampleSemester() 会撞 UNIQUE constraint（id 1 已存在）。
      await tester.runAsync(
        () => Dao.instance.insertCourse(_sampleCourse(semesterId: 1)),
      );
      // 页面高（含周网格 + 底部双按钮），按高面一次建全，免滚动找按钮。
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrapWithTheme(const ShareImagePage()));
      await _drain(tester);

      final saveBtn = find.byKey(const ValueKey('btn_save_week_png'));
      final shareBtn = find.byKey(const ValueKey('btn_share_week_png'));
      expect(saveBtn, findsOneWidget);
      expect(shareBtn, findsOneWidget);
      expect(tester.getSize(saveBtn).height, 48.0);
      expect(tester.getSize(shareBtn).height, 48.0);
    });

    testWidgets('§10.5 UpdateDownloadDialog 使用 AppDialog 外壳', (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          const Scaffold(
            body: UpdateDownloadDialog(
              version: '2.13.0',
              downloadUrl: 'https://example.com/app.apk',
              changelog: '交互与按钮统一',
            ),
          ),
        ),
      );
      await _drain(tester);

      expect(find.byType(AppDialog), findsOneWidget);
      expect(find.byType(AppDialogAction), findsWidgets);
    });

    test('§10.9 全局底部栏按钮样式常量高度为 48dp', () {
      expect(kBottomBarButtonHeight, equals(48.0));
      final filled = appBottomBarFilledButtonStyle();
      final outlined = appBottomBarOutlinedButtonStyle();
      expect(filled.minimumSize?.resolve(<WidgetState>{})?.height, 48.0);
      expect(outlined.minimumSize?.resolve(<WidgetState>{})?.height, 48.0);
      // 保留对 ShareImagePage / ImportPage / _sampleSlots 的编译期引用校验
      expect(ShareImagePage, isNotNull);
      expect(ImportPage, isNotNull);
      expect(_sampleSlots().length, 10);
    });
  });
}
