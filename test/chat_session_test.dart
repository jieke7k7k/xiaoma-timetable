import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/chat_session.dart';
import 'package:xiaoma_timetable/services/chat_session_service.dart';

/// 智能助手历史记录服务层测试（2.0.5 第 3 节）
///
/// 跑在 sqflite_common_ffi 内存库上：覆盖会话的存取（新建 / 更新）、
/// 列表按更新时间倒序、删除，以及消息（含指令 / 执行结果状态）的往返恢复。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
  });

  tearDown(() async {
    await db.close();
  });

  ChatSession session({
    int? id,
    String title = '我明天有什么课',
    int createdAt = 1000,
    int updatedAt = 1000,
    List<ChatMessage>? messages,
  }) =>
      ChatSession(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: updatedAt,
        messages: messages ??
            const [
              ChatMessage(role: 'user', text: '我明天有什么课？', time: 1000),
              ChatMessage(role: 'assistant', text: '明天有高等数学和大学英语。', time: 1001),
            ],
      );

  test('新建会话返回 id，列出来字段往返一致', () async {
    final id = await ChatSessionService.instance
        .saveSession(session(title: '帮我加课', createdAt: 1000, updatedAt: 2000));

    final list = await ChatSessionService.instance.listSessions();
    expect(list.length, 1);
    expect(list.first.id, id);
    expect(list.first.title, '帮我加课');
    expect(list.first.createdAt, 1000);
    expect(list.first.updatedAt, 2000);
    expect(list.first.messages.length, 2);
    expect(list.first.messages.first.role, 'user');
    expect(list.first.messages.first.text, '我明天有什么课？');
  });

  test('同一 id 再保存是更新（标题 / 时间 / 消息都刷新）', () async {
    final id = await ChatSessionService.instance.saveSession(session());
    await ChatSessionService.instance.saveSession(session(
      id: id,
      title: '改过的标题',
      updatedAt: 3000,
      messages: const [ChatMessage(role: 'user', text: '只有一句', time: 3000)],
    ));

    final list = await ChatSessionService.instance.listSessions();
    expect(list.length, 1);
    expect(list.first.title, '改过的标题');
    expect(list.first.updatedAt, 3000);
    expect(list.first.createdAt, 1000);
    expect(list.first.messages.single.text, '只有一句');
  });

  test('列表按更新时间倒序', () async {
    await ChatSessionService.instance
        .saveSession(session(title: '旧对话', updatedAt: 1000));
    await ChatSessionService.instance
        .saveSession(session(title: '新对话', updatedAt: 3000));
    await ChatSessionService.instance
        .saveSession(session(title: '中间对话', updatedAt: 2000));

    final list = await ChatSessionService.instance.listSessions();
    expect(list.map((s) => s.title).toList(), ['新对话', '中间对话', '旧对话']);
  });

  test('删除单条会话，返回是否真的删掉', () async {
    final id = await ChatSessionService.instance.saveSession(session());

    expect(await ChatSessionService.instance.deleteSession(id), isTrue);
    expect(await ChatSessionService.instance.listSessions(), isEmpty);
    // 再删一次：id 不存在，返回 false
    expect(await ChatSessionService.instance.deleteSession(id), isFalse);
  });

  test('消息的指令原文 / 执行结果状态能完整往返', () async {
    final id = await ChatSessionService.instance.saveSession(session(
      messages: [
        const ChatMessage(
          role: 'user',
          text: '给药理学实验加个备注',
          time: 1000,
        ),
        ChatMessage(
          role: 'assistant',
          text: '好的，帮你给课程加备注。',
          time: 1001,
          commands: [
            {'type': 'set_course_remark', 'courseName': '药理学实验', 'remark': '二楼'},
          ],
          resolved: {'0': true},
          results: ['已执行：已把《药理学实验》的课程备注改为：二楼'],
        ),
      ],
    ));

    final restored = (await ChatSessionService.instance.listSessions()).single;
    expect(restored.id, id);
    final assistant = restored.messages.last;
    expect(assistant.commands.single['type'], 'set_course_remark');
    expect(assistant.resolved['0'], isTrue);
    expect(assistant.results.single, contains('二楼'));
  });
}
