import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/models/semester.dart';
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

    test('今天与明天的备注分开列', () {
      final text = buildTimetableContext(
        semester: semester,
        courses: courses(),
        notes: notes(),
        now: now,
      );
      expect(text, contains('【今天备注 2026-10-22】'));
      expect(text, contains('- 交作业'));
      expect(text, contains('【明天备注 2026-10-23】'));
      expect(text, contains('- 买面包'));
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
      // 必须写明「不会立刻执行」，避免模型以为发出去就生效
      expect(prompt, contains('不会立刻执行'));
    });
  });
}
