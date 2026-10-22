import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/note.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/utils/bridge_codec.dart';

/// AI 桥协议编解码测试（纯函数，不碰网络与数据库）
///
/// 覆盖：指令批 id 安全字符集、指令批解析与排序、destructive 拆分、
/// results 的状态判定与按 index 合并、已处理 id 裁剪、待确认队列往返与人话描述、
/// 快照字段与「不含任何设置/令牌」这条隐私底线。
void main() {
  group('sanitizeCommandId', () {
    test('普通文件名直接通过', () {
      expect(sanitizeCommandId('abc-123_4'), 'abc-123_4');
    });

    test('含路径分隔符与点点的情况一律拒绝（防止改写仓库任意路径）', () {
      expect(sanitizeCommandId('../../etc/passwd'), isNull);
      expect(sanitizeCommandId('results/abc'), isNull);
      expect(sanitizeCommandId('a\\b'), isNull);
      expect(sanitizeCommandId(''), isNull);
    });

    test('以点开头（隐藏文件）与超长 id 也拒绝', () {
      expect(sanitizeCommandId('.hidden'), isNull);
      expect(sanitizeCommandId('a' * 65), isNull);
      expect(sanitizeCommandId('a' * 64), isNotNull);
    });
  });

  group('parseCommandBatch', () {
    const raw = '''
{
  "id": "batch-1",
  "createdAt": "2026-10-22T10:00:00",
  "note": "帮我把高数加进去",
  "commands": [
    {"type": "add_course", "name": "高等数学"},
    {"type": "delete_note", "id": 7}
  ]
}
''';

    test('正常解析：id / createdAt / note / 指令原文都在', () {
      final batch = parseCommandBatch(raw)!;
      expect(batch.id, 'batch-1');
      expect(batch.createdAtRaw, '2026-10-22T10:00:00');
      expect(batch.note, '帮我把高数加进去');
      expect(batch.commands.length, 2);
      expect(batch.commands.first['name'], '高等数学');
    });

    test('各种坏数据返回 null（由调用方记一条中文失败后跳过）', () {
      expect(parseCommandBatch('not json'), isNull);
      expect(parseCommandBatch('[]'), isNull);
      // 没有 id 且没有文件名兜底
      expect(parseCommandBatch('{"commands":[]}'), isNull);
      // id 非法
      expect(parseCommandBatch('{"id":"../x","commands":[]}'), isNull);
      // commands 不是数组 / 是空数组
      expect(parseCommandBatch('{"id":"a","commands":{}}'), isNull);
      expect(parseCommandBatch('{"id":"a","commands":[]}'), isNull);
    });

    test('缺 id 时用文件名兜底（id 可能被人漏写）', () {
      final batch = parseCommandBatch(
        '{"commands":[{"type":"add_note","content":"交作业"}]}',
        fallbackId: 'from-file-name',
      )!;
      expect(batch.id, 'from-file-name');
      expect(batch.commands.single['content'], '交作业');
    });

    test('指令列表里的非对象元素被丢弃', () {
      final batch = parseCommandBatch(
        '{"id":"a","commands":["垃圾",{"type":"add_note","content":"x"}]}',
      )!;
      expect(batch.commands.length, 1);
    });
  });

  group('sortByCreatedAt', () {
    test('按 createdAt 升序，解析不出来的排最前', () {
      final a = BridgeCommandBatch(
        id: 'a',
        createdAtRaw: '2026-10-23T10:00:00',
        note: null,
        commands: const [],
      );
      final b = BridgeCommandBatch(
        id: 'b',
        createdAtRaw: '2026-10-22T10:00:00',
        note: null,
        commands: const [],
      );
      final broken = BridgeCommandBatch(
        id: 'broken',
        createdAtRaw: '不是时间',
        note: null,
        commands: const [],
      );
      expect(
        sortByCreatedAt([a, b, broken]).map((e) => e.id).toList(),
        ['broken', 'b', 'a'],
      );
      expect(a.sortKey, isPositive);
      expect(broken.sortKey, 0);
    });
  });

  group('splitByDestructive', () {
    test('一期只有 delete_note 是破坏指令', () {
      final split = splitByDestructive([
        {'type': 'add_course'},
        {'type': 'delete_note', 'id': 3},
        {'type': 'add_note'},
      ]);
      expect(split.safe.map((e) => e.index).toList(), [0, 2]);
      expect(split.destructive.map((e) => e.index).toList(), [1]);
      expect(split.destructive.single.type, 'delete_note');
      expect(split.hasDestructive, isTrue);
    });

    test('全是安全指令时不产生待确认队列', () {
      final split = splitByDestructive([
        {'type': 'add_course'},
        {'type': 'set_course_color'},
      ]);
      expect(split.safe.length, 2);
      expect(split.destructive, isEmpty);
      expect(split.hasDestructive, isFalse);
    });

    test('未知指令按非破坏处理（由执行器判「不支持」，不静默吞掉）', () {
      final split = splitByDestructive([
        {'type': 'stop_course'},
      ]);
      expect(split.safe.single.type, 'stop_course');
      expect(split.destructive, isEmpty);
    });

    test('缺少 type 也算非破坏，下标仍然保留', () {
      final split = splitByDestructive([{'name': 'x'}]);
      expect(split.safe.single.index, 0);
      expect(split.safe.single.type, '');
    });
  });

  group('结果状态与合并', () {
    BridgeResultEntry entry(
      int index, {
      bool success = true,
      BridgeResultState state = BridgeResultState.executed,
    }) =>
        BridgeResultEntry(
          index: index,
          type: 'add_course',
          success: success,
          message: 'm$index',
          state: state,
        );

    test('全部成功 → done；有失败 → partial；有等确认 → awaiting_confirm', () {
      expect(statusOfEntries([entry(0), entry(1)]), BridgeResultStatus.done);
      expect(
        statusOfEntries([entry(0), entry(1, success: false)]),
        BridgeResultStatus.partial,
      );
      expect(
        statusOfEntries([
          entry(0, success: false),
          entry(1, state: BridgeResultState.pending),
        ]),
        BridgeResultStatus.awaitingConfirm,
      );
    });

    test('被拒绝也算失败（partial），空条目按 done 兜底', () {
      expect(
        statusOfEntries([entry(0, state: BridgeResultState.rejected)]),
        BridgeResultStatus.partial,
      );
      expect(statusOfEntries(const []), BridgeResultStatus.done);
    });

    test('合并：同下标以新条目覆盖，其余保留原来的并按 index 升序', () {
      final existing = {
        'results': [
          entry(0).toJson(),
          entry(1, success: false).toJson(),
          entry(2, state: BridgeResultState.pending).toJson(),
        ],
      };
      final merged = mergeResultEntries(
        existingDoc: existing,
        updates: [entry(1), entry(2, success: false)],
      );
      expect(merged.map((e) => e.index).toList(), [0, 1, 2]);
      expect(merged[1].success, isTrue); // 被新的成功结果覆盖
      // index 2 从「等确认」变成「执行失败」
      expect(merged[2].state, BridgeResultState.executed);
      expect(merged[2].success, isFalse);
      expect(statusOfEntries(merged), BridgeResultStatus.partial);
    });

    test('旧文档损坏时只写新条目（不因为读不懂就失败）', () {
      final merged = mergeResultEntries(
        existingDoc: '一串坏文本',
        updates: [entry(3)],
      );
      expect(merged.single.index, 3);
    });

    test('buildResultsJson 带齐四个字段且 status 自算', () {
      final json = buildResultsJson(
        batchId: 'b1',
        executedAt: DateTime.parse('2026-10-22T10:00:00'),
        entries: [entry(0), entry(1, state: BridgeResultState.pending)],
      );
      expect(json['id'], 'b1');
      expect(json['executedAt'], '2026-10-22T10:00:00.000');
      expect(json['status'], BridgeResultStatus.awaitingConfirm);
      final results = json['results'] as List;
      expect(results.length, 2);
      expect(results.first['index'], 0);
      expect(results.first['success'], isTrue);
      expect(results.first['message'], 'm0');
      expect(results.last['state'], 'pending');
    });

    test('BridgeResultEntry.fromJson 容错', () {
      expect(BridgeResultEntry.fromJson('x'), isNull);
      expect(BridgeResultEntry.fromJson({'index': '1'}), isNull);
      final e = BridgeResultEntry.fromJson({'index': 2, 'state': 'rejected'})!;
      expect(e.index, 2);
      expect(e.success, isFalse);
      expect(e.state, BridgeResultState.rejected);
      expect(e.message, '');
    });
  });

  group('已处理指令批裁剪', () {
    test('去重后按历史在前、新来的在后追加', () {
      final out = keepRecentProcessed(['a', 'b'], ['b', 'c']);
      expect(out, ['a', 'b', 'c']);
    });

    test('超过上限时丢最旧的（只留最近 limit 条）', () {
      final history = ['p1', 'p2', 'p3'];
      final out = keepRecentProcessed(history, ['n1', 'n2'], limit: 4);
      expect(out, ['p2', 'p3', 'n1', 'n2']);
    });

    test('默认上限就是 200 条', () {
      final many = [for (var i = 0; i < 300; i++) 'id$i'];
      final out = keepRecentProcessed(many, const ['new']);
      expect(out.length, 200);
      expect(out.last, 'new');
      expect(out.first, 'id101');
    });

    test('parseProcessedIds 坏数据按空历史处理', () {
      expect(parseProcessedIds(null), isEmpty);
      expect(parseProcessedIds('不是数组'), isEmpty);
      expect(parseProcessedIds('{"a":1}'), isEmpty);
      expect(parseProcessedIds('["a","b"]'), ['a', 'b']);
    });
  });

  group('待确认队列', () {
    BridgePendingItem pending({
      String batchId = 'batch-9',
      int index = 1,
      String type = 'delete_note',
      String? detail,
    }) =>
        BridgePendingItem(
          batchId: batchId,
          index: index,
          type: type,
          command: {'type': type, 'id': 7},
          arrivedAt: 1761000000000,
          detail: detail,
        );

    test('toJson / fromJson 往返无损', () {
      final item = pending(detail: '2026-10-23 交作业');
      final decoded = BridgePendingItem.fromJson(item.toJson())!;
      expect(decoded.batchId, item.batchId);
      expect(decoded.index, item.index);
      expect(decoded.type, item.type);
      expect(decoded.command['id'], 7);
      expect(decoded.arrivedAt, item.arrivedAt);
      expect(decoded.detail, '2026-10-23 交作业');
    });

    test('id 非法 / 索引不是数字 / 缺 command 的元素被丢弃', () {
      expect(BridgePendingItem.fromJson({'batchId': '../x'}), isNull);
      expect(
        BridgePendingItem.fromJson({'batchId': 'a', 'index': 'x'}),
        isNull,
      );
      expect(BridgePendingItem.fromJson({'batchId': 'a', 'index': 0}), isNull);
      expect(parsePendingList(null), isEmpty);
      expect(parsePendingList('乱码'), isEmpty);
    });

    test('encodePendingList / parsePendingList 往返', () {
      final items = [pending(), pending(index: 5)];
      final decoded = parsePendingList(encodePendingList(items));
      expect(decoded.length, 2);
      expect(decoded.last.index, 5);
    });

    test('describePendingCommand：删除备注带上了日期与内容', () {
      expect(
        describePendingCommand(pending(detail: '2026-10-23 交作业')),
        '删除备注 2026-10-23 交作业',
      );
    });

    test('describePendingCommand：查不到备注时退化成 id 兜底', () {
      expect(describePendingCommand(pending()), '删除备注 id=7');
    });

    test('describePendingCommand：未知类型也有一句人话', () {
      expect(
        describePendingCommand(pending(type: 'drop_table')),
        '执行 drop_table 指令',
      );
    });
  });

  group('BridgeSettings', () {
    test('三项非空才算配好', () {
      expect(
        BridgeSettings.clean(
          owner: ' me ',
          repo: ' xiaoma-bridge ',
          token: 'ghp_x',
        ).configured,
        isTrue,
      );
      expect(
        BridgeSettings.clean(owner: 'me', repo: 'r', token: '  ').configured,
        isFalse,
      );
    });

    test('owner/repo 里的斜杠被剔除（防止拼错 API 路径）', () {
      final s = BridgeSettings.clean(
        owner: 'me/x',
        repo: 'a\\b',
        token: 't',
      );
      expect(s.owner, 'mex');
      expect(s.repo, 'ab');
    });

    test('令牌留空时沿用旧令牌', () {
      final s = BridgeSettings.clean(owner: 'a', repo: 'b', token: '')
          .withTokenFallback('old-token');
      expect(s.token, 'old-token');
      expect(s.configured, isTrue);
    });
  });

  group('buildSnapshotJson', () {
    Semester semester() => const Semester(
          id: 1,
          name: '大三上学期',
          startDate: '2026-09-07',
          totalWeeks: 20,
          isCurrent: true,
        );

    List<Course> courses() => [
          const Course(
            id: 11,
            semesterId: 1,
            name: '高等数学',
            teacher: '张三',
            classroom: 'A101',
            colorValue: 0xFF6B8E7B,
            dayOfWeek: 1,
            startSection: 1,
            endSection: 2,
            weeks: [1, 2, 3],
          ),
          const Course(
            id: 12,
            semesterId: 1,
            name: '大学英语',
            colorValue: 0xFF000000,
            dayOfWeek: 3,
            startSection: 3,
            endSection: 4,
            weeks: [1],
            examDate: 1767225600000, // 2026-01-01 08:00 附近，具体看时区
          ),
        ];

    test('学期信息 + 课程精简字段都在', () {
      final json = buildSnapshotJson(
        semester: semester(),
        courses: courses(),
        notes: const [],
        now: DateTime(2026, 10, 22),
      );
      expect(json['snapshotVersion'], 1);
      expect(json['semester']['name'], '大三上学期');
      expect(json['semester']['startDate'], '2026-09-07');
      expect(json['semester']['totalWeeks'], 20);
      expect(json['semester']['todayWeek'], 7); // 09-07 起算的第 7 周
      final c = (json['courses'] as List).first;
      expect(c['name'], '高等数学');
      expect(c['dayOfWeek'], 1);
      expect(c['startSection'], 1);
      expect(c['endSection'], 2);
      expect(c['weeks'], [1, 2, 3]);
      expect(c['examDate'], isNull);
    });

    test('备注按日期分组、考试单独列一份', () {
      final json = buildSnapshotJson(
        semester: semester(),
        courses: courses(),
        notes: [
          Note(date: '2026-10-23', content: '交作业', createdAt: 1),
          Note(date: '2026-10-23', content: '买面包', createdAt: 2),
          Note(date: '2026-10-25', content: '', createdAt: 3),
        ],
        now: DateTime(2026, 10, 22),
      );
      final notes = json['notes'] as Map<String, dynamic>;
      expect(notes['2026-10-23'], ['交作业', '买面包']);
      expect(notes.containsKey('2026-10-25'), isFalse); // 空内容不入快照
      final exams = json['exams'] as List;
      expect(exams.length, 1);
      expect(exams.first['courseName'], '大学英语');
      // examDate = 2026-01-01 00:00 UTC，具体日期随本地时区 ±1 天，只验格式
      expect(exams.first['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}')));
    });

    test('快照里不含任何设置或令牌（隐私底线）', () {
      final json = buildSnapshotJson(
        semester: semester(),
        courses: courses(),
        notes: const [],
        now: DateTime(2026, 10, 22),
      );
      final text = jsonEncode(json);
      expect(text.contains('token'), isFalse);
      expect(text.contains('ghp_'), isFalse);
      expect(text.contains('app_settings'), isFalse);
    });

    test('没有学期时也能出一份可编码的快照', () {
      final json = buildSnapshotJson(
        semester: null,
        courses: const [],
        notes: const [],
        now: DateTime(2026, 10, 22),
      );
      expect(json['semester'], isNull);
      expect(json['courses'], isEmpty);
      expect(jsonEncode(json), isA<String>());
    });
  });

  group('规范 id（复审 B3：文件名说了算）', () {
    test('正文 id 与文件名不一致时强制用文件名 id 并标记 mismatched', () {
      final raw = jsonEncode({
        'id': 'cmd-body-id',
        'createdAt': '2026-10-22T10:00:00',
        'commands': [
          {'type': 'add_note', 'date': '2026-10-23', 'content': '交作业'},
        ],
      });
      final result =
          parseCanonicalCommandBatch(raw, canonicalId: 'batch_001');
      expect(result.batch, isNotNull);
      expect(result.batch!.id, 'batch_001');
      expect(result.mismatched, isTrue);
      expect(result.batch!.commands.length, 1);
    });

    test('正文 id 与文件名一致时 mismatched 为 false', () {
      final raw = jsonEncode({
        'id': 'batch_002',
        'createdAt': '2026-10-22T10:00:00',
        'commands': [
          {'type': 'add_note', 'date': '2026-10-24', 'content': '复习'},
        ],
      });
      final result =
          parseCanonicalCommandBatch(raw, canonicalId: 'batch_002');
      expect(result.batch!.id, 'batch_002');
      expect(result.mismatched, isFalse);
    });
  });
}
