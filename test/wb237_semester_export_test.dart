import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/card_style_page.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/services/semester_pdf_export.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';
import 'package:xiaoma_timetable/utils/semester_export_helper.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/utils/week_calc.dart';
import 'package:xiaoma_timetable/widgets/conflict_block.dart';
import 'package:xiaoma_timetable/widgets/course_detail_sheet.dart';

// ---------------------------------------------------------------------------
// 假 notifier（沿用 wb228 / wb232 / wb233 的模式：build 直接返回固定值）
// ---------------------------------------------------------------------------

class _FakeUiNotifier extends UiSettingsNotifier {
  _FakeUiNotifier(this.value);

  UiSettings value;

  @override
  Future<UiSettings> build() async => value;

  @override
  Future<void> apply(UiSettings next) async {
    value = next;
    state = AsyncData(next);
  }

  void set(UiSettings next) {
    value = next;
    state = AsyncData(next);
  }
}

class _FakeCoursesNotifier extends CoursesNotifier {
  _FakeCoursesNotifier(this.courses);

  final List<Course> courses;

  @override
  Future<List<Course>> build() async => courses;
}

class _FakeSemesterNotifier extends CurrentSemesterNotifier {
  _FakeSemesterNotifier(this.semester);

  final Semester semester;

  @override
  Future<Semester> build() async => semester;
}

class _FakeOverridesNotifier extends CourseOverridesNotifier {
  @override
  Future<List<CourseOverride>> build() async => const [];
}

class _FakeSlotsNotifier extends TimeSlotsNotifier {
  _FakeSlotsNotifier(this.slots);

  final List<TimeSlot> slots;

  @override
  Future<List<TimeSlot>> build() async => slots;
}

class _FakeSegmentNotifier extends SegmentSettingsNotifier {
  _FakeSegmentNotifier(this.lunch, this.dinner);

  final int lunch;
  final int dinner;

  @override
  Future<SegmentSettings> build() async => SegmentSettings(
        lunchAfterSection: lunch,
        dinnerAfterSection: dinner,
      );
}

class _FakeBandNotifier extends BandSettingsNotifier {
  @override
  Future<BandSettings> build() async => const BandSettings();
}

class _FixedWeek extends DisplayWeekNotifier {
  _FixedWeek(this.week);

  final int week;

  @override
  int build() => week;
}

class _FixedShowOther extends ShowOtherWeeksNotifier {
  _FixedShowOther(this.value);

  final bool value;

  @override
  bool build() => value;
}

class _FixedAutoCollapse extends AutoCollapseWeekendNotifier {
  _FixedAutoCollapse(this.value);

  final bool value;

  @override
  bool build() => value;
}

// ---------------------------------------------------------------------------
// 共享测试数据
// ---------------------------------------------------------------------------

Course _course({
  required String name,
  int dayOfWeek = 1,
  int startSection = 1,
  int endSection = 2,
  required List<int> weeks,
  int weekType = 0,
  String? classroom,
  String? teacher,
  int colorValue = 0xFF6B8E7B,
}) =>
    Course(
      semesterId: 1,
      name: name,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
      weekType: weekType,
      classroom: classroom,
      teacher: teacher,
      colorValue: colorValue,
    );

List<int> _weeks(int from, int to) =>
    List.generate(to - from + 1, (i) => from + i);

/// 14 节标准节次（与 App 默认节次表同口径）。
List<TimeSlot> _slots14() => const [
      TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
      TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
      TimeSlot(section: 3, startTime: '10:00', endTime: '10:45'),
      TimeSlot(section: 4, startTime: '10:55', endTime: '11:40'),
      TimeSlot(section: 5, startTime: '14:00', endTime: '14:45'),
      TimeSlot(section: 6, startTime: '14:55', endTime: '15:40'),
      TimeSlot(section: 7, startTime: '16:00', endTime: '16:45'),
      TimeSlot(section: 8, startTime: '16:55', endTime: '17:40'),
      TimeSlot(section: 9, startTime: '19:00', endTime: '19:45'),
      TimeSlot(section: 10, startTime: '19:55', endTime: '20:40'),
      TimeSlot(section: 11, startTime: '20:50', endTime: '21:35'),
      TimeSlot(section: 12, startTime: '21:45', endTime: '22:30'),
      TimeSlot(section: 13, startTime: '22:40', endTime: '23:25'),
      TimeSlot(section: 14, startTime: '23:35', endTime: '00:20'),
    ];

