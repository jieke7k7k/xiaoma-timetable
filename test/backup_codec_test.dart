import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/utils/backup_codec.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// JSON 备份编解码 + 恢复入库测试
///
/// encode/decode 为纯逻辑测试；restore 用 sqflite_common_ffi 内存库跑真实 SQL，
/// 验证「清空旧数据、外键重映射、设置覆盖」三条核心语义。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// 一份覆盖全部字段的标准备份（字段故意各不相同，便于往返断言）
  Map<String, dynamic> backupJson() => BackupCodec.encode(
        semesters: const [
          Semester(
              id: 1,
              name: '大三上',
              startDate: '2026-09-07',
              totalWeeks: 20,
              isCurrent: true),
          Semester(id: 2, name: '大三下', startDate: '2027-03-01', totalWeeks: 18),
        ],
        timeSlots: const [
          TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
          TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
        ],
        courses: const [
          Course(
            id: 11,
            semesterId: 1,
            name: '高等数学',
            teacher: '张老师',
            classroom: 'A101',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3],
            weekType: 0,
            note: '带教材',
            examDate: 1790000000000,
          ),
        ],
        overrides: const [
          CourseOverride(
              id: 21,
              courseId: 11,
              originalWeek: 2,
              targetWeek: CourseOverride.cancelFlag),
        ],
        settings: const {'theme_mode': 'dark', 'reminder_advance_minutes': '15'},
        now: DateTime(2026, 10, 15, 12, 0),
      );

  group('encode/decode 往返', () {
    test('往返后各模型字段完整保留', () {
      final data = BackupCodec.decode(jsonEncode(backupJson()));

      expect(data.semesters.length, 2);
      final s1 = data.semesters.first;
      expect(s1.name, '大三上');
      expect(s1.startDate, '2026-09-07');
      expect(s1.totalWeeks, 20);
      expect(s1.isCurrent, isTrue);

      expect(data.timeSlots.length, 2);
      expect(data.timeSlots.first.startTime, '08:00');

      final c = data.courses.single;
      expect(c.name, '高等数学');
      expect(c.teacher, '张老师');
      expect(c.classroom, 'A101');
      expect(c.colorValue, 0xFF6B8E7B);
      expect(c.weeks, [1, 2, 3]);
      expect(c.note, '带教材');
      expect(c.examDate, 1790000000000);

      final o = data.courseOverrides.single;
      expect(o.originalWeek, 2);
      expect(o.isCancellation, isTrue);

      expect(data.appSettings['theme_mode'], 'dark');
      expect(data.appSettings['reminder_advance_minutes'], '15');
    });

    test('导出 JSON 带版本号与归属标记', () {
      final j = backupJson();
      expect(j['version'], BackupCodec.backupVersion);
      expect(j['app'], BackupCodec.appTag);
    });
  });

  group('decode 校验（坏文件必须在碰数据库前被拦下）', () {
    test('非 JSON 文本给出中文错误', () {
      expect(
        () => BackupCodec.decode('这不是JSON{'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('版本过新拒绝导入并提示升级', () {
      final j = backupJson();
      j['version'] = 99;
      expect(
        () => BackupCodec.decode(jsonEncode(j)),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.message.contains('版本过新'))),
      );
    });

    test('缺少学期数据拒绝（不像本 App 的备份）', () {
      final j = backupJson();
      j.remove('semesters');
      expect(
        () => BackupCodec.decode(jsonEncode(j)),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.message.contains('没有学期数据'))),
      );
    });

    test('课程指向不存在的学期时报错并点名课程', () {
      final j = backupJson();
      (j['courses'] as List).first['semesterId'] = 999;
      expect(
        () => BackupCodec.decode(jsonEncode(j)),
        throwsA(predicate(
            (e) => e is BackupFormatException && e.message.contains('高等数学'))),
      );
    });

    test('两个学期都标 isCurrent 时归一为恰好一个（保留第一个）', () {
      final j = backupJson();
      (j['semesters'] as List)[1]['isCurrent'] = 1;
      final data = BackupCodec.decode(jsonEncode(j));
      expect(data.semesters.where((s) => s.isCurrent).length, 1);
      expect(data.semesters.first.isCurrent, isTrue);
      expect(data.semesters.last.isCurrent, isFalse);
    });

    test('完全没有 isCurrent 时回退第一个学期（保证恢复后有当前学期）', () {
      final j = backupJson();
      (j['semesters'] as List)[0]['isCurrent'] = 0;
      final data = BackupCodec.decode(jsonEncode(j));
      expect(data.semesters.first.isCurrent, isTrue);
      expect(data.semesters.last.isCurrent, isFalse);
    });
  });

  group('restore 恢复入库（ffi 内存库跑真实 SQL）', () {
    late Database db;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      // createSchema 自带「旧数据」：默认学期 + 默认节次时间，正好用来验证被清空
    });

    tearDown(() => db.close());

    test('清空旧数据、重映射外键、覆盖设置', () async {
      // 旧数据确实存在
      expect(await db.query('semesters'), isNotEmpty);
      expect((await db.query('time_slots')).length, defaultTimeSlots.length);

      final data = BackupCodec.decode(jsonEncode(backupJson()));
      final summary = await BackupCodec.restore(db, data);
      expect(summary.semesters, 2);
      expect(summary.courses, 1);
      expect(summary.courseOverrides, 1);
      expect(summary.timeSlots, 2);

      // 旧默认学期被清掉，新学期按备份顺序重建，isCurrent 唯一
      final semesters = await db.query('semesters', orderBy: 'id ASC');
      expect(semesters.length, 2);
      expect(semesters.first['name'], '大三上');
      expect(semesters.first['isCurrent'], 1);
      expect(semesters.last['isCurrent'], 0);
      final newFirstId = semesters.first['id'] as int;

      // 课程 semesterId 重映射到新学期 id（不能照抄备份里的旧 id=1 之外乱指）
      final courses = await db.query('courses');
      expect(courses.single['semesterId'], newFirstId);
      expect(courses.single['name'], '高等数学');
      expect(courses.single['examDate'], 1790000000000);
      expect(courses.single['weeksJson'], '[1,2,3]');

      // 调课记录 courseId 重映射到新课程 id
      final overrides = await db.query('course_overrides');
      expect(overrides.single['courseId'], courses.single['id']);
      expect(overrides.single['targetWeek'], CourseOverride.cancelFlag);

      // 节次时间被备份覆盖（12 条 → 2 条）
      expect((await db.query('time_slots')).length, 2);

      // app_settings 被备份覆盖
      final settings = {
        for (final r in await db.query('app_settings'))
          r['key'] as String: r['value'] as String,
      };
      expect(settings['theme_mode'], 'dark');
    });

    test('恢复后全局有且仅有一个当前学期', () async {
      final data = BackupCodec.decode(jsonEncode(backupJson()));
      await BackupCodec.restore(db, data);
      final currents =
          await db.query('semesters', where: 'isCurrent = 1');
      expect(currents.length, 1);
      expect(currents.first['name'], '大三上');
    });
  });
}
