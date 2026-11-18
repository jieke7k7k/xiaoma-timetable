import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';

/// WB_SPEC_244：整学期导出图按图2（本周导出图）效果对齐
///
/// §2：课卡对齐 CourseCard（描边、Morandi 文字色、分档字号、行数上限 8；
/// 高档按高度预算，低档守 P0-1 公式保 52dp 半格 3 行）。
/// §3：补网格线（通栏横线 + 纵向分段列线，与 _ExportSheet 同口径）。
/// §4：表头 surfaceContainerLow 底条 + 带子改 kBandHeight = 24dp。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<Course> courses,
    UiSettings ui = const UiSettings(),
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SemesterSingleImageSheet(
              semester: Semester(
                id: 1,
                name: '大三下学期',
                startDate: '2026-09-07',
                isCurrent: true,
              ),
              courses: courses,
              slots: defaultTimeSlots,
              bands: computeActiveBands(
                lunchAfter: 5,
                dinnerAfter: 9,
                sectionCount: 14,
                settings: const BandSettings(),
              ),
              ui: ui,
              displayDays: const [1, 2, 3, 4, 5, 6, 7],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cardRichText(String plainText) => find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(plainText),
      );

  group('WB_SPEC_244 §2 课卡对齐 CourseCard', () {
    testWidgets('144dp 长教室卡：maxLines == 8，课名/教室/老师全在文本里，且有描边',
        (tester) async {
      await pumpSheet(
        tester,
        courses: [
          Course(
            semesterId: 1,
            name: '药物分析实验',
            classroom: '12-分析化学实验室（二）',
            teacher: '王老师',
            colorValue: 0xFFD8EAD3,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 4, // 4 节高 144dp
            weeks: List.generate(16, (i) => i + 1),
          ),
        ],
        // 图2 有描边：他设置里 borderWidth > 0，默认 0 测不到描边。
        ui: const UiSettings(borderWidth: 1.0),
      );

      final rich = cardRichText('药物分析实验\n12-分析化学实验室（二）\n王老师');
      expect(rich, findsOneWidget);
      expect(tester.widget<RichText>(rich).maxLines, 8);
      // P1-3 复审：高度才是可见行数的代理——8 行实高约 97dp（名 3 行×13.8
      // + 教室 5 行×11）。若预算退回 4 行，高度只剩约 50dp。
      // 注意：didExceedMaxLines 在此不可用——测试字体里数字按 1em 排，
      // 教室在测试字体下要 5 行、整卡要 9 行，必然超 8 行；真机数字约 0.5em，
      // 同样内容只要 8 行（名 3 + 教室 4 + 老师 1），正好放满。
      expect(tester.getSize(rich).height, greaterThan(90.0));

      // 描边：课卡 Container 的 decoration 带 Border。
      final card = find.ancestor(
        of: rich,
        matching: find.byType(Container),
      ).first;
      final decoration = tester.widget<Container>(card).decoration;
      expect(decoration, isA<BoxDecoration>());
      expect((decoration as BoxDecoration).border, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('52dp 单双周半格仍 3 行（P0-1 公式不动）', (tester) async {
      await pumpSheet(
        tester,
        courses: [
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
        ],
      );

      // 1–3 节共 106dp，两门各分 52.25dp；低档守 P0-1 公式仍给 3 行。
      // 实高 33.25dp 正好是 3 行（名 12 + 教室/老师各 10.03，测试字体
      // 下略有取整）；上限 38 钉死 3 行——预算退回 2 行只剩约 22dp，
      // 放宽到 4 行会到约 42dp。didExceedMaxLines 在此不可用，见上条注释。
      for (final name in ['单周课', '双周课']) {
        final rich = cardRichText('$name\n16-204\n林老师');
        expect(rich, findsOneWidget);
        expect(tester.widget<RichText>(rich).maxLines, 3);
        expect(tester.getSize(rich).height, greaterThan(30.0));
        expect(tester.getSize(rich).height, lessThan(38.0));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('WB_SPEC_244 §3 网格线', () {
    testWidgets('通栏横线与纵向分段列线都在树里', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          Course(
            semesterId: 1,
            name: '药剂学',
            classroom: '16-204',
            teacher: '林老师',
            colorValue: 0xFFD8EAD3,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            weeks: List.generate(16, (i) => i + 1),
          ),
        ],
      );

      // 横线：defaultTimeSlots 共 13 节，12 条节底线 + 2 条带底线 = 14。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Positioned &&
              w.child is ColoredBox &&
              w.height == 0.5,
        ),
        findsNWidgets(14),
      );
      // 纵线：13 节 × 8 列（c <= 7，含最右边缘线）= 104。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Positioned &&
              w.child is ColoredBox &&
              w.width == 0.5,
        ),
        findsNWidgets(104),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('WB_SPEC_244 §4 表头与带子', () {
    testWidgets('分隔带高 24dp，轴列仍写午间/晚间', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          Course(
            semesterId: 1,
            name: '药剂学',
            classroom: '16-204',
            teacher: '林老师',
            colorValue: 0xFFD8EAD3,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            weeks: List.generate(16, (i) => i + 1),
          ),
        ],
      );

      // 两条带（午间/晚间）的 Positioned 高都是 24dp。
      expect(
        find.byWidgetPredicate(
          (w) => w is Positioned && w.height == 24.0,
        ),
        findsNWidgets(2),
      );
      expect(find.text('午间'), findsOneWidget);
      expect(find.text('晚间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
