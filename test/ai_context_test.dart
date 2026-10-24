import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/services/command_executor.dart';
import 'package:xiaoma_timetable/utils/ai_context.dart';

/// 内置 AI 的纯函数测试：指令块解析 + 课表上下文组装 + 系统提示
///
/// 全是不碰网络、不碰数据库的纯函数（与 bridge_codec_test 同一套路）。
void main() {
  group('parseAiReply', () {
    test('带指令块：指令被抽出，正文里不再有代码块', () {
      const raw = '好的，我帮你加一条备注。\n\n'
          '```json\n{"commands":[{"type":"add_note","date":"2026-10-23","content":"交作业"}]}\n```';
      final reply = parseAiReply(raw);
      expect(reply.hasCommands, isTrue);
      expect(reply.commands.length, 1);
      expect(reply.commands.first['type'], 'add_note');
      expect(reply.commands.first['content'], '交作业');
      expect(reply.text, isNot(contains('```')));
      expect(reply.text, isNot(contains('commands')));
      expect(reply.text, contains('好的，我帮你加一条备注'));
      expect(reply.commandParseError, isNull);
    });

    test('没有指令块时正文原样保留', () {
      const raw = '明天有两节课：高等数学和大学英语。';
      final reply = parseAiReply(raw);
      expect(reply.hasCommands, isFalse);
      expect(reply.text, raw);
    });

    test('多个指令块按顺序合并', () {
      const raw = '```json\n{"commands":[{"type":"add_note","content":"A"}]}\n```\n'
          '说明一下\n\n'
          '```json\n{"commands":[{"type":"delete_note","id":7}]}\n```';
      final reply = parseAiReply(raw);
      expect(reply.commands.length, 2);
      expect(reply.commands.last['type'], 'delete_note');
      expect(reply.text, '说明一下');
    });

    test('非 json 语言标记的代码块不当指令（原样留在正文里）', () {
      const raw = '格式长这样：\n```dart\nvar x = {"commands": []};\n```';
      final reply = parseAiReply(raw);
      expect(reply.hasCommands, isFalse);
      expect(reply.text, contains('```dart'));
      expect(reply.commandParseError, isNull);
    });

    test('看着像指令块但 JSON 坏了：忽略并给出中文提示', () {
      const raw = '```json\n{"commands":[{"type":}\n```\n正文';
      final reply = parseAiReply(raw);
      expect(reply.hasCommands, isFalse);
      expect(reply.commandParseError, isNotNull);
      expect(reply.text, contains('正文'));
    });

    test('代码块里没有 commands 字段：不算指令', () {
      const raw = '```json\n{"hello":"world"}\n```';
      final reply = parseAiReply(raw);
      expect(reply.hasCommands, isFalse);
    });

    test('空回复不会炸', () {
      final reply = parseAiReply('');
      expect(reply.text, '');
      expect(reply.hasCommands, isFalse);
    });
  });

  group('指令描述与破坏性', () {
    test('add_course 的人话描述带上星期节次与周次', () {
      expect(
        describeAiCommand({
          'type': 'add_course',
          'name': '高等数学',
          'dayOfWeek': 1,
          'startSection': 1,
          'endSection': 2,
          'weeks': [1, 2, 3, 5],
          'classroom': 'A101',
        }),
        '新增课程《高等数学》：周一，第1-2节，第1-3,5周，A101',
      );
    });

    test('delete_note 是破坏性，其余不是', () {
      expect(isDestructiveCommand({'type': 'delete_note', 'id': 7}), isTrue);
      expect(isDestructiveCommand({'type': 'add_note'}), isFalse);
      // 未知类型按非破坏处理：执行器会把它判成「不支持的指令类型」
      expect(isDestructiveCommand({'type': 'whatever'}), isFalse);
    });

    test('未知类型也有兜底人话', () {
      expect(describeAiCommand({'type': 'drop_table'}), '执行 drop_table 指令');
      expect(describeAiCommand({}), '执行 未知 指令');
    });
  });

  group('buildTimetableContext', () {
    const semester = Semester(
      id: 1,
      name: '大三上学期',
      startDate: '2026-09-07',
      totalWeeks: 20,
      isCurrent: true,
    );

    final now = DateTime(2026, 10, 22, 9, 30); // 周四，开学第 7 周（单周）

    // 用本地时间构造时间戳：测试机在任何时区都落在 2026-10-30 这一天
    final examStamp = DateTime(2026, 10, 30).millisecondsSinceEpoch;

    List<Course> courses() => [
          const Course(
            id: 11,
            semesterId: 1,
            name: '高等数学',
            teacher: '张三',
            classroom: 'A101',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 2,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3, 4, 5, 6, 7],
          ),
          Course(
            id: 12,
            semesterId: 1,
            name: '大学英语',
            colorValue: 0xFF000000,
            dayOfWeek: 4,
            startSection: 3,
            endSection: 4,
            weeks: const [7],
            weekType: 1,
            examDate: examStamp,
          ),
        ];

    List<Note> notes() => const [
          Note(id: 1, date: '2026-10-22', content: '交作业', createdAt: 1),
          Note(id: 2, date: '2026-10-23', content: '买面包', createdAt: 2),
        ];

    test('学期名 / 总周数 / 当前第几周与单双周都在', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: now,
      );
      expect(text, contains('大三上学期'));
      expect(text, contains('共 20 周'));
      expect(text, contains('第 7 周（单周）'));
    });

    test('今天与明天的日期 + 星期都给了（模型不用自己算）', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: now,
      );
      expect(text, contains('【今天】2026-10-22 周四'));
      expect(text, contains('明天 2026-10-23 周五'));
    });

    test('本周课程按星期节次排序，含教师/教室/周次/仅单周', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: now,
      );
      final mathLine = text.split('\n').firstWhere(
            (l) => l.contains('高等数学'),
          );
      expect(mathLine, contains('周二 第1-2节'));
      expect(mathLine, contains('教师：张三'));
      expect(mathLine, contains('教室：A101'));
      expect(mathLine, contains('第1-7周'));
      final englishLine = text.split('\n').firstWhere(
            (l) => l.contains('大学英语'),
          );
      expect(englishLine, contains('仅单周'));
      // 周二排在周四前面
      expect(text.indexOf('高等数学'), lessThan(text.indexOf('大学英语')));
    });

    test('临近考试带倒计时文案', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: now,
      );
      expect(text, contains('【临近考试】'));
      expect(text, contains('《大学英语》'));
      expect(text, contains('还有 8 天'));
    });

    test('日期备注全部列出（不只今明两天），每条带 id / 日期 / 内容', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: const [
          Note(id: 1, date: '2026-10-22', content: '交作业', createdAt: 1),
          Note(id: 2, date: '2026-10-23', content: '买面包', createdAt: 2),
          // 远于今明两天的日期也要列出，证明是「全部」而非只今明
          Note(id: 3, date: '2026-11-01', content: '运动会', createdAt: 3),
        ],
        now: now,
      );
      expect(text, contains('【日期备注（按天，只对某一天有效）】'));
      expect(text, contains('- [id=1] 2026-10-22 交作业'));
      expect(text, contains('- [id=2] 2026-10-23 买面包'));
      expect(text, contains('- [id=3] 2026-11-01 运动会'));
    });

    test('课程备注单列一节，明确与日期备注区分', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: const [
          Note(id: 9, date: '2026-10-25', content: '买药', createdAt: 1),
        ],
        now: now,
      );
      expect(text, contains('【课程备注（挂在课程上，长期有效）】'));
      // 大学英语没有 note，课程备注节显示无
      expect(text, contains('（无）'));
    });

    test('带课程备注的课程会出现在「课程备注」节，并带课程名', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: [
          const Course(
            id: 11,
            semesterId: 1,
            name: '高等数学',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 2,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3],
            note: '二楼',
          ),
        ],
        notes: const [],
        now: now,
      );
      expect(text, contains('【课程备注（挂在课程上，长期有效）】'));
      expect(text, contains('- 《高等数学》（id=11）：二楼'));
    });

    test('没有课程 / 没有考试 / 没有备注时都有兜底文案', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: const [],
        notes: const [],
        now: now,
      );
      expect(text, contains('（本周没有课程）'));
      expect(text, contains('（没有已登记的考试）'));
      expect(text, contains('（无）'));
    });

    test('还没开学时明确写出来，且不显示单双周', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: DateTime(2026, 8, 1),
      );
      expect(text, contains('还没开学'));
      expect(text, isNot(contains('（单周）')));
    });

    test('没有当前学期时提示用户去建学期', () {
      final text = buildTimetableContext(
        semester: null,
        courses: const [],
        notes: const [],
        now: now,
      );
      expect(text, contains('还没设置当前学期'));
    });

    test('上下文是稳定的多行文本（以【学期】开头）', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: now,
      );
      expect(text.split('\n').first, startsWith('【学期】'));
    });
  });

  group('buildSystemPrompt', () {
    test('包含上下文、回答规则与指令协议', () {
      final prompt = buildSystemPrompt('【学期】测试');
      expect(prompt, contains('【学期】测试'));
      expect(prompt, contains('```json'));
      expect(prompt, contains('"commands"'));
      expect(prompt, contains('add_course'));
      expect(prompt, contains('delete_note'));
      expect(prompt, contains('set_course_remark'));
      // 必须写明「不会立刻执行」，避免模型以为发出去就生效
      expect(prompt, contains('不会立刻执行'));
      // 2.0.5 第 2 节：明确两类备注的默认语义，让模型不再把课程备注塞成日期备注
      expect(prompt, contains('课程备注'));
      expect(prompt, contains('日期备注'));
      expect(prompt, contains('给 XX 课加备注'));
    });
  });

  group('全部课程清单与指令示例（2.0.6 第 3 节）', () {
    const semester = Semester(
      id: 1,
      name: '大三上学期',
      startDate: '2026-09-07',
      totalWeeks: 20,
      isCurrent: true,
    );
    final now = DateTime(2026, 10, 22, 9, 30);

    List<Course> allCourses() => [
          Course(
            id: 21,
            semesterId: 1,
            name: '药理学实验',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 4,
            startSection: 3,
            endSection: 4,
            weeks: const [1, 2, 3],
          ),
          const Course(
            id: 11,
            semesterId: 1,
            name: '高等数学',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 2,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3],
          ),
        ];

    test('buildCourseListContext 按课程名排序，行格式「《课程名》（id 编号、周X 第A-B节）」', () {
      final list = buildCourseListContext(allCourses());
      expect(list, contains('【全部课程（定位用）】'));
      // 按课程名 compareTo（UTF-16 编码序）排序：药 U+836F < 高 U+9AD8，药理学实验在前
      expect(list.indexOf('药理学实验'), lessThan(list.indexOf('高等数学')));
      expect(list, contains('- 《高等数学》（id 11、周二 第1-2节）'));
      expect(list, contains('- 《药理学实验》（id 21、周四 第3-4节）'));
    });

    test('buildTimetableContext 传 allCourses 时多出【全部课程（定位用）】节', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: allCourses(),
        notes: const [],
        now: now,
        allCourses: allCourses(),
      );
      expect(text, contains('【全部课程（定位用）】'));
      expect(text, contains('- 《高等数学》（id 11、周二 第1-2节）'));
    });

    test('allCourses 为空/null 时不输出这一节（兼容不传的调用方）', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: allCourses(),
        notes: const [],
        now: now,
      );
      expect(text, isNot(contains('【全部课程（定位用）】')));
    });

    test('buildSystemPrompt 含 set_course_remark 两条 JSON 示例与 courseName 原样复制硬规矩', () {
      final prompt = buildSystemPrompt('【学期】测试');
      expect(
        prompt,
        contains('{"type":"set_course_remark","courseName":"药理学实验","remark":"二楼"}'),
      );
      expect(
        prompt,
        contains('{"type":"set_course_remark","courseName":"药理学实验","remark":""}'),
      );
      expect(prompt, contains('清除备注'));
      expect(prompt, contains('原样复制'));
      expect(prompt, contains('不要改字'));
      expect(prompt, contains('不要用简称'));
      expect(prompt, contains('不要自己编 id'));
    });
  });

  group('纠错重试判定（2.0.6 第 4 节）', () {
    CommandResult fail(String msg) => CommandResult(
          type: 'set_course_remark',
          success: false,
          message: msg,
          destructive: false,
        );
    const ok = CommandResult(
      type: 'set_course_remark',
      success: true,
      message: '已改好',
      destructive: false,
    );

    test('参数类报错判为参数类失败', () {
      expect(isParameterFailure('缺少参数 dayOfWeek'), isTrue);
      expect(isParameterFailure('缺少定位参数：需要 courseId 或 courseName'), isTrue);
      expect(isParameterFailure('当前学期没有名为《高等数学》的课程'), isTrue);
      expect(isParameterFailure('当前学期没有 id 为 999 的课程'), isTrue);
      expect(isParameterFailure('课程名「数学」能对上多门课：…'), isTrue);
      expect(isParameterFailure('不支持的指令类型：stop_course'), isTrue);
    });

    test('非参数类报错不算参数类失败', () {
      expect(isParameterFailure('还没有当前学期，无法修改课程备注'), isFalse);
      expect(isParameterFailure('执行失败：数据库异常'), isFalse);
    });

    test('有参数类失败且未重试才重试；全成功 / 已重试都不重试', () {
      expect(
        shouldRetryForParameterError([ok, fail('缺少定位参数')], alreadyRetried: false),
        isTrue,
      );
      expect(shouldRetryForParameterError([ok], alreadyRetried: false), isFalse);
      expect(
        shouldRetryForParameterError([fail('缺少定位参数')], alreadyRetried: true),
        isFalse,
      );
    });

    test('buildCorrectionPrompt 含用户原话 / 失败指令 / 报错 / 课程名单', () {
      final prompt = buildCorrectionPrompt(
        userText: '给药理学实验添加备注',
        failedCommands: const [
          {'type': 'set_course_remark', 'remark': '二楼'},
        ],
        failedMessages: const ['缺少定位参数：需要 courseId 或 courseName'],
        courseList: '【全部课程（定位用）】\n- 《药理学实验》（id 21、周四 第3-4节）',
      );
      expect(prompt, contains('给药理学实验添加备注'));
      expect(prompt, contains('"type": "set_course_remark"'));
      expect(prompt, contains('缺少定位参数'));
      expect(prompt, contains('【全部课程（定位用）】'));
      expect(prompt, contains('{"commands":[...]}'));
    });
  });
}
