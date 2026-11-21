import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';
import 'package:xiaoma_timetable/widgets/course_card.dart';

/// WB_SPEC_253 §5：课卡 widget 测试（4 个开关各一正一反）+ 导出图非默认态
/// + 库值不变性断言。
void main() {
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
    TimeSlot(section: 3, startTime: '09:50', endTime: '10:35'),
  ];

  Course markedCourse() => Course(
    semesterId: 1,
    name: '[通识]渔业简史16周⊙',
    classroom: '黑石礁校区獐314',
    teacher: '张老师',
    note: '带教材',
    colorValue: 0xFF7E9BB5,
    dayOfWeek: 1,
    startSection: 1,
    endSection: 2,
    weeks: List.generate(16, (i) => i + 1),
  );

  Widget wrapCard(CourseCard card) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 220, height: 160, child: card)),
    ),
  );

  group('CourseCard 四个显示开关', () {
    testWidgets('默认态：标记/校区/时间/@ 都按默认隐藏', (tester) async {
      final course = markedCourse();
      await tester.pumpWidget(
        wrapCard(
          CourseCard(
            course: course,
            onTap: () {},
            onLongPress: () {},
            timeSlots: slots,
          ),
        ),
      );

      expect(find.textContaining('渔业简史'), findsOneWidget);
      expect(find.textContaining('16周'), findsNothing);
      expect(find.textContaining('⊙'), findsNothing);
      expect(find.textContaining('[通识]'), findsNothing);
      expect(find.textContaining('黑石礁'), findsNothing);
      expect(find.textContaining('獐314'), findsOneWidget);
      expect(find.textContaining('08:00'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
      // 老师与备注不受 253 开关影响，照常显示
      expect(find.textContaining('张老师'), findsOneWidget);
      expect(find.textContaining('带教材'), findsOneWidget);
    });

    testWidgets('四开关翻过来：原样显示课名/校区/@/时间', (tester) async {
      final course = markedCourse();
      await tester.pumpWidget(
        wrapCard(
          CourseCard(
            course: course,
            onTap: () {},
            onLongPress: () {},
            hideNameMarks: false,
            hideCampus: false,
            showCellTime: true,
            showLocationAt: true,
            timeSlots: slots,
          ),
        ),
      );

      expect(find.textContaining('[通识]渔业简史16周⊙'), findsOneWidget);
      expect(find.textContaining('@黑石礁校区獐314'), findsOneWidget);
      expect(find.textContaining('08:00–09:35'), findsOneWidget);
    });

    testWidgets('showCellTime 开但作息为空：静默不显示时间，不崩溃', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapCard(
          CourseCard(
            course: markedCourse(),
            onTap: () {},
            onLongPress: () {},
            showCellTime: true,
            timeSlots: const [],
          ),
        ),
      );

      expect(find.textContaining('08:00'), findsNothing);
      expect(find.textContaining('渔业简史'), findsOneWidget);
    });

    testWidgets('showClassroom 关 + showLocationAt 开：不渲染孤零零的 @', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapCard(
          CourseCard(
            course: markedCourse(),
            onTap: () {},
            onLongPress: () {},
            showClassroom: false,
            showLocationAt: true,
            timeSlots: slots,
          ),
        ),
      );

      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('獐314'), findsNothing);
    });

    testWidgets('库值不变性：开关只改显示，不改 Course 原始数据', (tester) async {
      final course = markedCourse();
      await tester.pumpWidget(
        wrapCard(
          CourseCard(
            course: course,
            onTap: () {},
            onLongPress: () {},
            timeSlots: slots,
          ),
        ),
      );

      expect(course.name, '[通识]渔业简史16周⊙');
      expect(course.classroom, '黑石礁校区獐314');
    });
  });

  group('整学期导出图非默认态（WB_SPEC_253 §5）', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required UiSettings ui,
    }) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semester = Semester(
        id: 1,
        name: '大三下学期',
        startDate: '2026-09-07',
        isCurrent: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemesterSingleImageSheet(
                semester: semester,
                courses: [markedCourse()],
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
    }

    testWidgets('默认态：导出图与课卡同口径隐藏', (tester) async {
      await pumpSheet(tester, ui: const UiSettings());

      expect(find.textContaining('渔业简史'), findsOneWidget);
      expect(find.textContaining('渔业简史16周'), findsNothing);
      expect(find.textContaining('黑石礁'), findsNothing);
      // 格子内时间是「首节开始–末节结束」的组合串，节数栏不会出现
      expect(find.textContaining('08:00–09:30'), findsNothing);
    });

    testWidgets('四开关翻过来：导出图同步显示原样', (tester) async {
      await pumpSheet(
        tester,
        ui: const UiSettings().copyWith(
          hideNameMarks: false,
          hideCampus: false,
          showCellTime: true,
          showLocationAt: true,
        ),
      );

      expect(find.textContaining('[通识]渔业简史16周⊙'), findsOneWidget);
      expect(find.textContaining('@黑石礁校区獐314'), findsOneWidget);
      expect(find.textContaining('08:00–09:30'), findsOneWidget);
    });
  });
}
