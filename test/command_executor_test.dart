import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/services/command_executor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 结构化指令执行器测试（跑在 sqflite_common_ffi 内存库上）
///
/// 覆盖：一期五条指令的正常路径、参数缺失/非法时的中文原因、
/// 「冲突只提示不拦截」「单条失败不中断整批」两条产品口径，
/// 以及 destructive 标记的集中登记。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late CommandExecutor ex;
  late int semesterId;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    ex = CommandExecutor();
    semesterId = (await Dao.instance.getCurrentSemester())!.id!;
  });

  tearDown(() async {
    await db.close();
  });

  Course course({
    int? id,
    String name = '高等数学',
    int dayOfWeek = 1,
    int startSection = 1,
    int endSection = 2,
    List<int> weeks = const [1, 2, 3],
    int colorValue = 0xFF6B8E7B,
    String? note,
  }) =>
      Course(
        id: id,
        semesterId: semesterId,
        name: name,
        colorValue: colorValue,
        dayOfWeek: dayOfWeek,
        startSection: startSection,
        endSection: endSection,
        weeks: weeks,
        note: note,
      );

  Future<List<Course>> courses() =>
      Dao.instance.getCoursesBySemester(semesterId);

  group('add_course', () {
    test('按全字段新增，学期自动取当前学期', () async {
      final r = await ex.execute({
        'type': 'add_course',
        'name': '高等数学',
        'teacher': '张三',
        'classroom': 'A101',
        'colorValue': '#6B8E7B',
        'dayOfWeek': 1,
        'startSection': 1,
        'endSection': 2,
        'weeks': '1-8',
        'note': '带书',
      });

      expect(r.success, isTrue);
      expect(r.destructive, isFalse);
      expect(r.message, contains('已新增《高等数学》'));
      final list = await courses();
      expect(list.length, 1);
      expect(list.single.semesterId, semesterId);
      expect(list.single.name, '高等数学');
      expect(list.single.teacher, '张三');
      expect(list.single.classroom, 'A101');
      expect(list.single.note, '带书');
      expect(list.single.colorValue, 0xFF6B8E7B);
      expect(list.single.weeks, [1, 2, 3, 4, 5, 6, 7, 8]);
    });

    test('周次语义与导入一致：字符串支持「1-8单周」，数组直接当列表', () async {
      await ex.execute({
        'type': 'add_course',
        'name': '单周课',
        'dayOfWeek': 2,
        'startSection': 3,
        'endSection': 4,
        'weeks': '1-8单周',
      });
      await ex.execute({
        'type': 'add_course',
        'name': '数组课',
        'dayOfWeek': 3,
        'startSection': 3,
        'weeks': [2, 4, 6],
      });

      final list = await courses();
      expect(
        list.firstWhere((c) => c.name == '单周课').weeks,
        [1, 3, 5, 7],
      );
      expect(list.firstWhere((c) => c.name == '数组课').weeks, [2, 4, 6]);
    });

    test('缺参数：失败并给中文原因，不入库', () async {
      final r = await ex.execute({
        'type': 'add_course',
        'name': '缺星期的课',
        'startSection': 1,
        'weeks': '1-8',
      });

      expect(r.success, isFalse);
      expect(r.message, contains('缺少参数 dayOfWeek'));
      expect(await courses(), isEmpty);
    });

    test('非法参数：星期/节次/周次各有对应中文原因', () async {
      final badDay = await ex.execute({
        'type': 'add_course',
        'name': 'A',
        'dayOfWeek': 8,
        'startSection': 1,
        'weeks': '1-8',
      });
      expect(badDay.success, isFalse);
      expect(badDay.message, contains('dayOfWeek 要在 1~7 之间'));

      final badSection = await ex.execute({
        'type': 'add_course',
        'name': 'B',
        'dayOfWeek': 1,
        'startSection': 5,
        'endSection': 3,
        'weeks': '1-8',
      });
      expect(badSection.success, isFalse);
      expect(badSection.message, contains('节次范围不对'));

      final badWeeks = await ex.execute({
        'type': 'add_course',
        'name': 'C',
        'dayOfWeek': 1,
        'startSection': 1,
        'weeks': 'x-y',
      });
      expect(badWeeks.success, isFalse);
      expect(badWeeks.message, contains('周次解析失败'));
    });

    test('时间冲突：只提示不拦截，课程照样入库', () async {
      final id = await Dao.instance.insertCourse(course(name: '已存在的课'));

      final r = await ex.execute({
        'type': 'add_course',
        'name': '撞车的课',
        'dayOfWeek': 1,
        'startSection': 1,
        'endSection': 2,
        'weeks': '1-8',
      });

      expect(r.success, isTrue);
      expect(r.message, contains('冲突'));
      expect(r.data?['conflicts'], isTrue);
      final list = await courses();
      expect(list.length, 2);
      expect(list.any((c) => c.id == id), isTrue);
    });
  });

  group('set_course_color', () {
    test('按 courseId 改色成功', () async {
      final id = await Dao.instance.insertCourse(course());

      final r = await ex.execute({
        'type': 'set_course_color',
        'courseId': id,
        'colorValue': 0xFFB8BFC7,
      });

      expect(r.success, isTrue);
      expect((await courses()).single.colorValue, 0xFFB8BFC7);
      expect(r.message, contains('#B8BFC7'));
    });

    test('重名多门时批量全改', () async {
      await Dao.instance.insertCourse(course(name: '同名课'));
      await Dao.instance.insertCourse(
          course(name: '同名课', dayOfWeek: 2, startSection: 3, endSection: 4));

      final r = await ex.execute({
        'type': 'set_course_color',
        'courseName': '同名课',
        'color': '#AFC3BB',
      });

      expect(r.success, isTrue);
      expect(r.data?['changedCount'], 2);
      expect(r.message, contains('2 门'));
      final list = await courses();
      expect(list.every((c) => c.colorValue == 0xFFAFC3BB), isTrue);
    });

    test('找不到课程 / 缺参数 → 失败且不动数据', () async {
      final id = await Dao.instance.insertCourse(course());

      final notFound = await ex.execute({
        'type': 'set_course_color',
        'courseId': 999,
        'colorValue': 0xFFB8BFC7,
      });
      expect(notFound.success, isFalse);
      expect(notFound.message, contains('没有 id 为 999 的课程'));

      final noLocate = await ex.execute({
        'type': 'set_course_color',
        'colorValue': 0xFFB8BFC7,
      });
      expect(noLocate.success, isFalse);
      expect(noLocate.message, contains('缺少定位参数'));

      final noColor = await ex.execute({'type': 'set_course_color', 'courseId': id});
      expect(noColor.success, isFalse);
      expect(noColor.message, contains('缺少参数 colorValue'));

      expect((await courses()).single.colorValue, 0xFF6B8E7B);
    });
  });

  group('set_course_remark', () {
    test('按 courseName 定位设置课程备注', () async {
      await Dao.instance.insertCourse(course(name: '药理学实验'));

      final r = await ex.execute({
        'type': 'set_course_remark',
        'courseName': '药理学实验',
        'remark': '二楼',
      });

      expect(r.success, isTrue);
      expect(r.destructive, isFalse);
      expect(r.message, contains('二楼'));
      final c = (await courses()).single;
      expect(c.note, '二楼');
      // 只动 note，其余字段保持
      expect(c.colorValue, 0xFF6B8E7B);
    });

    test('同名课程批量全改', () async {
      await Dao.instance.insertCourse(course(name: '药理学实验'));
      await Dao.instance.insertCourse(
          course(name: '药理学实验', dayOfWeek: 2, startSection: 3, endSection: 4));

      final r = await ex.execute({
        'type': 'set_course_remark',
        'courseName': '药理学实验',
        'remark': '带实验服',
      });

      expect(r.success, isTrue);
      expect(r.data?['changedCount'], 2);
      final list = await courses();
      expect(list.every((c) => c.note == '带实验服'), isTrue);
    });

    test('空字符串清除课程备注', () async {
      final id = await Dao.instance.insertCourse(course(note: '二楼'));

      final r = await ex.execute({
        'type': 'set_course_remark',
        'courseId': id,
        'remark': '',
      });

      expect(r.success, isTrue);
      expect(r.message, contains('清除'));
      expect((await courses()).single.note, isNull);
    });

    test('找不到课程 / 缺参数 → 失败且不动数据', () async {
      final id = await Dao.instance.insertCourse(course(note: '原备注'));

      final notFound = await ex.execute({
        'type': 'set_course_remark',
        'courseName': '不存在的课',
        'remark': '二楼',
      });
      expect(notFound.success, isFalse);
      expect(notFound.message, contains('没有名为'));

      final noLocate = await ex.execute({
        'type': 'set_course_remark',
        'remark': '二楼',
      });
      expect(noLocate.success, isFalse);
      expect(noLocate.message, contains('缺少定位参数'));

      final noRemark = await ex.execute({
        'type': 'set_course_remark',
        'courseId': id,
      });
      expect(noRemark.success, isFalse);
      expect(noRemark.message, contains('缺少参数 remark'));

      expect((await courses()).single.note, '原备注');
    });
  });

  group('add_note / delete_note', () {
    test('指定日期新增备注；不传日期默认今天', () async {
      // 刻意用一个远离今天的固定日期，避免与「默认今天」那条撞在同一个日期里
      final withDate = await ex.execute({
        'type': 'add_note',
        'date': '2030/05/06',
        'content': '带实验服',
      });
      expect(withDate.success, isTrue);
      final list = await Dao.instance.getNotesByDate('2030-05-06');
      expect(list.single.content, '带实验服');

      final today = await ex.execute({'type': 'add_note', 'content': '今天的事'});
      expect(today.success, isTrue);
      expect(today.data?['date'], _todayKey());
      expect(await Dao.instance.getNotesByDate(_todayKey()), hasLength(1));
      // 顺带验证斜杠写法被归一化成 yyyy-MM-dd
      expect(withDate.data?['date'], '2030-05-06');
    });

    test('缺内容 / 日期非法 → 失败不入库', () async {
      final noContent = await ex.execute({
        'type': 'add_note',
        'date': '2026-10-22',
      });
      expect(noContent.success, isFalse);
      expect(noContent.message, contains('缺少参数 content'));

      final badDate = await ex.execute({
        'type': 'add_note',
        'date': '下周某天',
        'content': '待办',
      });
      expect(badDate.success, isFalse);
      expect(badDate.message, contains('日期格式不对'));

      expect(await Dao.instance.getAllNotes(), isEmpty);
    });

    test('delete_note 按 id 删除，标记为 destructive', () async {
      final id = await Dao.instance.insertNote(Note(
        date: '2026-10-22',
        content: '待删除',
        createdAt: 1,
      ));

      final r = await ex.execute({'type': 'delete_note', 'id': id});
      expect(r.success, isTrue);
      expect(r.destructive, isTrue);
      expect(await Dao.instance.getAllNotes(), isEmpty);

      final again = await ex.execute({'type': 'delete_note', 'id': id});
      expect(again.success, isFalse);
      expect(again.message, contains('找不到 id 为 $id 的备注'));
    });

    test('delete_note 按日期删除当天全部备注，报删了几条', () async {
      await Dao.instance.insertNote(Note(
        date: '2026-10-22', content: '第一条', createdAt: 1,
      ));
      await Dao.instance.insertNote(Note(
        date: '2026-10-22', content: '第二条', createdAt: 2,
      ));
      await Dao.instance.insertNote(Note(
        date: '2026-10-23', content: '别的日期', createdAt: 3,
      ));

      final r = await ex.execute({
        'type': 'delete_note',
        'date': '2026-10-22',
      });

      expect(r.success, isTrue);
      expect(r.data?['deletedCount'], 2);
      expect(r.message, contains('2 条'));
      final notes = await Dao.instance.getAllNotes();
      expect(notes.map((n) => n.content).toList(), ['别的日期']);
    });

    test('delete_note 按日期 + 关键词删除当天含关键词备注', () async {
      await Dao.instance.insertNote(Note(
        date: '2026-10-22', content: '带实验服', createdAt: 1,
      ));
      await Dao.instance.insertNote(Note(
        date: '2026-10-22', content: '交作业', createdAt: 2,
      ));
      await Dao.instance.insertNote(Note(
        date: '2026-10-23', content: '带实验服', createdAt: 3,
      ));

      final r = await ex.execute({
        'type': 'delete_note',
        'date': '2026-10-22',
        'content': '实验',
      });

      expect(r.success, isTrue);
      expect(r.data?['deletedCount'], 1);
      final notes = await Dao.instance.getAllNotes();
      expect(notes.map((n) => n.content).toList(), ['交作业', '带实验服']);
    });

    test('delete_note 日期/关键词定位不到 → 中文原因，不报「缺少参数 id」', () async {
      await Dao.instance.insertNote(Note(
        date: '2026-10-22', content: '交作业', createdAt: 1,
      ));

      final noDate = await ex.execute({
        'type': 'delete_note',
        'date': '2026-10-30',
      });
      expect(noDate.success, isFalse);
      expect(noDate.message, contains('没有 2026-10-30 的备注'));

      final noKeyword = await ex.execute({
        'type': 'delete_note',
        'date': '2026-10-22',
        'content': '不存在的词',
      });
      expect(noKeyword.success, isFalse);
      expect(noKeyword.message, contains('不存在的词'));

      final noLocate = await ex.execute({'type': 'delete_note'});
      expect(noLocate.success, isFalse);
      expect(noLocate.message, contains('缺少定位参数'));
      expect(noLocate.message, isNot(contains('缺少参数 id')));

      // 定位失败不动数据
      expect(await Dao.instance.getAllNotes(), hasLength(1));
    });

    test('destructive 标记集中登记：只有删除类为 true', () {
      expect(CommandRegistry.destructiveOf('delete_note'), isTrue);
      expect(CommandRegistry.destructiveOf('add_course'), isFalse);
      expect(CommandRegistry.destructiveOf('set_course_color'), isFalse);
      expect(CommandRegistry.destructiveOf('set_course_remark'), isFalse);
      expect(CommandRegistry.destructiveOf('add_note'), isFalse);
      expect(CommandRegistry.destructiveOf('add_exam'), isFalse);
      // 未登记的指令按非破坏性处理，不影响后续确认策略
      expect(CommandRegistry.destructiveOf('stop_course'), isFalse);
    });
  });

  group('add_exam', () {
    test('按课程名设置考试日期（可带时刻）', () async {
      await Dao.instance.insertCourse(course());

      final r = await ex.execute({
        'type': 'add_exam',
        'courseName': '高等数学',
        'date': '2026-12-20',
        'time': '14:30',
      });

      expect(r.success, isTrue);
      expect(r.message, contains('2026年12月20日 14:30'));
      expect((await courses()).single.examDate,
          DateTime(2026, 12, 20, 14, 30).millisecondsSinceEpoch);
    });

    test('按 courseId 设置，不带时刻时落在当天零点', () async {
      final id = await Dao.instance.insertCourse(course(name: '药理学'));

      final r = await ex.execute({
        'type': 'add_exam',
        'courseId': id,
        'date': '2027-01-11',
      });

      expect(r.success, isTrue);
      expect((await courses()).single.examDate,
          DateTime(2027, 1, 11).millisecondsSinceEpoch);
    });

    test('也接受毫秒时间戳（examDate 字段）', () async {
      final id = await Dao.instance.insertCourse(course());
      final stamp = DateTime(2027, 3, 5).millisecondsSinceEpoch;

      final r = await ex.execute({'type': 'add_exam', 'courseId': id, 'examDate': stamp});

      expect(r.success, isTrue);
      expect((await courses()).single.examDate, stamp);
    });

    test('找不到课程 / 缺日期 / 时刻非法 → 失败不动数据', () async {
      final id = await Dao.instance.insertCourse(course());

      final noCourse = await ex.execute({
        'type': 'add_exam',
        'courseName': '不存在的课',
        'date': '2026-12-20',
      });
      expect(noCourse.success, isFalse);
      expect(noCourse.message, contains('没有名为'));

      final noDate = await ex.execute({'type': 'add_exam', 'courseId': id});
      expect(noDate.success, isFalse);
      expect(noDate.message, contains('缺少参数 date'));

      final badTime = await ex.execute({
        'type': 'add_exam',
        'courseId': id,
        'date': '2026-12-20',
        'time': '25:00',
      });
      expect(badTime.success, isFalse);
      expect(badTime.message, contains('时间超范围'));

      expect((await courses()).single.examDate, isNull);
    });
  });

  group('定位参数别名与按名模糊匹配（2.0.6）', () {
    test('courseName 别名：name / course / course_name / 课程名 都能定位', () async {
      await Dao.instance.insertCourse(course(name: '高等数学'));

      final r1 = await ex.execute(
          {'type': 'set_course_remark', 'name': '高等数学', 'remark': 'A'});
      expect(r1.success, isTrue);
      final r2 = await ex.execute(
          {'type': 'set_course_remark', 'course': '高等数学', 'remark': 'B'});
      expect(r2.success, isTrue);
      final r3 = await ex.execute(
          {'type': 'set_course_remark', 'course_name': '高等数学', 'remark': 'C'});
      expect(r3.success, isTrue);
      final r4 = await ex.execute(
          {'type': 'set_course_remark', '课程名': '高等数学', 'remark': 'D'});
      expect(r4.success, isTrue);
      expect((await courses()).single.note, 'D');
    });

    test('courseId 别名：id 也能定位', () async {
      final id = await Dao.instance.insertCourse(course(name: '药理学'));
      final r = await ex.execute(
          {'type': 'set_course_color', 'id': id, 'color': '#B8BFC7'});
      expect(r.success, isTrue);
      expect((await courses()).single.colorValue, 0xFFB8BFC7);
    });

    test('add_exam 也认 courseName 的别名（course）', () async {
      await Dao.instance.insertCourse(course(name: '高等数学'));
      final r = await ex.execute(
          {'type': 'add_exam', 'course': '高等数学', 'date': '2026-12-20'});
      expect(r.success, isTrue);
      expect((await courses()).single.examDate,
          DateTime(2026, 12, 20).millisecondsSinceEpoch);
    });

    test('add_course 的 name 仍是新课名，不被当定位参数', () async {
      final r = await ex.execute({
        'type': 'add_course',
        'name': '新课',
        'dayOfWeek': 1,
        'startSection': 1,
        'weeks': '1-8',
      });
      expect(r.success, isTrue);
      expect((await courses()).single.name, '新课');
    });

    test('按名模糊匹配：恰好 1 个候选就用它', () async {
      await Dao.instance.insertCourse(course(name: '高等数学'));
      final r = await ex.execute(
          {'type': 'set_course_color', 'courseName': '数学', 'color': '#AFC3BB'});
      expect(r.success, isTrue);
      expect((await courses()).single.colorValue, 0xFFAFC3BB);
    });

    test('按名模糊匹配：多个候选报错并列候选课程名', () async {
      await Dao.instance.insertCourse(course(name: '高等数学'));
      await Dao.instance.insertCourse(
          course(name: '数学分析', dayOfWeek: 2, startSection: 3, endSection: 4));
      final r = await ex.execute(
          {'type': 'set_course_remark', 'courseName': '数学', 'remark': 'X'});
      expect(r.success, isFalse);
      expect(r.message, contains('能对上多门课'));
      expect(r.message, contains('高等数学'));
      expect(r.message, contains('数学分析'));
      // 定位失败不动数据
      expect((await courses()).every((c) => c.note == null), isTrue);
    });

    test('按名模糊匹配：0 个候选维持「没有名为」报错', () async {
      await Dao.instance.insertCourse(course(name: '高等数学'));
      final r = await ex.execute(
          {'type': 'set_course_color', 'courseName': '物理', 'color': '#AFC3BB'});
      expect(r.success, isFalse);
      expect(r.message, contains('没有名为'));
    });
  });

  group('批量与容错', () {
    test('缺 type / 未知 type → 该条失败，提示支持哪些指令', () async {
      final noType = await ex.execute({'name': '没有类型的指令'});
      expect(noType.success, isFalse);
      expect(noType.message, contains('缺少指令类型'));

      final unknown = await ex.execute({'type': 'stop_course'});
      expect(unknown.success, isFalse);
      expect(unknown.message, contains('不支持的指令类型'));
      expect(unknown.message, contains('add_course'));
    });

    test('单条失败不中断整批，结果顺序与入参一致', () async {
      final results = await ex.executeAll([
        {'type': 'add_note', 'date': '2026-10-22', 'content': '第一条'},
        {'type': 'add_note', 'date': '乱写的日期', 'content': '这条会失败'},
        {'type': 'add_note', 'date': '2026-10-23', 'content': '第三条'},
      ]);

      expect(results.length, 3);
      expect(results[0].success, isTrue);
      expect(results[1].success, isFalse);
      expect(results[1].message, contains('日期格式不对'));
      expect(results[2].success, isTrue);

      final notes = await Dao.instance.getAllNotes();
      expect(notes.map((n) => n.content).toList(), ['第一条', '第三条']);
    });

    test('未知指令不会抛异常中断（run 结束即通过）', () async {
      final results = await ex.executeAll([
        {'type': '未知'},
        {},
        {'type': 'delete_note', 'id': 999},
      ]);
      expect(results.every((r) => !r.success), isTrue);
    });
  });
}

String _todayKey() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}
