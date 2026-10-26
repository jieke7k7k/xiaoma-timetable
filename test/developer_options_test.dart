import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/tap_unlock.dart';

/// 开发者选项解锁测试（WB_SPEC_212 第 3 节）
///
/// 覆盖：
/// 1. [TapUnlockCounter] 纯函数：5 次窗口内解锁、不足 5 次不解锁、
///    超 2 秒窗口不解锁（误触不提示）；
/// 2. [DeveloperOptionsNotifier] 持久化：默认未解锁、unlock 落库；
/// 3. [SettingsPage]：未解锁时无任何 AI 入口、无开发者选项；解锁后出现
///    「开发者选项」入口。
void main() {
  group('TapUnlockCounter 纯函数（单调时钟）', () {
    // 可注入的单调时钟：测试手动推进，与系统墙钟无关——
    // 墙钟回拨/前跳不影响窗口判断（2.1.0 返修 P1）。
    test('5 次点击全落在 2 秒窗口内 → 第 5 次解锁', () {
      var now = Duration.zero;
      final counter = TapUnlockCounter(monotonicNow: () => now);
      expect(counter.tap(), isFalse); // 1
      now = const Duration(milliseconds: 400);
      expect(counter.tap(), isFalse);
      now = const Duration(milliseconds: 800);
      expect(counter.tap(), isFalse);
      now = const Duration(milliseconds: 1200);
      expect(counter.tap(), isFalse);
      now = const Duration(milliseconds: 1600);
      expect(counter.tap(), isTrue);
    });

    test('不足 5 次不解锁', () {
      var now = Duration.zero;
      final counter = TapUnlockCounter(monotonicNow: () => now);
      counter.tap();
      now = const Duration(milliseconds: 400);
      counter.tap();
      now = const Duration(milliseconds: 800);
      counter.tap();
      now = const Duration(milliseconds: 1200);
      expect(counter.tap(), isFalse);
    });

    test('超 2 秒窗口：旧点击被丢弃，不解锁（误触不提示）', () {
      var now = Duration.zero;
      final counter = TapUnlockCounter(monotonicNow: () => now);
      counter.tap();
      now = const Duration(milliseconds: 600);
      counter.tap();
      now = const Duration(milliseconds: 1200);
      counter.tap();
      now = const Duration(milliseconds: 1800);
      counter.tap();
      // 第 5 次距第一次已超 2 秒，第一次被移出窗口 → 仍不足 5 次
      now = const Duration(milliseconds: 2400);
      expect(counter.tap(), isFalse);
    });
  });

  group('DeveloperOptionsNotifier 持久化 + SettingsPage 显示（FFI 内存库）', () {
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

    test('默认未解锁（空库）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(developerOptionsProvider.future), isFalse);
    });

    test('unlock 落库 "1" 并更新状态，返回 true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(developerOptionsProvider.notifier);
      await container.read(developerOptionsProvider.future);

      expect(await notifier.unlock(), isTrue);
      expect(await Dao.instance.getSetting('developer_options_unlocked'), '1');
      expect(container.read(developerOptionsProvider).value, isTrue);
    });

    testWidgets('未解锁：设置页无任何 AI 入口、无开发者选项', (tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsPage())),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 解锁前不得出现任何 AI 字样与入口
      expect(find.textContaining('智能助手'), findsNothing);
      expect(find.text('开发者选项'), findsNothing);
      // 新增的菜单管理 / 更多工具仍在
      expect(find.text('菜单管理'), findsOneWidget);
      expect(find.text('更多工具'), findsOneWidget);
    });

    testWidgets('解锁后：设置页出现开发者选项入口', (tester) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await Dao.instance.setSetting('developer_options_unlocked', '1');
        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: SettingsPage())),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('开发者选项'), findsOneWidget);
    });
  });
}
