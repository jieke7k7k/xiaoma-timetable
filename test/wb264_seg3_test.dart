import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/color_schemes.dart';
import 'package:xiaoma_timetable/utils/ics_export.dart';
import 'package:xiaoma_timetable/utils/ics_parser.dart';
import 'package:xiaoma_timetable/utils/morandi_palette.dart';
import 'package:xiaoma_timetable/utils/override_effect.dart';
import 'package:xiaoma_timetable/utils/reminder_plan.dart';
import 'package:xiaoma_timetable/utils/semester_export_helper.dart';
import 'package:xiaoma_timetable/utils/slot_calibrator.dart';
import 'package:xiaoma_timetable/utils/week_parser.dart';
import 'package:xiaoma_timetable/widgets/week_picker.dart';

/// WB_SPEC_264 第 3 段（§3 逻辑不一致）回归测试
void main() {
  const semester =
      Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
  ];

  Course course({
    int id = 1,
    List<int> weeks = const [1, 2],
    int weekType = 0,
  }) =>
      Course(
        id: id,
        semesterId: 1,
        name: '高数',
        colorValue: 0xFF6B8E7B,
        dayOfWeek: 1,
        startSection: 1,
        endSection: 1,
        weeks: weeks,
        weekType: weekType,
      );

  group('S2-3 ICS 导出应用调课', () {
    test('停课的周不导出', () {
      final res = IcsExporter.build(
        semester: semester,
        courses: [course()],
        slots: slots,
        overrides: const [
          CourseOverride(
            courseId: 1,
            originalWeek: 2,
            targetWeek: CourseOverride.cancelFlag,
          ),
        ],
        now: DateTime(2026, 9, 7),
      );
      expect(res.eventCount, 1);
      expect(res.content.contains('-w2-'), isFalse);
      // M16（DeepSeek 264 复审 B 段）：UID 片段断言依赖 UID 格式，改断具体日期——
      // 第 1 周周一第 1 节 2026-09-07 08:00 应出现，第 2 周同课次 2026-09-14 不应出现
      expect(res.content.contains('DTSTART:20260907T080000'), isTrue);
      expect(res.content.contains('DTSTART:20260914T080000'), isFalse);
    });

    test('调课按新星期/节次导出', () {
      final res = IcsExporter.build(
        semester: semester,
        courses: [course()],
        slots: slots,
        overrides: const [
          CourseOverride(
            courseId: 1,
            originalWeek: 1,
            targetWeek: 1,
            targetDayOfWeek: 3,
            targetStartSection: 2,
            targetEndSection: 2,
          ),
        ],
        now: DateTime(2026, 9, 7),
      );
      expect(res.eventCount, 2);
      // 第 1 周调到周三第 2 节：2026-09-09 08:50
      expect(res.content.contains('DTSTART:20260909T085000'), isTrue);
    });

    test('转义先归一化换行', () {
      final res = IcsExporter.build(
        semester: semester,
        courses: [
          course().copyWith(note: '第一行\r\n第二行\rmore'),
        ],
        slots: slots,
        now: DateTime(2026, 9, 7),
      );
      expect(res.content.contains('\\r'), isFalse);
      expect(res.content.contains('第一行\\n第二行\\nmore'), isTrue);
    });
  });

  group('S2-4 提醒计划超周早退', () {
    test('超出总周数不排提醒', () {
      // M2（DeepSeek 264 复审 B 段）：旧用例的课程只在 1-3 周活跃，
      // 第 21 周时即使删掉早退也不会排提醒，假阴性；改成第 21 周活跃，
      // 旧实现会排、新实现不排，才算咬住早退
      final plans = buildDailyReminderPlan(
        date: DateTime(2027, 1, 25),
        semester: semester,
        courses: [course(weeks: const [21])],
        timeSlots: slots,
        advanceMinutes: 10,
      );
      expect(plans, isEmpty);
    });

    test('学期内正常排提醒', () {
      final plans = buildDailyReminderPlan(
        date: DateTime(2026, 9, 7),
        semester: semester,
        courses: [course()],
        timeSlots: slots,
        advanceMinutes: 10,
      );
      expect(plans.length, 1);
    });
  });

  group('S2-5 周次胶囊', () {
    test('纯单周不再简化成 1-7周而是 1-7单周', () {
      expect(
        SemesterExportHelper.formatWeekCapsule(
          course(weeks: const [1, 3, 5, 7], weekType: 1),
        ),
        '1-7单周',
      );
    });

    test('单周仅剩 1 周不再出 3-3单周', () {
      expect(
        SemesterExportHelper.formatWeekCapsule(
          course(weeks: const [3], weekType: 1),
        ),
        '第3周',
      );
    });

    test('非连续周次按实际区间分段', () {
      expect(
        SemesterExportHelper.formatWeekCapsule(
          course(weeks: const [1, 2, 4, 5]),
        ),
        '1-2, 4-5周',
      );
    });

    test('checkConflict 指定周两门都不活跃返回 null', () {
      final a = course(id: 1, weeks: const [1]);
      final b = course(id: 2, weeks: const [2]);
      expect(SemesterExportHelper.checkConflict(a, b, 3), isNull);
    });
  });

  group('S2-6 显示色统一入口', () {
    test('莫兰迪色按方案映射，浅色下不变', () {
      final stored = MorandiPalette.colors.first;
      final scheme = kCourseColorSchemes[1]; // macaron
      expect(
        resolveCourseDisplayColor(stored, scheme, Brightness.light),
        Color(scheme.colors.first),
      );
    });

    test('深色下降饱和，与浅色结果不同', () {
      final stored = MorandiPalette.colors.first;
      final scheme = kCourseColorSchemes[1];
      final light =
          resolveCourseDisplayColor(stored, scheme, Brightness.light);
      final dark = resolveCourseDisplayColor(stored, scheme, Brightness.dark);
      expect(dark, isNot(light));
    });

    test('自定义色原样返回', () {
      const custom = 0xFF123456;
      expect(
        resolveCourseDisplayColor(
          custom,
          kCourseColorSchemes[1],
          Brightness.light,
        ),
        const Color(custom),
      );
    });
  });

  group('S2-8 调课冲突第 2 步跳过非活跃课', () {
    // M8（DeepSeek 264 复审 B 段）：规格要求第 2 步遍历同周调课时同步检查
    // other.isActiveInWeek(week)；旧实现会把非活跃课的调课目标也算成冲突
    Course movedCourse({
      required int id,
      required List<int> weeks,
      int dayOfWeek = 1,
      int startSection = 1,
      int endSection = 2,
    }) =>
        Course(
          id: id,
          semesterId: 1,
          name: '课$id',
          colorValue: 0xFF6B8E7B,
          dayOfWeek: dayOfWeek,
          startSection: startSection,
          endSection: endSection,
          weeks: weeks,
        );

    test('对方课该周不上课时，其调课目标不算冲突', () {
      final a = movedCourse(id: 1, weeks: const [1]);
      final b = movedCourse(id: 2, weeks: const [2]); // 第 1 周非活跃
      final conflicts = checkOverrideConflicts(
        course: a,
        override: const CourseOverride(
          courseId: 1,
          originalWeek: 1,
          targetWeek: 1,
          targetDayOfWeek: 1,
          targetStartSection: 3,
          targetEndSection: 4,
        ),
        allCourses: [a, b],
        allOverrides: const [
          CourseOverride(
            courseId: 2,
            originalWeek: 1,
            targetWeek: 1,
            targetDayOfWeek: 1,
            targetStartSection: 3,
            targetEndSection: 4,
          ),
        ],
      );
      expect(conflicts, isEmpty);
    });

    test('对方课该周活跃时，同目标时段照常报冲突（正对照）', () {
      final a = movedCourse(id: 1, weeks: const [1]);
      final b = movedCourse(id: 2, weeks: const [1]); // 第 1 周活跃
      final conflicts = checkOverrideConflicts(
        course: a,
        override: const CourseOverride(
          courseId: 1,
          originalWeek: 1,
          targetWeek: 1,
          targetDayOfWeek: 1,
          targetStartSection: 3,
          targetEndSection: 4,
        ),
        allCourses: [a, b],
        allOverrides: const [
          CourseOverride(
            courseId: 2,
            originalWeek: 1,
            targetWeek: 1,
            targetDayOfWeek: 1,
            targetStartSection: 3,
            targetEndSection: 4,
          ),
        ],
      );
      expect(conflicts, isNotEmpty);
    });
  });

  group('S2-9 周次选择器初始化过滤', () {
    testWidgets('单周标记传入时只留单周且 weekType 归一化', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSemesterProvider.overrideWith(() => _FixedCurrent()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WeekPicker(
                initialWeeks: const [1, 2, 3, 4],
                initialWeekType: WeekParser.oddWeek,
                onChanged: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '1, 3');
      // 再点选第 2 周：weekType 已归一化为 allWeeks，文本应为 1-3 而非 1-3 单周
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(field.controller?.text, '1-3');
    });
  });

  group('S2-10 校准不再产出零时长节次', () {
    test('23:59–23:59 被钳成 23:58–23:59', () {
      final out = SlotCalibrator.calibrate(
        const [TimeSlot(section: 1, startTime: '08:00', endTime: '08:45')],
        const [
          IcsTimeBlock(
            startSection: 1,
            endSection: 1,
            startTime: '23:59',
            endTime: '23:59',
          ),
        ],
      );
      expect(out.first.startTime, '23:58');
      expect(out.first.endTime, '23:59');
    });
  });
}

class _FixedCurrent extends CurrentSemesterNotifier {
  @override
  Future<Semester> build() async =>
      const Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
}