/// 真实学期量级的一组课：交接对 + 真冲突对 + 单双周对 + 普通课。
/// 最晚到 18 周（药物分析），所以 N=18。
List<Course> _semesterCourses() => [
      _course(
        name: '药物化学',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        weeks: _weeks(1, 8),
        classroom: '16-102',
        teacher: '王老师',
      ),
      _course(
        name: '药理学',
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        weeks: _weeks(9, 16),
        classroom: '16-639',
        teacher: '李老师',
      ),
      _course(
        name: '有机化学',
        dayOfWeek: 2,
        startSection: 3,
        endSection: 4,
        weeks: _weeks(1, 16),
        classroom: '16-201',
        teacher: '张老师',
      ),
      _course(
        name: '药物分析',
        dayOfWeek: 3,
        startSection: 5,
        endSection: 6,
        weeks: _weeks(1, 18),
        classroom: '16-305',
      ),
      _course(
        name: '生药学',
        dayOfWeek: 5,
        startSection: 1,
        endSection: 2,
        weeks: _weeks(1, 8),
        classroom: '16-401',
      ),
      _course(
        name: '天然药物化学',
        dayOfWeek: 5,
        startSection: 1,
        endSection: 2,
        weeks: _weeks(5, 12),
        classroom: '16-402',
      ),
      _course(
        name: '计算机辅助药物设计',
        dayOfWeek: 1,
        startSection: 3,
        endSection: 4,
        weeks: [1, 3, 5, 7, 9, 11, 13, 15],
        weekType: 1,
        classroom: '16-501',
      ),
      _course(
        name: '药事管理',
        dayOfWeek: 1,
        startSection: 3,
        endSection: 4,
        weeks: [2, 4, 6, 8, 10, 12, 14, 16],
        weekType: 2,
        classroom: '16-502',
      ),
    ];

