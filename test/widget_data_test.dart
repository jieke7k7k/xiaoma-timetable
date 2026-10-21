import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/utils/color_schemes.dart';
import 'package:xiaoma_timetable/utils/morandi_palette.dart';
import 'package:xiaoma_timetable/utils/widget_data.dart';

/// 桌面小部件数据（1.2.2 列表式改版）：今日剩余课 → 列表行；
/// 今天没课换明天；最多 4 行 + 尾注；颜色按配色方案映射。
void main() {
  // 2026-09-07 是周一，第 1 周
  const semester =
      Semester(name: '大三上', startDate: '2026-09-07', totalWeeks: 20);
  const slots = [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '09:40', endTime: '12:00'),
    TimeSlot(section: 3, startTime: '14:00', endTime: '17:10'),
    TimeSlot(section: 4, startTime: '19:00', endTime: '20:00'),
    TimeSlot(section: 5, startTime: '20:10', endTime: '21:00'),
    TimeSlot(section: 6, startTime: '21:10', endTime: '22:00'),
  ];

  Course course({
    int id = 1,
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 1,
    String name = '高等数学',
    String? classroom = 'A101',
    String? teacher = '张三',
    int colorValue = 0xFFE53935,
  }) =>
      Course(
        id: id,
        semesterId: 1,
        name: name,
        classroom: classroom,
        teacher: teacher,
        colorValue: colorValue,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        weeks: const [1, 2],
        weekType: 0,
      );

  test('上课中 + 后续课：只列未结束的，按时间排序，顶栏是今天', () {
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 10, 12),
      semester: semester,
      courses: [
        course(id: 3, startSection: 3, endSection: 3, name: '实验课'),
        course(id: 1, startSection: 1, endSection: 1, name: '已结束课'),
        course(id: 2, startSection: 2, endSection: 2, name: '药理学'),
      ],
      timeSlots: slots,
    );
    expect(payload.headerLeft, '大三上');
    expect(payload.headerRight, '9.7 第1周 周一');
    expect(payload.rows.map((r) => r.name).toList(), ['药理学', '实验课']);
    expect(payload.rows.first.start, '09:40');
    expect(payload.rows.first.end, '12:00');
    expect(payload.rows.first.sub, 'A101 张三');
    expect(payload.footer, '');
  });

  test('今天没课了 → 换明天的课，顶栏日期跟着变', () {
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 22, 30),
      semester: semester,
      courses: [
        course(id: 1, dayOfWeek: 2, startSection: 1, name: '明天的课'),
      ],
      timeSlots: slots,
    );
    expect(payload.rows.single.name, '明天的课');
    expect(payload.headerRight, '9.8 第1周 周二');
  });

  test('超过 4 行截断 + 尾注计数', () {
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: semester,
      courses: [
        for (var i = 1; i <= 6; i++)
          course(id: i, startSection: i, endSection: i, name: '课$i'),
      ],
      timeSlots: slots,
    );
    expect(payload.rows.length, 4);
    expect(payload.footer, '还有 2 节课');
  });

  test('教室/教师缺失时 sub 省略对应部分', () {
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: semester,
      courses: [course(classroom: null, teacher: null, name: '无地点课')],
      timeSlots: slots,
    );
    expect(payload.rows.single.sub, '');
  });

  test('颜色按配色方案映射（莫兰迪色切到马卡龙方案）', () {
    final raw = MorandiPalette.colors[0];
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: semester,
      courses: [course(colorValue: raw)],
      timeSlots: slots,
      ui: const UiSettings(colorSchemeId: 'macaron'),
    );
    expect(
      payload.rows.single.colorArgb,
      mapCourseColor(raw, courseSchemeById('macaron')),
    );
    expect(payload.rows.single.colorArgb, isNot(raw));
  });

  test('停课的课不出现在列表里', () {
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: semester,
      courses: [course(id: 9, name: '停掉的课')],
      timeSlots: slots,
      overrides: const [
        CourseOverride(
            courseId: 9, originalWeek: 1, targetWeek: CourseOverride.cancelFlag),
      ],
    );
    expect(payload.rows, isEmpty);
    expect(payload.emptyText, '暂无课程');
  });

  test('无学期时兜底', () {
    final payload = buildWidgetPayload(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: null,
      courses: const [],
      timeSlots: slots,
    );
    expect(payload.headerLeft, '小马课表');
    expect(payload.rows, isEmpty);
  });
}
