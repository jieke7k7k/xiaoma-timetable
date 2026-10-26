import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/ui/page_transitions.dart';
import 'package:xiaoma_timetable/widgets/ai_route_guard.dart';

/// 2.1.0 返修测试：转场 300ms 与 AI 路由守卫。
void main() {
  group('页面转场（WB_SPEC_212 第 5 节）', () {
    test('正向与返回时长均为 300ms', () {
      const builder = AppSlidePageTransitionsBuilder(android: true);
      expect(builder.transitionDuration, const Duration(milliseconds: 300));
      expect(
        builder.reverseTransitionDuration,
        const Duration(milliseconds: 300),
      );
      const iosBuilder = AppSlidePageTransitionsBuilder(android: false);
      expect(iosBuilder.transitionDuration, const Duration(milliseconds: 300));
    });
  });

  group('AI 路由守卫（AiRouteGuard）', () {
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

    Future<void> pumpGuarded(WidgetTester tester) async {
      // 沿用其它 FFI 测试的既定模式：runAsync 里给真库留出读写时间，
      // 再多 pump 几帧，让 provider 加载 → 守卫判定 → 跳转依次走完。
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              routes: {
                '/settings': (context) =>
                    const Scaffold(body: Text('设置页')),
              },
              home: const Scaffold(
                body: AiRouteGuard(child: Text('AI 内容')),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('未解锁：不显示 AI 内容，退无可退时替换为设置页', (tester) async {
      await pumpGuarded(tester);
      expect(find.text('AI 内容'), findsNothing);
      expect(find.text('设置页'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));

    testWidgets('已解锁：原样显示 AI 内容', (tester) async {
      await tester.runAsync(() async {
        await Dao.instance.setSetting('developer_options_unlocked', '1');
      });
      await pumpGuarded(tester);
      expect(find.text('AI 内容'), findsOneWidget);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
