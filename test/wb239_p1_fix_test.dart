import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';
import 'package:xiaoma_timetable/utils/semester_export_helper.dart';
import 'package:xiaoma_timetable/widgets/conflict_block.dart';

/// DeepSeek 复审提交 38e2c27 的 5 条 P1 修复测试（WB_SPEC_238/239/240）。
void main() {
  group('P1 修复测试', () {
    List<int> weeks(int from, int to) =>
        List.generate(to - from + 1, (i) => i + from);

    Course course({
      required String name,
      int day = 1,
      int start = 1,
      int end = 2,
      List<int>? weeksList,
      int weekType = 0,
      String? classroom,
      String? teacher,
    }) {
      return Course(
        semesterId: 1,
        name: name,
        classroom: classroom,
        teacher: teacher,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: day,
        startSection: start,
        endSection: end,
        weeks: weeksList ?? weeks(1, 16),
        weekType: weekType,
      );
    }

    Semester semester() => Semester(
      id: 1,
      name: '大三下学期',
      startDate: '2026-09-07',
      isCurrent: true,
    );

    List<GridBand> bands() => computeActiveBands(
      lunchAfter: 5,
      dinnerAfter: 9,
      sectionCount: 14,
      settings: const BandSettings(),
    );

    Future<void> pumpSheet(
      WidgetTester tester, {
      required List<Course> courses,
    }) async {
      // 真机视口（390×844 @3.0）：ConflictBlock 按视口宽判小屏字号。
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemesterSingleImageSheet(
                semester: semester(),
                courses: courses,
                slots: defaultTimeSlots,
                bands: bands(),
                ui: const UiSettings(),
                displayDays: const [1, 2, 3, 4, 5, 6, 7],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// 课名所在卡片根容器的 finder（卡片根 Container 带 BoxDecoration；
    /// 祖先链里只有这一个带 BoxDecoration 的 Container）。
    /// WB_SPEC_243 起课卡改用 Text.rich（课名+教室+老师同一段富文本），
    /// find.text(课名) 精确匹配不到，改按富文本首行 == 课名找。
    Finder cardBoxOf(String courseName) => find.ancestor(
      of: find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().split('\n').first == courseName,
      ),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      ),
    );

    test('P1-1 同格 3 门课不丢课：stack 布局保留全部 3 门', () {
      final courses = [
        course(name: '药物化学', weeksList: weeks(1, 8)),
        course(name: '药理学', weeksList: weeks(9, 16)),
        course(name: '生物药剂学', weeksList: weeks(1, 16), weekType: 1),
      ];
      final slots = SemesterExportHelper.layoutSemesterMasterDay(
        dayCourses: courses,
        dayOfWeek: 1,
        maxSection: 14,
      );
      expect(slots.length, 1);
      expect(slots[0].kind, SemesterMasterSlotKind.stack);
      expect(slots[0].courses.length, 3);
      expect(
        slots[0].courses.map((c) => c.name),
        containsAll(['药物化学', '药理学', '生物药剂学']),
      );
    });

    testWidgets('P1-1 同格 3 门课：单图里 3 门课名都画出来', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          course(name: '药物化学', weeksList: weeks(1, 8)),
          course(name: '药理学', weeksList: weeks(9, 16)),
          course(name: '生物药剂学', weeksList: weeks(1, 16), weekType: 1),
        ],
      );
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);
      expect(find.text('生物药剂学'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-2 整学期单图导出尺寸为 1080×1920', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));

      final courses = [
        course(name: '药物化学', weeksList: weeks(1, 18)),
        course(name: '药剂学', day: 2, start: 3, end: 4, weeksList: weeks(1, 18)),
      ];
      late Uint8List bytes;
      await tester.runAsync(() async {
        final fut = generateAndShareSemesterSinglePng(
          context: context,
          semester: semester(),
          courses: courses,
          slots: defaultTimeSlots,
          bands: bands(),
          uiSettings: const UiSettings(),
          invokeShare: false,
        );
        await tester.pump();
        bytes = await fut;
      });
      await tester.pump();

      late ui.Image img;
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(bytes);
        img = (await codec.getNextFrame()).image;
      });
      expect(img.width, 1080);
      expect(img.height, 1920);
      img.dispose();
    });

    testWidgets('P1-3 跨带课程卡片高度含分隔带：5–6 节卡高 94dp', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          course(
            name: '跨带课程',
            start: 5,
            end: 6,
            classroom: '16-102',
            weeksList: weeks(1, 16),
          ),
        ],
      );
      // 5–6 节跨午间带（after=5）：topOf(7) - topOf(5) - 2 = 240 - 144 - 2
      //（WB_SPEC_244：带高由 20dp 改为 kBandHeight = 24dp，卡高 90→94）。
      expect(cardBoxOf('跨带课程'), findsOneWidget);
      expect(tester.getSize(cardBoxOf('跨带课程')).height, 94.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-3 跨带冲突块高度含分隔带：5–6 节冲突块高 94dp', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          course(name: '前半课', start: 5, end: 6, weeksList: weeks(1, 8)),
          course(name: '后半课', start: 5, end: 6, weeksList: weeks(9, 16)),
        ],
      );
      expect(find.byType(ConflictBlock), findsOneWidget);
      expect(cardBoxOf('前半课'), findsOneWidget);
      expect(tester.getSize(cardBoxOf('前半课')).height, 94.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-4 单节带教室/老师的卡不溢出', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          course(
            name: '单节课',
            start: 1,
            end: 1,
            classroom: '16-102',
            teacher: '张老师',
            weeksList: weeks(1, 16),
          ),
        ],
      );
      expect(find.text('单节课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-4 单双周半格卡带教室不溢出', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          course(
            name: '单周课',
            start: 3,
            end: 4,
            classroom: '16-201',
            weeksList: weeks(1, 16),
            weekType: 1,
          ),
          course(
            name: '双周课',
            start: 3,
            end: 4,
            classroom: '机房3',
            weeksList: weeks(1, 16),
            weekType: 2,
          ),
        ],
      );
      expect(find.text('单周课'), findsOneWidget);
      expect(find.text('双周课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('P1-4 三门同格叠排卡不溢出', (tester) async {
      await pumpSheet(
        tester,
        courses: [
          course(name: '药物化学', classroom: '16-102', weeksList: weeks(1, 8)),
          course(name: '药理学', classroom: '16-639', weeksList: weeks(9, 16)),
          course(
            name: '生物药剂学',
            classroom: '16-201',
            weeksList: weeks(1, 16),
            weekType: 1,
          ),
        ],
      );
      expect(find.text('药物化学'), findsOneWidget);
      expect(find.text('药理学'), findsOneWidget);
      expect(find.text('生物药剂学'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('P1-5 renderWithinLimit 降到 1.0 仍超限时返回最后一次结果（调用方必须复核）', () async {
      final result = await renderWithinLimit((ratio) async {
        return Uint8List(3 * 1024 * 1024);
      }, 3.0);
      expect(result, isNotNull);
      // 仍超限：调用方不得直接分享，须用 isWithinPngLimit 复核后抛错。
      expect(result!.lengthInBytes, greaterThan(kMaxPngBytes));
      expect(isWithinPngLimit(result), isFalse);
    });

    test('P1-5 isWithinPngLimit：2MB 内通过、超 2MB 拒绝', () {
      expect(isWithinPngLimit(Uint8List(2 * 1024 * 1024)), isTrue);
      expect(isWithinPngLimit(Uint8List(2 * 1024 * 1024 + 1)), isFalse);
      expect(isWithinPngLimit(Uint8List(100)), isTrue);
    });
  });
}
