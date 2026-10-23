import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/chat_session.dart';
import 'package:xiaoma_timetable/models/operation_log.dart';
import 'package:xiaoma_timetable/pages/ai_history_page.dart';
import 'package:xiaoma_timetable/services/chat_session_service.dart';

/// 智能助手历史记录页 widget 测试（2.0.5 第 3 / 4 节）
///
/// 内存库 + 预置数据：断言「对话」Tab 列表存在性（标题 / 消息数）、空状态文案，
/// 以及「操作记录」Tab 的撤回按钮存在。
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

  /// FFI 内存库的读写都要放进 runAsync：先把种子数据写进去、再 pump 页面，
  /// 等真实异步完成后再切回 fake async 逐帧 pump。
  Future<void> pumpHistory(
    WidgetTester tester, {
    Future<void> Function()? seed,
  }) async {
    await tester.runAsync(() async {
      if (seed != null) await seed();
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AiHistoryPage())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('对话 Tab：列出历史会话标题与消息数', (tester) async {
    await pumpHistory(tester, seed: () async {
      await ChatSessionService.instance.saveSession(const ChatSession(
        title: '我明天有什么课',
        createdAt: 1000,
        updatedAt: 2000,
        messages: [
          ChatMessage(role: 'user', text: '我明天有什么课？', time: 1000),
          ChatMessage(role: 'assistant', text: '明天有高等数学。', time: 1001),
        ],
      ));
    });

    expect(find.text('我明天有什么课'), findsOneWidget);
    expect(find.textContaining('2 条消息'), findsOneWidget);
  });

  testWidgets('对话 Tab：没有会话时显示中文空状态', (tester) async {
    await pumpHistory(tester);
    expect(find.text('还没有历史对话'), findsOneWidget);
  });

  testWidgets('对话 Tab：左滑删除点取消，行保留', (tester) async {
    await pumpHistory(tester, seed: () async {
      await ChatSessionService.instance.saveSession(const ChatSession(
        title: '我明天有什么课',
        createdAt: 1000,
        updatedAt: 2000,
        messages: [
          ChatMessage(role: 'user', text: '我明天有什么课？', time: 1000),
        ],
      ));
    });

    expect(find.text('我明天有什么课'), findsOneWidget);

    // 左滑触发 confirmDismiss：应先弹确认框，而不是直接把行滑掉
    await tester.drag(find.text('我明天有什么课'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('删除这段对话？'), findsOneWidget);

    // 点取消 → confirmDismiss 返回 false，行自动弹回、不被误删
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('删除这段对话？'), findsNothing);
    expect(find.text('我明天有什么课').hitTestable(), findsOneWidget);
  });

  testWidgets('操作记录 Tab：列出摘要与撤回按钮', (tester) async {
    await pumpHistory(tester, seed: () async {
      await Dao.instance.insertOperationLog(OperationLog(
        createdAt: 1000,
        source: 'ai',
        summary: '已把《药理学实验》的课程备注改为：二楼',
        snapshot: {'kind': 'set_course_remark', 'courses': []},
      ));
    });

    // 切到「操作记录」Tab
    await tester.tap(find.text('操作记录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('课程备注改为：二楼'), findsOneWidget);
    expect(find.text('撤回'), findsOneWidget);
  });
}