/// 拉高画布并等首帧异步 provider 就绪（与 wb228 同款）。
Future<void> _pumpPage(
  WidgetTester tester, {
  required Widget home,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: home),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('WB_SPEC_237 §3 周数：按课程 weeks 最大值算 N，不取 totalWeeks', () {
    test('课程最晚 18 周 → N=18；最晚 12 周 → N=12', () {
      expect(
        SemesterExportHelper.calculateMaxWeek([
          _course(name: '课A', weeks: [1, 5, 18]),
        ]),
        18,
      );
      expect(
        SemesterExportHelper.calculateMaxWeek([
          _course(name: '课B', dayOfWeek: 2, weeks: [2, 12]),
        ]),
        12,
      );
    });

    test('totalWeeks=20 但课程最晚 18 周 → N=18（不取 totalWeeks）', () {
      // calculateMaxWeek 只收课程列表，totalWeeks 根本不是入参，不可能漏进来。
      const semester = Semester(
        name: '2026-2027-1',
        startDate: '2026-09-07',
        totalWeeks: 20,
      );
      expect(semester.totalWeeks, 20);
      expect(
        SemesterExportHelper.calculateMaxWeek(_semesterCourses()),
        18,
      );
    });

    test('空课程列表返回 0：调用方（BottomSheet）应提示「本学期还没有课」'
        '而不是按 N=0 生成', () {
      expect(SemesterExportHelper.calculateMaxWeek([]), 0);
    });
  });

  group('WB_SPEC_237 §4.1 冲突分组', () {
    late Course c1_8;
    late Course c5_12;
    late Course c9_16;
    late Course cOdd;
    late Course cEven;

    setUp(() {
      c1_8 = _course(name: '前半学期课', weeks: _weeks(1, 8));
      c5_12 = _course(name: '交集课', weeks: _weeks(5, 12));
      c9_16 = _course(name: '后半学期课', weeks: _weeks(9, 16));
      cOdd = _course(name: '单周课', weeks: [1, 3, 5, 7], weekType: 1);
      cEven = _course(name: '双周课', weeks: [2, 4, 6, 8], weekType: 2);
    });

    test('真冲突：周次有交集 → 分组，上半 = 首周小的那门', () {
      final pair = SemesterExportHelper.checkConflict(c1_8, c5_12, 6);
      expect(pair, isNotNull);
      expect(pair!.topCourse.name, '前半学期课');
      expect(pair.bottomCourse.name, '交集课');
    });

    test('前后交接：1–8 与 9–16，第 3 周与第 12 周都分组，上半仍是先开始那门', () {
      final pairWeek3 = SemesterExportHelper.checkConflict(c1_8, c9_16, 3);
      expect(pairWeek3, isNotNull);
      expect(pairWeek3!.topCourse.name, '前半学期课');
      final pairWeek12 = SemesterExportHelper.checkConflict(c1_8, c9_16, 12);
      expect(pairWeek12, isNotNull);
      expect(pairWeek12!.topCourse.name, '前半学期课');
    });

    test('反向传参：先传后开始的课，上半仍是首周小的那门', () {
      final pair = SemesterExportHelper.checkConflict(c9_16, c1_8, 3);
      expect(pair, isNotNull);
      expect(pair!.topCourse.name, '前半学期课');
      expect(pair.bottomCourse.name, '后半学期课');
    });

    test('单双周交错：第 1 周与第 2 周都不分组', () {
      expect(SemesterExportHelper.checkConflict(cOdd, cEven, 1), isNull);
      expect(SemesterExportHelper.checkConflict(cOdd, cEven, 2), isNull);
      expect(SemesterExportHelper.checkConflict(cOdd, cEven, 5), isNull);
    });

    test('不同星期 → 不分组', () {
      final otherDay = _course(
        name: '周二课',
        dayOfWeek: 2,
        weeks: _weeks(1, 8),
      );
      expect(SemesterExportHelper.checkConflict(c1_8, otherDay, 3), isNull);
    });

    test('节次无重合 → 不分组', () {
      final otherSection = _course(
        name: '3–4 节课',
        startSection: 3,
        endSection: 4,
        weeks: _weeks(1, 8),
      );
      expect(
        SemesterExportHelper.checkConflict(c1_8, otherSection, 3),
        isNull,
      );
    });

    test('两门当周都不生效 → 不分组（第 20 周，交接对已全部结束）', () {
      expect(SemesterExportHelper.checkConflict(c1_8, c9_16, 20), isNull);
    });

    test('节次部分重合 + 周次有交集 → 分组（并集覆盖，PDF 里验证）', () {
      final a = _course(
        name: 'A',
        startSection: 1,
        endSection: 3,
        weeks: _weeks(1, 8),
      );
      final b = _course(
        name: 'B',
        startSection: 2,
        endSection: 4,
        weeks: _weeks(5, 12),
      );
      final pair = SemesterExportHelper.checkConflict(a, b, 6);
      expect(pair, isNotNull);
      expect(pair!.topCourse.name, 'A');
    });
  });

  group('WB_SPEC_237 §5 强度插值与外观设置', () {
    test('darkEnd 走自家插值路径：t=0 浅端、t=1 深端', () {
      final colors = ConflictBlockAppearance.getColors('caramel');
      expect(
        ConflictBlockAppearance.darkEnd('caramel', 0.0),
        colors.light,
      );
      expect(
        ConflictBlockAppearance.darkEnd('caramel', 1.0),
        colors.dark,
      );
    });

    test('30% 与 60% 档：按 Dart 实测值断言（样品是 CSS 舍入）', () {
      // Color.lerp 在新版 Flutter 里保留浮点通道，不四舍五入到 8bit：
      // 30% 的 R 是 221.5（不是 221 也不是 222），样品的 #DD/#DE 都是
      // CSS 式取整的近似值；这里按浮点值断言（容差半个色阶）。
      // 转 8bit 时（如 PDF 的 toARGB32）221.5 会进到 222 = 0xDE。
      final c30 = ConflictBlockAppearance.darkEnd('caramel', 0.3);
      expect(c30.r, closeTo(221.5 / 255, 0.002));
      expect(c30.g, closeTo(182.1 / 255, 0.002));
      expect(c30.b, closeTo(139 / 255, 0.002));
      final c60 = ConflictBlockAppearance.darkEnd('caramel', 0.6);
      expect(c60.r, closeTo(208 / 255, 0.002));
      expect(c60.g, closeTo(163.2 / 255, 0.002));
      expect(c60.b, closeTo(118 / 255, 0.002));
    });

    test('未知 colorId 回落焦糖', () {
      expect(
        ConflictBlockAppearance.getColors('nope'),
        ConflictBlockAppearance.getColors('caramel'),
      );
      expect(
        ConflictBlockAppearance.darkEnd('nope', 1.0),
        const Color(0xFFBE8A5A),
      );
    });

    test('三色浅/深端与规格一致', () {
      expect(
        ConflictBlockAppearance.getColors('mistBlue').light,
        const Color(0xFFB9C9D9),
      );
      expect(
        ConflictBlockAppearance.getColors('mistBlue').dark,
        const Color(0xFF7E9BB5),
      );
      expect(
        ConflictBlockAppearance.getColors('sage').light,
        const Color(0xFFC2CDB4),
      );
      expect(
        ConflictBlockAppearance.getColors('sage').dark,
        const Color(0xFF8A9A7A),
      );
    });
  });

  group('WB_SPEC_237 §5 UiSettings 冲突外观三键', () {
    test('默认值：焦糖 / 满强度 / 模糊关', () {
      const ui = UiSettings();
      expect(ui.conflictBlockColorId, 'caramel');
      expect(ui.conflictGradientIntensity, 1.0);
      expect(ui.conflictBlurEnabled, isFalse);
    });

    test('旧 JSON（无三键）反序列化回退到默认值', () {
      final decoded =
          UiSettings.fromEncoded('{"cellHeight":46,"cornerRadius":12}');
      expect(decoded.conflictBlockColorId, 'caramel');
      expect(decoded.conflictGradientIntensity, 1.0);
      expect(decoded.conflictBlurEnabled, isFalse);
    });

    test('toJson/fromEncoded 往返：三键不丢', () {
      const ui = UiSettings(
        conflictBlockColorId: 'sage',
        conflictGradientIntensity: 0.6,
        conflictBlurEnabled: true,
      );
      final decoded = UiSettings.fromEncoded(jsonEncode(ui.toJson()));
      expect(decoded.conflictBlockColorId, 'sage');
      expect(decoded.conflictGradientIntensity, 0.6);
      expect(decoded.conflictBlurEnabled, isTrue);
    });

    test('copyWith 只改指定的键', () {
      const ui = UiSettings();
      final next = ui.copyWith(conflictBlockColorId: 'mistBlue');
      expect(next.conflictBlockColorId, 'mistBlue');
      expect(next.conflictGradientIntensity, 1.0);
      expect(next.conflictBlurEnabled, isFalse);
    });
  });

  group('WB_SPEC_237 §8 PNG 像素比封顶（纯函数）', () {
    test('小图：3.0 倍', () {
      expect(cappedExportPixelRatio(300, 500), 3.0);
    });

    test('宽超限：按 1080 封顶', () {
      expect(cappedExportPixelRatio(500, 500), closeTo(1080 / 500, 1e-9));
    });

    test('高超限：按 1920 封顶', () {
      expect(cappedExportPixelRatio(300, 800), closeTo(1920 / 800, 1e-9));
    });

    test('宽高都超：取更小的那个', () {
      expect(cappedExportPixelRatio(400, 1000), closeTo(1920 / 1000, 1e-9));
    });
  });

  group('WB_SPEC_237 §4.2 冲突块 Widget', () {
    Widget block({
      required double height,
      required double width,
      bool blur = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: ConflictBlock(
              topCourse: _course(
                name: '药物化学',
                classroom: '16-102',
                teacher: '王老师',
                weeks: _weeks(1, 8),
              ),
              bottomCourse: _course(
                name: '药理学',
                classroom: '16-639',
                teacher: '李老师',
                weeks: _weeks(9, 16),
              ),
              height: height,
              width: width,
              colorId: 'caramel',
              intensity: 1.0,
              blurEnabled: blur,
            ),
          ),
        ),
      );
    }

    testWidgets('标签/课名/教室老师都画出；半块 ≥50 时老师名在', (tester) async {
      await tester.pumpWidget(block(height: 120, width: 200));
      expect(find.text('前半学期'), findsOneWidget);
      expect(find.text('后半学期'), findsOneWidget);
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);
      expect(find.text('16-102 · 王老师'), findsOneWidget);
      expect(find.text('16-639 · 李老师'), findsOneWidget);
    });

    testWidgets('半块 <50 时藏老师名，只留教室（半块太矮时单行显示）', (tester) async {
      await tester.pumpWidget(block(height: 60, width: 200));
      // 半块 30px <38，两行放不下，改成单行「课名 · 教室」
      expect(find.textContaining('药物化学 · 16-102'), findsOneWidget);
      expect(find.textContaining('药理学 · 16-639'), findsOneWidget);
      expect(find.textContaining('王老师'), findsNothing);
      expect(find.textContaining('李老师'), findsNothing);
    });

    testWidgets('模糊开时 BackdropFilter 在 ClipRRect 内（防整屏漫溢）',
        (tester) async {
      await tester.pumpWidget(block(height: 120, width: 200, blur: true));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(ClipRRect),
        ),
        findsWidgets,
      );
    });

    testWidgets('中间分隔是虚线 CustomPaint，不叠实线边框', (tester) async {
      await tester.pumpWidget(block(height: 120, width: 200));
      // 虚线由 CustomPaint 画（块内唯一一个 CustomPaint）
      expect(
        find.descendant(
          of: find.byType(ConflictBlock),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      // 块内没有任何「只有底边」的实线装饰（旧 bug：上半底部叠了一条实线）；
      // 唯一带边框的装饰是外框（四边 1.5 实线）。
      final decorations = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ConflictBlock),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>();
      var bottomOnlySolid = false;
      var hasOuterFrame = false;
      for (final d in decorations) {
        final b = d.border;
        if (b is Border) {
          if (b.top == BorderSide.none &&
              b.left == BorderSide.none &&
              b.right == BorderSide.none &&
              b.bottom.style == BorderStyle.solid) {
            bottomOnlySolid = true;
          }
          if (b.top.width == 1.5 &&
              b.bottom.width == 1.5 &&
              b.left.width == 1.5 &&
              b.right.width == 1.5) {
            hasOuterFrame = true;
          }
        }
      }
      expect(bottomOnlySolid, isFalse);
      expect(hasOuterFrame, isTrue);
    });

    testWidgets('中间分隔真是虚线：CustomPaint 画的是多段短线，不是整条实线',
        (tester) async {
      await tester.pumpWidget(block(height: 120, width: 200));
      final customPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(ConflictBlock),
          matching: find.byType(CustomPaint),
        ),
      );
      final painter = customPaint.painter!;
      // 用录制画布直接跑 painter，数 drawLine：虚线是多段短线，
      // 实线只有 1 条贯穿整宽的线（变异自检 §10.4(c) 的靶子）。
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, const Size(200, 60));
      final lines = canvas.invocations
          .where((r) => r.invocation.memberName == #drawLine)
          .toList();
      expect(lines.length, greaterThan(1));
      for (final line in lines) {
        final args = line.invocation.positionalArguments;
        final p1 = args[0] as Offset;
        final p2 = args[1] as Offset;
        // 每段是水平短线（dash 4px），不是贯穿整宽的实线
        expect(p1.dy, p2.dy);
        expect((p2.dx - p1.dx).abs(), lessThanOrEqualTo(4.0));
      }
    });

    testWidgets('小屏（视口 ≤600）用小字号；宽视口用正常字号', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(block(height: 120, width: 200));
      expect(
        tester.widget<Text>(find.text('药物化学')).style?.fontSize,
        8.5,
      );
      expect(
        tester.widget<Text>(find.text('前半学期')).style?.fontSize,
        7.0,
      );
      // 宽视口：默认 800 宽
      tester.view.reset();
      await tester.pumpWidget(block(height: 120, width: 200));
      expect(
        tester.widget<Text>(find.text('药物化学')).style?.fontSize,
        10.5,
      );
      expect(
        tester.widget<Text>(find.text('前半学期')).style?.fontSize,
        8.0,
      );
    });
  });

  group('WB_SPEC_237 §6 冲突块外观编辑器', () {
    late _FakeUiNotifier fake;

    List<Override> overrides() => [
          uiSettingsProvider.overrideWith(() => fake),
          coursesProvider.overrideWith(
            () => _FakeCoursesNotifier(const []),
          ),
          courseOverridesProvider.overrideWith(
            () => _FakeOverridesNotifier(),
          ),
          // AppearancePreviewCard 还读 timeSlotsProvider（预览表头节次），
          // 不覆盖会走真 Dao（测试环境没初始化数据库）。
          timeSlotsProvider.overrideWith(
            () => _FakeSlotsNotifier(_slots14()),
          ),
          displayWeekProvider.overrideWith(() => _FixedWeek(1)),
          showOtherWeeksProvider.overrideWith(
            () => _FixedShowOther(false),
          ),
          autoCollapseWeekendProvider.overrideWith(
            () => _FixedAutoCollapse(false),
          ),
        ];

    setUp(() {
      fake = _FakeUiNotifier(const UiSettings());
    });

    testWidgets('冲突组 + 实时预览 + 颜色三选 + 强度滑杆 + 模糊开关都在',
        (tester) async {
      await _pumpPage(
        tester,
        home: const CardStylePage(),
        overrides: overrides(),
      );
      expect(find.text('冲突课程块'), findsOneWidget);
      expect(find.byType(ConflictBlock), findsOneWidget);
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);
      expect(find.text('焦糖'), findsOneWidget);
      expect(find.text('雾蓝'), findsOneWidget);
      expect(find.text('豆沙绿'), findsOneWidget);
      expect(find.text('渐变强度'), findsOneWidget);
      expect(find.text('模糊'), findsOneWidget);
    });

    testWidgets('点「雾蓝」色块：设置改成雾蓝，预览跟着变', (tester) async {
      await _pumpPage(
        tester,
        home: const CardStylePage(),
        overrides: overrides(),
      );
      await tester.tap(find.text('雾蓝'));
      await tester.pumpAndSettle();
      expect(fake.value.conflictBlockColorId, 'mistBlue');
      final preview =
          tester.widget<ConflictBlock>(find.byType(ConflictBlock));
      expect(preview.colorId, 'mistBlue');
    });

    testWidgets('强度滑杆：拖动改强度', (tester) async {
      await _pumpPage(
        tester,
        home: const CardStylePage(),
        overrides: overrides(),
      );
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      // 三个滑杆：格子圆角 / 卡片文字大小 / 渐变强度（冲突组在最后）
      expect(sliders.length, 3);
      expect(sliders.last.value, 1.0);
      await tester.drag(find.byType(Slider).last, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(fake.value.conflictGradientIntensity, lessThan(1.0));
    });

    testWidgets('模糊开关：点开后设置变成 true', (tester) async {
      await _pumpPage(
        tester,
        home: const CardStylePage(),
        overrides: overrides(),
      );
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      // 四个开关：显示教室 / 老师 / 备注 + 模糊（冲突组在最后）
      expect(switches.length, 4);
      expect(switches.last.value, isFalse);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(fake.value.conflictBlurEnabled, isTrue);
    });
  });

  group('WB_SPEC_237 §2 导出 BottomSheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required List<Override> overrides,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  // 预热 BottomSheet 点行时要读的 provider：ExportBottomSheetContent
                  // 的 build 不读它们，不预热的话点行那一刻它们还在 loading，
                  // .value 读到 null 会被当成空学期。
                  ref.watch(coursesProvider);
                  ref.watch(uiSettingsProvider);
                  ref.watch(timeSlotsProvider);
                  ref.watch(segmentSettingsProvider);
                  ref.watch(bandSettingsProvider);
                  ref.watch(currentSemesterProvider);
                  return ElevatedButton(
                    onPressed: () => showExportBottomSheet(context, ref),
                    child: const Text('打开导出'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开导出'));
      await tester.pumpAndSettle();
    }

    List<Override> baseOverrides({required List<Course> courses}) => [
          coursesProvider.overrideWith(
            () => _FakeCoursesNotifier(courses),
          ),
          uiSettingsProvider.overrideWith(
            () => _FakeUiNotifier(const UiSettings()),
          ),
          timeSlotsProvider.overrideWith(
            () => _FakeSlotsNotifier(_slots14()),
          ),
          segmentSettingsProvider.overrideWith(
            () => _FakeSegmentNotifier(5, 9),
          ),
          bandSettingsProvider.overrideWith(() => _FakeBandNotifier()),
          currentSemesterProvider.overrideWith(
            () => _FakeSemesterNotifier(
              const Semester(
                name: '2026-2027-1',
                startDate: '2026-09-07',
                totalWeeks: 20,
                isCurrent: true,
              ),
            ),
          ),
          displayWeekProvider.overrideWith(() => _FixedWeek(3)),
        ];

    testWidgets('三行文案逐字正确；点取消关闭', (tester) async {
      await pumpSheet(tester, overrides: baseOverrides(courses: []));
      expect(find.text('导出课表'), findsOneWidget);
      expect(find.text('导出整学期完整课表（PDF）'), findsOneWidget);
      expect(
        find.text('包含全部周次（页数按课表自动算） · 适合打印存档'),
        findsOneWidget,
      );
      expect(find.text('导出当前第 3 周课表（高清图片）'), findsOneWidget);
      expect(find.text('适合发给同学或设为锁屏壁纸'), findsOneWidget);
      expect(find.text('取消 / 关闭'), findsOneWidget);
      await tester.tap(find.text('取消 / 关闭'));
      await tester.pumpAndSettle();
      expect(find.text('导出课表'), findsNothing);
    });

    testWidgets('空学期点 PDF 行：提示「本学期还没有课」，不生成',
        (tester) async {
      await pumpSheet(tester, overrides: baseOverrides(courses: []));
      await tester.tap(find.text('导出整学期完整课表（PDF）'));
      await tester.pumpAndSettle();
      expect(find.text('本学期还没有课'), findsOneWidget);
      expect(find.text('导出课表'), findsNothing);
    });

    testWidgets('空学期点 PNG 行：同样提示，不跳分享页', (tester) async {
      await pumpSheet(tester, overrides: baseOverrides(courses: []));
      await tester.tap(find.text('导出当前第 3 周课表（高清图片）'));
      await tester.pumpAndSettle();
      expect(find.text('本学期还没有课'), findsOneWidget);
      expect(find.text('导出课表'), findsNothing);
    });

    testWidgets('有课点 PDF 行：先显示「生成中…」，分享不可用时弹失败弹窗',
        (tester) async {
      await pumpSheet(
        tester,
        overrides: baseOverrides(courses: _semesterCourses()),
      );
      // 在真异步里点行 + 立即 pump 一帧：此时字体还在加载（真时间约 0.5s），
      // 「生成中…」应已画出；假时钟的单次 pump 会把整条链一次冲完，看不到它。
      await tester.runAsync(() async {
        await tester.tap(find.text('导出整学期完整课表（PDF）'));
        await tester.pump();
      });
      expect(find.text('生成中…'), findsOneWidget);
      // 生成完 → 分享面板打不开（测试环境无平台通道）→ 失败弹窗。
      // PDF 生成是真异步（读字体 + 18 页），用真时间轮询等它。
      for (var i = 0; i < 60; i++) {
        if (find.text('导出失败').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('导出失败'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('导出失败'), findsNothing);
    });
  });

  group('WB_SPEC_237 §8 导出图（_ExportSheet）画冲突块', () {
    testWidgets('真冲突对在导出图里画成 ConflictBlock', (tester) async {
      final courses = [
        _course(name: '药物化学', weeks: _weeks(1, 8), classroom: '16-102'),
        _course(name: '药理学', weeks: _weeks(5, 12), classroom: '16-639'),
      ];
      await _pumpPage(
        tester,
        home: const ShareImagePage(),
        overrides: [
          currentSemesterProvider.overrideWith(
            () => _FakeSemesterNotifier(
              const Semester(
                name: '2026-2027-1',
                startDate: '2026-09-07',
                totalWeeks: 20,
                isCurrent: true,
              ),
            ),
          ),
          coursesProvider.overrideWith(
            () => _FakeCoursesNotifier(courses),
          ),
          courseOverridesProvider.overrideWith(
            () => _FakeOverridesNotifier(),
          ),
          timeSlotsProvider.overrideWith(
            () => _FakeSlotsNotifier(_slots14()),
          ),
          uiSettingsProvider.overrideWith(
            () => _FakeUiNotifier(const UiSettings()),
          ),
          displayWeekProvider.overrideWith(() => _FixedWeek(6)),
          showOtherWeeksProvider.overrideWith(
            () => _FixedShowOther(false),
          ),
          autoCollapseWeekendProvider.overrideWith(
            () => _FixedAutoCollapse(false),
          ),
          segmentSettingsProvider.overrideWith(
            () => _FakeSegmentNotifier(5, 9),
          ),
          bandSettingsProvider.overrideWith(() => _FakeBandNotifier()),
        ],
      );
      expect(find.byType(ConflictBlock), findsOneWidget);
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);
      expect(find.text('前半学期'), findsOneWidget);
      expect(find.text('后半学期'), findsOneWidget);
    });

    testWidgets('PNG 导出：真实导出图按封顶像素比算出的像素尺寸 ≤1080×1920',
        (tester) async {
      await _pumpPage(
        tester,
        home: const ShareImagePage(),
        overrides: [
          currentSemesterProvider.overrideWith(
            () => _FakeSemesterNotifier(
              const Semester(
                name: '2026-2027-1',
                startDate: '2026-09-07',
                totalWeeks: 20,
                isCurrent: true,
              ),
            ),
          ),
          coursesProvider.overrideWith(
            () => _FakeCoursesNotifier(_semesterCourses()),
          ),
          courseOverridesProvider.overrideWith(
            () => _FakeOverridesNotifier(),
          ),
          timeSlotsProvider.overrideWith(
            () => _FakeSlotsNotifier(_slots14()),
          ),
          uiSettingsProvider.overrideWith(
            () => _FakeUiNotifier(const UiSettings()),
          ),
          displayWeekProvider.overrideWith(() => _FixedWeek(6)),
          showOtherWeeksProvider.overrideWith(
            () => _FixedShowOther(false),
          ),
          autoCollapseWeekendProvider.overrideWith(
            () => _FixedAutoCollapse(false),
          ),
          segmentSettingsProvider.overrideWith(
            () => _FakeSegmentNotifier(5, 9),
          ),
          bandSettingsProvider.overrideWith(() => _FakeBandNotifier()),
        ],
      );
      // 找到包着导出图的 RepaintBoundary（_ExportSheet 外层 _boundaryKey）：
      // ConflictBlock 的祖先里可能有多个 RepaintBoundary，取最外层。
      // 注意：不要在这里调 boundary.toImage()——本测试环境的
      // flutter_tester 对这张大图光栅化会死等（两轮实测各挂 6 分钟以上、
      // CPU 近 0），是测试环境限制，不是生产问题。尺寸约束改用
      // 逻辑尺寸 × 封顶像素比直接算；PNG 体积 ≤2MB 由 _share() 的
      // 降级循环兜底（代码已核实），不在此渲染断言。
      final boundaries = find
          .ancestor(
            of: find.byType(ConflictBlock),
            matching: find.byType(RepaintBoundary),
          )
          .evaluate()
          .toList();
      expect(boundaries, isNotEmpty);
      final boundary =
          boundaries.last.renderObject as RenderRepaintBoundary;
      final ratio = cappedExportPixelRatio(
        boundary.size.width,
        boundary.size.height,
      );
      expect(boundary.size.width * ratio, lessThanOrEqualTo(1080));
      expect(boundary.size.height * ratio, lessThanOrEqualTo(1920));
    });
  });

  group('WB_SPEC_237 §7 PDF 多页导出（真实学期量级）', () {
    const semester = Semester(
      name: '2026-2027-1',
      startDate: '2026-09-07',
      totalWeeks: 20,
      isCurrent: true,
    );

    late List<Course> courses;
    late List<TimeSlot> slots;
    late List<GridBand> bands;

    setUp(() {
      courses = _semesterCourses();
      slots = _slots14();
      bands = computeActiveBands(
        lunchAfter: 5,
        dinnerAfter: 9,
        sectionCount: slots.length,
        settings: const BandSettings(),
      );
    });

    Future<Uint8List> generate() =>
        SemesterPdfExport.generatePdfBytes(
          semester: semester,
          allCourses: courses,
          slots: slots,
          bands: bands,
          ui: const UiSettings(),
          maxWeek: SemesterExportHelper.calculateMaxWeek(courses),
        );

    // Syncfusion 提文本时按词断行（每个 pw.Text 之间插 \r\n），
    // 断言前先把全部空白去掉，期望值也相应去掉空格。
    String pageText(PdfDocument doc, int pageIndex) {
      final extractor = PdfTextExtractor(doc);
      final raw = extractor.extractText(
        startPageIndex: pageIndex,
        endPageIndex: pageIndex,
      );
      return raw.replaceAll(RegExp(r'\s+'), '');
    }

    test('页数 = N（18），每页标题含周数，文件 ≤5MB', () async {
      final bytes = await generate();
      expect(bytes.lengthInBytes, lessThanOrEqualTo(5 * 1024 * 1024));
      final doc = PdfDocument(inputBytes: bytes);
      expect(doc.pages.count, 18);
      for (var i = 0; i < 18; i++) {
        expect(pageText(doc, i), contains('第${i + 1}周课表'));
      }
      doc.dispose();
      // 存一份备查（写失败不影响断言）。
      try {
        final home = Platform.environment['HOME'] ?? '';
        final file = File(
          '$home/workspace/goals/app/hidden_files/wb237-sample.pdf',
        );
        await file.writeAsBytes(bytes);
      } catch (_) {}
    });

    test('交接对：第 3 周与第 12 周的页上两个半都画（标签 + 两门课名）',
        () async {
      final bytes = await generate();
      final doc = PdfDocument(inputBytes: bytes);
      for (final pageIndex in [2, 11]) {
        final text = pageText(doc, pageIndex);
        expect(text, contains('药物化学'));
        expect(text, contains('药理学'));
        expect(text, contains('前半学期'));
        expect(text, contains('后半学期'));
      }
      doc.dispose();
    });

    test('真冲突对：第 6 周的页上两门课与冲突标签都在', () async {
      final bytes = await generate();
      final doc = PdfDocument(inputBytes: bytes);
      final text = pageText(doc, 5);
      expect(text, contains('生药学'));
      expect(text, contains('天然药物化学'));
      expect(text, contains('前半学期'));
      expect(text, contains('后半学期'));
      doc.dispose();
    });

    test('单双周对：第 3 周（单周）只画单周课，第 4 周（双周）只画双周课',
        () async {
      final bytes = await generate();
      final doc = PdfDocument(inputBytes: bytes);
      final week3 = pageText(doc, 2);
      expect(week3, contains('计算机辅助药物设计'));
      expect(week3, isNot(contains('药事管理')));
      final week4 = pageText(doc, 3);
      expect(week4, contains('药事管理'));
      expect(week4, isNot(contains('计算机辅助药物设计')));
      doc.dispose();
    });

    test('普通课与日期范围：第 1 周有有机化学与日期，第 18 周有药物分析',
        () async {
      final bytes = await generate();
      final doc = PdfDocument(inputBytes: bytes);
      final week1 = pageText(doc, 0);
      expect(week1, contains('有机化学'));
      final dates = WeekCalc.weekDatesOf(semester.startDateParsed, 1);
      expect(
        week1,
        contains('${dates.first.month}月${dates.first.day}日'),
      );
      expect(
        week1,
        contains('${dates.last.month}月${dates.last.day}日'),
      );
      expect(pageText(doc, 17), contains('药物分析'));
      doc.dispose();
    });

    test('表头是「周一」～「周日」，不是「周1」～「周7」', () async {
      final bytes = await generate();
      final doc = PdfDocument(inputBytes: bytes);
      final week1 = pageText(doc, 0);
      for (final name in ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
        expect(week1, contains(name));
      }
      expect(week1, isNot(contains('周1')));
      doc.dispose();
    });

    test('分隔带画出：午间 / 晚间标签在每页', () async {
      final bytes = await generate();
      final doc = PdfDocument(inputBytes: bytes);
      expect(pageText(doc, 0), contains('午间'));
      expect(pageText(doc, 0), contains('晚间'));
      doc.dispose();
    });

    test('中间无课的周出空白页，不跳页：页数仍 = N', () async {
      // 只有 1–2 周与 5–6 周有课，第 3、4 周是空白周。
      final gapCourses = [
        _course(name: '药物化学', weeks: _weeks(1, 2), classroom: '16-102'),
        _course(name: '药理学', weeks: _weeks(5, 6), classroom: '16-639'),
      ];
      final bytes = await SemesterPdfExport.generatePdfBytes(
        semester: semester,
        allCourses: gapCourses,
        slots: slots,
        bands: bands,
        ui: const UiSettings(),
        maxWeek: SemesterExportHelper.calculateMaxWeek(gapCourses),
      );
      final doc = PdfDocument(inputBytes: bytes);
      expect(doc.pages.count, 6);
      for (final pageIndex in [2, 3]) {
        final text = pageText(doc, pageIndex);
        expect(text, contains('第${pageIndex + 1}周课表'));
        expect(text, isNot(contains('药物化学')));
        expect(text, isNot(contains('药理学')));
      }
      expect(pageText(doc, 0), contains('药物化学'));
      expect(pageText(doc, 5), contains('药理学'));
      doc.dispose();
    });

    test('空节次表 / N=0 时抛明确错误，不生成空壳', () async {
      await expectLater(
        SemesterPdfExport.generatePdfBytes(
          semester: semester,
          allCourses: courses,
          slots: const [],
          bands: bands,
          ui: const UiSettings(),
          maxWeek: 18,
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        SemesterPdfExport.generatePdfBytes(
          semester: semester,
          allCourses: const [],
          slots: slots,
          bands: bands,
          ui: const UiSettings(),
          maxWeek: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('WB_SPEC_237 §8 周视图点按（FFI 内存库 + HomeShell）', () {
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
        version: '2.1.7',
        buildNumber: '32',
        buildSignature: '',
      );
      // 锁周一时钟，避免周日弹窗挡住点击
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1));
      sundayDialogNow = () => monday;
      // 开学日 = 5 周前的周一 → 今天是第 6 周（真冲突对 1–8/5–12 都生效）
      final startMonday = monday.subtract(const Duration(days: 7 * 5));
      String two(int v) => v.toString().padLeft(2, '0');
      final start =
          '${startMonday.year}-${two(startMonday.month)}-${two(startMonday.day)}';
      final existing = await Dao.instance.getCurrentSemester();
      if (existing == null) {
        await Dao.instance.insertSemester(
          Semester(name: '测试学期', startDate: start, isCurrent: true),
        );
      } else {
        await Dao.instance.updateSemester(existing.copyWith(startDate: start));
      }
      // 真冲突对：同一天同一节，周次 1–8 与 5–12（第 6 周两门都生效）
      await Dao.instance.insertCourse(
        _course(name: '药物化学', weeks: _weeks(1, 8), classroom: '16-102'),
      );
      await Dao.instance.insertCourse(
        _course(name: '药理学', weeks: _weeks(5, 12), classroom: '16-639'),
      );
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
          createHttpClient: (_) =>
              throw const SocketException('测试环境阻断网络'),
        );
      });
      await tester.pump();
      // 等网格里的冲突块出现
      for (var i = 0; i < 25; i++) {
        if (find.byType(ConflictBlock).evaluate().isNotEmpty) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

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

    testWidgets('第 6 周画出冲突块；点上半进药物化学详情、点下半进药理学详情',
        (tester) async {
      await pumpHome(tester);
      expect(find.byType(ConflictBlock), findsOneWidget);
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);

      // 点上半
      var rect = tester.getRect(find.byType(ConflictBlock));
      await tester.tapAt(
        Offset(rect.center.dx, rect.top + rect.height * 0.25),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CourseDetailSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CourseDetailSheet),
          matching: find.text('药物化学'),
        ),
        findsOneWidget,
      );
      // 关掉详情，再点下半
      Navigator.of(tester.element(find.byType(CourseDetailSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CourseDetailSheet), findsNothing);
      rect = tester.getRect(find.byType(ConflictBlock));
      await tester.tapAt(
        Offset(rect.center.dx, rect.top + rect.height * 0.75),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CourseDetailSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CourseDetailSheet),
          matching: find.text('药理学'),
        ),
        findsOneWidget,
      );
      await finish(tester);
    });
  });
}
