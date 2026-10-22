import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/note.dart';
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

  // ---------- 1.3.4 逐日 payload（小部件跨天自动切换） ----------

  test('逐日表：默认 7 天，键是今天起算的 yyyy-MM-dd', () {
    final days = buildWidgetPayloadDays(
      now: DateTime(2026, 9, 7, 10, 12),
      semester: semester,
      courses: [course(id: 1, dayOfWeek: 1, name: '周一的课')],
      timeSlots: slots,
    );
    expect(days.length, 7);
    expect(
      days.keys.toList(),
      [
        '2026-09-07',
        '2026-09-08',
        '2026-09-09',
        '2026-09-10',
        '2026-09-11',
        '2026-09-12',
        '2026-09-13',
      ],
    );
  });

  test('今天这份与 buildWidgetPayload 逐字一致（含「已结束的课不入选」）', () {
    final now = DateTime(2026, 9, 7, 10, 12);
    final days = buildWidgetPayloadDays(
      now: now,
      semester: semester,
      courses: [
        course(id: 1, startSection: 1, name: '已结束课'),
        course(id: 2, startSection: 2, name: '正在上的课'),
      ],
      timeSlots: slots,
    );
    expect(
      days['2026-09-07'],
      buildWidgetPayload(
        now: now,
        semester: semester,
        courses: [
          course(id: 1, startSection: 1, name: '已结束课'),
          course(id: 2, startSection: 2, name: '正在上的课'),
        ],
        timeSlots: slots,
      ).toJson(),
    );
  });

  test('未来某日按该日 00:00 构建：当天课程完整入选且顶栏是该日', () {
    final days = buildWidgetPayloadDays(
      now: DateTime(2026, 9, 7, 10, 12),
      semester: semester,
      courses: [
        course(id: 1, dayOfWeek: 1, startSection: 1, name: '周一第1节'),
        course(id: 2, dayOfWeek: 2, startSection: 1, name: '周二第1节'),
        course(
          id: 3,
          dayOfWeek: 2,
          startSection: 4,
          endSection: 4,
          name: '周二第4节',
        ),
      ],
      timeSlots: slots,
    );
    final tue = days['2026-09-08']!;
    expect(tue['rows'] as List, hasLength(2));
    expect(
      (tue['rows'] as List).map((r) => (r as Map)['name']).toList(),
      ['周二第1节', '周二第4节'],
    );
    expect(tue['headerRight'], '9.8 第1周 周二');
  });

  test('无课的某天按现有语义顺延到次日（今天与未来某日同理）', () {
    final days = buildWidgetPayloadDays(
      now: DateTime(2026, 9, 11, 10, 12), // 2026-09-11 是周五
      semester: semester,
      courses: [course(id: 1, dayOfWeek: 6, name: '只有周六有课')],
      timeSlots: slots,
    );
    // 周五当天无课 → 顺延周六；周六那份（00:00 构建）直接是周六的课
    expect(days['2026-09-11']!['headerRight'], '9.12 第1周 周六');
    final sat = days['2026-09-12']!;
    expect(sat['headerRight'], '9.12 第1周 周六');
    expect((sat['rows'] as List).single['name'], '只有周六有课');
    // 周日 00:00 无课 → 顺延周一（第 2 周）
    expect(days['2026-09-13']!['headerRight'], '9.14 第2周 周一');
  });

  test('逐日表整体可 JSON 编码，且每天都是完整 payload 结构', () {
    final days = buildWidgetPayloadDays(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: semester,
      courses: [course(id: 1, dayOfWeek: 3, name: '周三的课')],
      timeSlots: slots,
    );
    final decoded = jsonDecode(jsonEncode(days)) as Map<String, dynamic>;
    expect(decoded.length, 7);
    for (final v in decoded.values) {
      final m = v as Map<String, dynamic>;
      final keys = m.keys.toList()..sort();
      expect(keys, [
        'emptyText',
        'footer',
        'headerLeft',
        'headerRight',
        'notes',
        'rows',
      ]);
    }
  });

  test('无学期时逐日表也有 7 份兜底 payload', () {
    final days = buildWidgetPayloadDays(
      now: DateTime(2026, 9, 7, 7, 0),
      semester: null,
      courses: const [],
      timeSlots: const [],
    );
    expect(days.length, 7);
    expect(days.values.every((p) => p['headerLeft'] == '小马课表'), isTrue);
    expect(days['2026-09-09']!['headerRight'], '9.9 周三');
  });

  group('当日备注', () {
    Note note(String date, String content, {int id = 1}) => Note(
          id: id,
          date: date,
          content: content,
          createdAt: DateTime(2026, 9, 1).millisecondsSinceEpoch,
        );

    test('payload 带上展示那天的备注，最多 3 条且去掉空白', () {
      final payload = buildWidgetPayload(
        now: DateTime(2026, 9, 7, 7, 0),
        semester: semester,
        courses: [course(startSection: 1, endSection: 1)],
        timeSlots: slots,
        notesByDate: {
          '2026-09-07': [
            note('2026-09-07', '带实验服'),
            note('2026-09-07', '  '),
            note('2026-09-07', '交作业'),
            note('2026-09-07', '周三预习'),
            note('2026-09-07', '第四条不该出现'),
          ],
        },
      );
      expect(payload.notes, ['带实验服', '交作业', '周三预习']);
    });

    test('没有备注时 notes 为空列表，老 payload 结构不受影响', () {
      final payload = buildWidgetPayload(
        now: DateTime(2026, 9, 7, 7, 0),
        semester: semester,
        courses: [course(startSection: 1, endSection: 1)],
        timeSlots: slots,
      );
      expect(payload.notes, isEmpty);
      expect(payload.toJson()['notes'], <String>[]);
    });

    test('今天没课顺延到明天时，备注跟着换成明天的', () {
      final payload = buildWidgetPayload(
        // 今天的课已经上完（最后一节 22:00 结束）
        now: DateTime(2026, 9, 7, 23, 0),
        semester: semester,
        courses: [course(startSection: 6, endSection: 6, dayOfWeek: 1)],
        timeSlots: slots,
        notesByDate: {
          '2026-09-07': [note('2026-09-07', '今天的备忘')],
          '2026-09-08': [note('2026-09-08', '明天的备忘')],
        },
      );
      expect(payload.headerRight, contains('9.8'));
      expect(payload.notes, ['明天的备忘']);
    });

    test('逐日 payload 各带各日备注', () {
      final days = buildWidgetPayloadDays(
        now: DateTime(2026, 9, 7, 7, 0),
        semester: semester,
        courses: [course(id: 1, dayOfWeek: 3, name: '周三的课')],
        timeSlots: slots,
        notesByDate: {
          '2026-09-07': [note('2026-09-07', '周一备忘')],
          '2026-09-09': [note('2026-09-09', '周三备忘')],
        },
      );
      expect(days['2026-09-07']!['notes'], ['周一备忘']);
      expect(days['2026-09-08']!['notes'], isEmpty);
      expect(days['2026-09-09']!['notes'], ['周三备忘']);
    });
  });
}
