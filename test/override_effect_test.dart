import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/ongoing_notice.dart';
import 'package:xiaoma_timetable/utils/override_effect.dart';
import 'package:xiaoma_timetable/utils/reminder_plan.dart';

/// 单次调课纯逻辑测试（阶段五·节假日调课）
///
/// 覆盖：按周应用调课（停课移除/调整替换/其他周不受影响）、
/// 「调」角标集合、与提醒计划及常驻通知文案的联动、落课前冲突检测。
void main() {
  // 2026-09-07 是周一（与 db_helper 默认开学日期一致）
  const semester =
      Semester(name: '默认学期', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
    TimeSlot(section: 3, startTime: '10:00', endTime: '10:45'),
    TimeSlot(section: 4, startTime: '10:55', endTime: '11:40'),
  ];

  Course course({
    int? id,
    String name = '高等数学',
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 2,
    List<int> weeks = const [1, 2, 3],
    String? classroom = 'A101',
  }) =>
      Course(
        id: id,
        semesterId: 1,
        name: name,
        classroom: classroom,
        colorValue: 0xFF6B8E7B,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        weeks: weeks,
      );

  group('effectiveCoursesForWeek', () {
    test('无调课记录时原样返回', () {
      final c = course(id: 1);
      final result = effectiveCoursesForWeek(
          courses: [c], overrides: const [], week: 1);
      expect(result.length, 1);
      expect(result.first.dayOfWeek, 1);
      expect(result.first.classroom, 'A101');
    });

    test('停课仅移除该周，其他周不受影响', () {
      final c = course(id: 1);
      const overrides = [
        CourseOverride(
            courseId: 1, originalWeek: 2, targetWeek: CourseOverride.cancelFlag),
      ];
      // 第 2 周被移除
      expect(
        effectiveCoursesForWeek(
            courses: [c], overrides: overrides, week: 2),
        isEmpty,
      );
      // 第 1、3 周照常
      expect(
        effectiveCoursesForWeek(
            courses: [c], overrides: overrides, week: 1).length,
        1,
      );
      expect(
        effectiveCoursesForWeek(
            courses: [c], overrides: overrides, week: 3).length,
        1,
      );
    });

    test('调整替换为新的星期/节次，周次规律不变', () {
      final c = course(id: 1); // 周一 1-2 节
      const overrides = [
        CourseOverride(
          courseId: 1,
          originalWeek: 2,
          targetWeek: 2,
          targetDayOfWeek: 3,
          targetStartSection: 3,
          targetEndSection: 4,
        ),
      ];
      final result = effectiveCoursesForWeek(
          courses: [c], overrides: overrides, week: 2);
      expect(result.length, 1);
      expect(result.first.dayOfWeek, 3);
      expect(result.first.startSection, 3);
      expect(result.first.endSection, 4);
      // 原课程对象未被修改（copyWith 产生副本）
      expect(c.dayOfWeek, 1);
      // 其他周仍是原时间
      final other = effectiveCoursesForWeek(
          courses: [c], overrides: overrides, week: 1);
      expect(other.first.dayOfWeek, 1);
    });

    test('教室为 null 表示沿用原教室；给了新教室则替换', () {
      final c = course(id: 1, classroom: 'A101');
      const keepRoom = [
        CourseOverride(
          courseId: 1,
          originalWeek: 1,
          targetWeek: 1,
          targetDayOfWeek: 1,
          targetStartSection: 1,
          targetEndSection: 2,
          // targetClassroom 为 null：沿用原教室
        ),
      ];
      expect(
        effectiveCoursesForWeek(courses: [c], overrides: keepRoom, week: 1)
            .first
            .classroom,
        'A101',
      );
      const newRoom = [
        CourseOverride(
          courseId: 1,
          originalWeek: 1,
          targetWeek: 1,
          targetDayOfWeek: 1,
          targetStartSection: 1,
          targetEndSection: 2,
          targetClassroom: 'B203',
        ),
      ];
      expect(
        effectiveCoursesForWeek(courses: [c], overrides: newRoom, week: 1)
            .first
            .classroom,
        'B203',
      );
    });

    test('课程该周本就不上课时 override 无效，忽略', () {
      final c = course(id: 1, weeks: [1]); // 只第 1 周上课
      const overrides = [
        CourseOverride(
            courseId: 1, originalWeek: 2, targetWeek: CourseOverride.cancelFlag),
      ];
      // 第 2 周本来就无课，override 不产生任何效果（课程原样返回，由调用方过滤）
      final result = effectiveCoursesForWeek(
          courses: [c], overrides: overrides, week: 2);
      expect(result.length, 1);
      expect(result.first.weeks, [1]);
    });

    test('草稿课程（id 为空）不受调课影响', () {
      final c = course(); // id 为 null
      const overrides = [
        CourseOverride(
            courseId: 1, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      ];
      expect(
        effectiveCoursesForWeek(courses: [c], overrides: overrides, week: 1)
            .length,
        1,
      );
    });
  });

  group('movedCourseIds / overrideForCourse / describeOverride', () {
    test('movedCourseIds 只含非停课记录', () {
      const overrides = [
        CourseOverride(
            courseId: 1,
            originalWeek: 1,
            targetWeek: 1,
            targetDayOfWeek: 2,
            targetStartSection: 1,
            targetEndSection: 1),
        CourseOverride(
            courseId: 2, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
        CourseOverride(
            courseId: 3,
            originalWeek: 2,
            targetWeek: 2,
            targetDayOfWeek: 2,
            targetStartSection: 1,
            targetEndSection: 1),
      ];
      expect(movedCourseIds(overrides, 1), {1});
      expect(movedCourseIds(overrides, 2), {3});
    });

    test('overrideForCourse 精确匹配课程与周', () {
      const overrides = [
        CourseOverride(
            courseId: 1, originalWeek: 2, targetWeek: CourseOverride.cancelFlag),
      ];
      expect(overrideForCourse(overrides, 1, 2), isNotNull);
      expect(overrideForCourse(overrides, 1, 1), isNull);
      expect(overrideForCourse(overrides, 2, 2), isNull);
    });

    test('describeOverride：停课/调整/无教室省略', () {
      const cancel = CourseOverride(
          courseId: 1, originalWeek: 1, targetWeek: CourseOverride.cancelFlag);
      expect(describeOverride(cancel), '本次停课');
      const move = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 3,
        targetEndSection: 4,
        targetClassroom: 'B203',
      );
      expect(describeOverride(move), '调至 周三 第 3-4 节 B203');
      const moveNoRoom = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 3,
        targetEndSection: 3,
      );
      expect(describeOverride(moveNoRoom), '调至 周三 第 3 节');
    });
  });

  group('提醒计划应用单次调课', () {
    test('停课的那天不再提醒，其他周照常', () {
      final c = course(id: 1); // 周一 1-2 节，weeks 1-3
      const overrides = [
        CourseOverride(
            courseId: 1, originalWeek: 2, targetWeek: CourseOverride.cancelFlag),
      ];
      // 第 2 周周一（2026-09-14）：无提醒
      expect(
        buildDailyReminderPlan(
          date: DateTime(2026, 9, 14),
          semester: semester,
          courses: [c],
          timeSlots: slots,
          advanceMinutes: 15,
          overrides: overrides,
        ),
        isEmpty,
      );
      // 第 3 周周一（2026-09-21）：照常提醒
      expect(
        buildDailyReminderPlan(
          date: DateTime(2026, 9, 21),
          semester: semester,
          courses: [c],
          timeSlots: slots,
          advanceMinutes: 15,
          overrides: overrides,
        ).length,
        1,
      );
    });

    test('调课的按新星期/新节次提醒，文案用新教室', () {
      final c = course(id: 1); // 周一 1-2 节 A101
      const overrides = [
        CourseOverride(
          courseId: 1,
          originalWeek: 2,
          targetWeek: 2,
          targetDayOfWeek: 3, // 调到周三
          targetStartSection: 3,
          targetEndSection: 4,
          targetClassroom: 'B203',
        ),
      ];
      // 原周一（2026-09-14）：不再提醒
      expect(
        buildDailyReminderPlan(
          date: DateTime(2026, 9, 14),
          semester: semester,
          courses: [c],
          timeSlots: slots,
          advanceMinutes: 15,
          overrides: overrides,
        ),
        isEmpty,
      );
      // 新周三（2026-09-16）：按第 3 节 10:00 提醒，教室 B203
      final plans = buildDailyReminderPlan(
        date: DateTime(2026, 9, 16),
        semester: semester,
        courses: [c],
        timeSlots: slots,
        advanceMinutes: 15,
        overrides: overrides,
      );
      expect(plans.length, 1);
      expect(plans.first.courseStart, DateTime(2026, 9, 16, 10, 0));
      expect(plans.first.reminderTime, DateTime(2026, 9, 16, 9, 45));
      expect(
        buildReminderBody(plans.first.course, 15),
        '《高等数学》还有 15 分钟在 B203 上课',
      );
    });
  });

  group('常驻通知应用单次调课', () {
    test('停课的课程从今日列表移除，标题计数同步减少', () {
      final a = course(id: 1, name: '课程A'); // 周一 1-2 节（已停课）
      final b = course(id: 2, name: '课程B', startSection: 3, endSection: 4);
      const overrides = [
        CourseOverride(
            courseId: 1, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      ];
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 10, 30), // 第 1 周周一上午，课程B（3-4 节）未下课
        semester: semester,
        courses: [a, b],
        timeSlots: slots,
        overrides: overrides,
      );
      expect(notice.title, '今日剩余课程（共 1 节）');
      expect(notice.lines.length, 1);
      expect(notice.lines.first, contains('课程B'));
    });

    test('调课的课程按新时间展示', () {
      final a = course(id: 1, name: '课程A'); // 周一 1-2 节 A101
      const overrides = [
        CourseOverride(
          courseId: 1,
          originalWeek: 1,
          targetWeek: 1,
          targetDayOfWeek: 2, // 调到周二
          targetStartSection: 3,
          targetEndSection: 3,
          targetClassroom: 'C305',
        ),
      ];
      // 周一中午：今日无课 → 明日（周二）预告里有课程A，时间 10:00-10:45 教室 C305
      final notice = buildOngoingNotice(
        now: DateTime(2026, 9, 7, 12, 0),
        semester: semester,
        courses: [a],
        timeSlots: slots,
        overrides: overrides,
      );
      expect(notice.title, '明日课程预告（共 1 节）');
      expect(notice.lines, ['10:00-10:45 课程A C305']);
    });
  });

  group('checkOverrideConflicts', () {
    test('调到无人占用的时间：无冲突', () {
      final me = course(id: 1, dayOfWeek: 1, startSection: 1, endSection: 2);
      final other = course(id: 2, dayOfWeek: 2, startSection: 1, endSection: 2);
      const o = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 3,
        targetEndSection: 4,
      );
      expect(
        checkOverrideConflicts(
            course: me,
            override: o,
            allCourses: [me, other],
            allOverrides: const []),
        isEmpty,
      );
    });

    test('调到其他课程正常排课的时段：报冲突', () {
      final me = course(id: 1, dayOfWeek: 1, startSection: 1, endSection: 2);
      final other = course(id: 2, name: '英语', dayOfWeek: 3);
      const o = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 2,
        targetEndSection: 3,
      );
      final conflicts = checkOverrideConflicts(
          course: me,
          override: o,
          allCourses: [me, other],
          allOverrides: const []);
      expect(conflicts.length, 1);
      expect(conflicts.first, contains('英语'));
      expect(conflicts.first, contains('周三'));
    });

    test('端点相接不算冲突（第 2 节结束 vs 第 3 节开始）', () {
      final me = course(id: 1, dayOfWeek: 1);
      final other = course(id: 2, dayOfWeek: 3, startSection: 3, endSection: 4);
      const o = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 1,
        targetEndSection: 2,
      );
      expect(
        checkOverrideConflicts(
            course: me,
            override: o,
            allCourses: [me, other],
            allOverrides: const []),
        isEmpty,
      );
    });

    test('对方该周已停课：原位置不算冲突', () {
      final me = course(id: 1, dayOfWeek: 1);
      final other = course(id: 2, name: '英语', dayOfWeek: 3);
      const cancel = CourseOverride(
          courseId: 2, originalWeek: 1, targetWeek: CourseOverride.cancelFlag);
      const o = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 1,
        targetEndSection: 2,
      );
      expect(
        checkOverrideConflicts(
            course: me,
            override: o,
            allCourses: [me, other],
            allOverrides: const [cancel]),
        isEmpty,
      );
    });

    test('对方已被调走：原位置不算冲突；调到对方新位置才算冲突', () {
      final me = course(id: 1, dayOfWeek: 1);
      final other = course(id: 2, name: '英语', dayOfWeek: 3); // 周三 1-2 节
      // 英语本次调到周四 1-2 节
      const otherMove = CourseOverride(
        courseId: 2,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 4,
        targetStartSection: 1,
        targetEndSection: 2,
      );
      // 我调到英语的旧位置（周三 1-2 节）：不冲突
      const toOldSlot = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 3,
        targetStartSection: 1,
        targetEndSection: 2,
      );
      expect(
        checkOverrideConflicts(
            course: me,
            override: toOldSlot,
            allCourses: [me, other],
            allOverrides: const [otherMove]),
        isEmpty,
      );
      // 我调到英语的新位置（周四 1-2 节）：冲突
      const toNewSlot = CourseOverride(
        courseId: 1,
        originalWeek: 1,
        targetWeek: 1,
        targetDayOfWeek: 4,
        targetStartSection: 1,
        targetEndSection: 2,
      );
      final conflicts = checkOverrideConflicts(
          course: me,
          override: toNewSlot,
          allCourses: [me, other],
          allOverrides: const [otherMove]);
      expect(conflicts.length, 1);
      expect(conflicts.first, contains('单次调整'));
    });

    test('停课类型不需要冲突检测，直接返回空', () {
      final me = course(id: 1);
      const cancel = CourseOverride(
          courseId: 1, originalWeek: 1, targetWeek: CourseOverride.cancelFlag);
      expect(
        checkOverrideConflicts(
            course: me,
            override: cancel,
            allCourses: [me],
            allOverrides: const []),
        isEmpty,
      );
    });
  });
}
