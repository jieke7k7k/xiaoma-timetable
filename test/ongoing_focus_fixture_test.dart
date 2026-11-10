import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/next_class.dart';
import 'package:xiaoma_timetable/utils/ongoing_boundary.dart';
import 'package:xiaoma_timetable/utils/ongoing_notice.dart';

/// 今日课程常驻通知的共享夹具测试（WB_SPEC_229 第 4.4 节）
///
/// 夹具文件 test/fixtures/ongoing_focus_cases.json 是**唯一事实来源**：
/// Dart 侧（本文件）与 Kotlin 侧（android/app/src/test/.../OngoingFocusCalculatorTest.kt）
/// 读同一份输入、断言同一份 expected。谁改了文案或焦点规则，另一边的测试立刻红——
/// 这是「App 被杀后原生算出来的通知与 App 内说法逐字一致」的硬门槛。
///
/// 覆盖：上课中 / 课间 / 午休 / 晚上 / 周末 / 假期 / 停课当天 / 调课当天 /
/// 单周 / 双周 / 学期外（开学前 + 学期已结束）/ 课表为空 / 当天最后一节。
void main() {
  final fixture = _Fixture.load();

  group('共享夹具：文案与边界点（与 Kotlin 侧逐字等价）', () {
    for (final c in fixture.cases) {
      test(c.name, () {
        final notice = buildOngoingNotice(
          now: c.now,
          semester: fixture.semester,
          courses: c.courses ?? fixture.courses,
          timeSlots: fixture.timeSlots,
          overrides: fixture.overrides,
        );
        expect(notice.title, c.expectedTitle);
        expect(notice.lines, c.expectedLines);
        // 边界点：原生闹钟下一次唤醒的时刻，晚一分钟就会晚一分钟翻页
        final focus = computeClassFocus(
          now: c.now,
          semester: fixture.semester,
          courses: c.courses ?? fixture.courses,
          timeSlots: fixture.timeSlots,
          overrides: fixture.overrides,
        );
        expect(
          _fmt(computeNextBoundary(now: c.now, focus: focus)),
          c.expectedBoundary,
        );
      });
    }
  });

  group('边界点兜底', () {
    test('时钟跳变导致算出的边界点不晚于 now 时，退回次日 00:05', () {
      final now = DateTime(2026, 9, 7, 8, 20);
      // 构造一个「已经结束」的焦点：end 早于 now（脏数据 / 系统时间被改）
      final focus = ClassFocus(
        current: ClassSession(
          course: fixture.courses.first,
          date: DateTime(2026, 9, 7),
          start: DateTime(2026, 9, 7, 7, 0),
          end: DateTime(2026, 9, 7, 7, 40),
        ),
      );
      expect(computeNextBoundary(now: now, focus: focus),
          DateTime(2026, 9, 8, 0, 5));
    });

    test('跨月次日 00:05 的日期进位正确', () {
      final now = DateTime(2026, 9, 30, 22, 0);
      expect(
        computeNextBoundary(now: now, focus: const ClassFocus()),
        DateTime(2026, 10, 1, 0, 5),
      );
    });
  });
}

/// 'yyyy-MM-dd HH:mm'（东八区墙上时间）
String _fmt(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

class _Case {
  _Case({
    required this.name,
    required this.now,
    required this.expectedTitle,
    required this.expectedLines,
    required this.expectedBoundary,
    this.courses,
  });

  final String name;
  final DateTime now;
  final String expectedTitle;
  final List<String> expectedLines;
  final String expectedBoundary;

  /// 部分 case（课表为空 / 只有一门课）用自己的一套课程覆盖默认课程表
  final List<Course>? courses;
}

class _Fixture {
  _Fixture({
    required this.semester,
    required this.timeSlots,
    required this.courses,
    required this.overrides,
    required this.cases,
  });

  final Semester semester;
  final List<TimeSlot> timeSlots;
  final List<Course> courses;
  final List<CourseOverride> overrides;
  final List<_Case> cases;

  /// 从仓库根目录读夹具（flutter test 的工作目录恒为包根）
  static _Fixture load() {
    final raw =
        File('test/fixtures/ongoing_focus_cases.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final s = json['semester'] as Map<String, dynamic>;
    return _Fixture(
      semester: Semester(
        name: s['name'] as String,
        startDate: s['startDate'] as String,
        totalWeeks: s['totalWeeks'] as int,
      ),
      timeSlots: [
        for (final t in json['timeSlots'] as List)
          TimeSlot(
            section: t['section'] as int,
            startTime: t['startTime'] as String,
            endTime: t['endTime'] as String,
          ),
      ],
      courses: _coursesOf(json['courses'] as List),
      overrides: [
        for (final o in json['overrides'] as List)
          CourseOverride(
            courseId: o['courseId'] as int,
            originalWeek: o['originalWeek'] as int,
            targetWeek: o['targetWeek'] as int,
            targetDayOfWeek: o['targetDayOfWeek'] as int?,
            targetStartSection: o['targetStartSection'] as int?,
            targetEndSection: o['targetEndSection'] as int?,
            targetClassroom: o['targetClassroom'] as String?,
          ),
      ],
      cases: [
        for (final c in json['cases'] as List)
          _Case(
            name: c['name'] as String,
            now: DateTime.parse(c['now'] as String),
            expectedTitle: c['expected']['title'] as String,
            expectedLines:
                (c['expected']['lines'] as List).cast<String>().toList(),
            expectedBoundary: c['expected']['boundary'] as String,
            courses: c['courses'] == null
                ? null
                : _coursesOf(c['courses'] as List),
          ),
      ],
    );
  }

  static List<Course> _coursesOf(List list) => [
        for (final c in list)
          Course(
            id: c['id'] as int?,
            semesterId: 1,
            name: c['name'] as String,
            classroom: c['classroom'] as String?,
            colorValue: 0xFF6B8E7B,
            dayOfWeek: c['dayOfWeek'] as int,
            startSection: c['startSection'] as int,
            endSection: c['endSection'] as int,
            weeks: (c['weeks'] as List).cast<int>(),
            weekType: c['weekType'] as int,
          ),
      ];
}
