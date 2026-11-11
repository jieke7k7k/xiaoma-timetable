import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/services/notification_service.dart';

/// WB_SPEC_231 第 4.2–4.4 节：提醒 / 常驻通知开关的权限事务（拒了开关不亮）。
///
/// 老 bug：通知权限被拒只弹一个 SnackBar，`setEnabled(true)` 照样执行，
/// 开关亮着但提醒收不到。现在：
/// - 通知被拒 → 开关保持 false（且不写库）+ 带引导的确认框；
/// - 通知通过 + 精确闹钟未授权 → 开关 true、降级为非精确排期、常驻轻量提示；
/// - 通知通过 + 精确闹钟已授权 → 开关 true、没有多余弹窗；
/// - 电池优化只在首次成功开启提醒后提示一次（标记 battery_hint_shown）。
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
    // 默认按「已授权 + 精确闹钟已授权」起步，各用例按需改写
    NotificationService.debugEnsurePermissionOverride = () async => true;
    NotificationService.debugCanScheduleExactOverride = () async => true;
  });

  tearDown(() async {
    NotificationService.debugEnsurePermissionOverride = null;
    NotificationService.debugCanScheduleExactOverride = null;
    await db.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: RemindersSettingsPage())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<String?> readSetting(WidgetTester tester, String key) async {
    return tester.runAsync<String?>(() => Dao.instance.getSetting(key));
  }

  /// 点一下并给真实异步留窗口：写库 → setState → 重排提醒都是一段段真实 Future，
  /// 只在 runAsync 的窗口里才会推进（假异步里会一直挂着）
  Future<void> tapAndDrain(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapReminder(WidgetTester tester) =>
      tapAndDrain(tester, find.widgetWithText(SwitchListTile, '上课提醒'));

  testWidgets('通知权限被拒：开关保持 false、不写库、弹带引导的确认框', (tester) async {
    NotificationService.debugEnsurePermissionOverride = () async => false;
    await pumpPage(tester);

    await tapReminder(tester);

    expect(find.text('需要通知权限'), findsOneWidget);
    expect(
      find.text('需要开启通知权限才能发送上课提醒，是否前往系统设置开启？'),
      findsOneWidget,
    );
    expect(find.text('去设置'), findsOneWidget);
    final tile =
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '上课提醒'));
    expect(tile.value, isFalse, reason: '被拒时开关绝不能变成 true');
    expect(await readSetting(tester, 'reminder_enabled'), isNull, reason: '被拒时不写库');

    await tester.tap(find.text('暂不'));
    await tester.pumpAndSettle();
    expect(find.text('需要通知权限'), findsNothing);
  });

  testWidgets('通知通过 + 精确闹钟未授权：开关 true、轻量提示出现、电池提示只一次', (tester) async {
    NotificationService.debugCanScheduleExactOverride = () async => false;
    await pumpPage(tester);

    await tapReminder(tester);

    final tile =
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '上课提醒'));
    expect(tile.value, isTrue, reason: '降级为非精确排期，但开关要保持开');
    // 精确闹钟说明框先来
    expect(find.text('开启精确闹钟'), findsOneWidget);
    await tapAndDrain(tester, find.text('暂不'));

    // 开关行下方的轻量提示（不是弹窗）
    expect(find.text('精确闹钟未授权，提醒可能延迟几分钟'), findsOneWidget);
    // 首次开提醒成功 → 电池优化提示一次
    expect(find.textContaining('建议在电池优化列表里把小马课表设为'), findsOneWidget);
    expect(await readSetting(tester, 'battery_hint_shown'), '1');
  });

  testWidgets('通知通过 + 精确闹钟已授权：开关 true、无多余弹窗', (tester) async {
    await pumpPage(tester);

    await tapReminder(tester);

    final tile =
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '上课提醒'));
    expect(tile.value, isTrue);
    expect(find.text('开启精确闹钟'), findsNothing);
    expect(find.text('精确闹钟未授权，提醒可能延迟几分钟'), findsNothing);
  });

  testWidgets('电池提示只出现一次：标记已写过就不再提示', (tester) async {
    await tester.runAsync(
      () => Dao.instance.setSetting('battery_hint_shown', '1'),
    );
    await pumpPage(tester);

    await tapReminder(tester);

    expect(find.textContaining('建议在电池优化列表里把小马课表设为'), findsNothing);
  });

  testWidgets('今日课程常驻通知：通知未授权时拨开保持关 + 确认框', (tester) async {
    await tester.runAsync(
      () => Dao.instance.setSetting('ongoing_enabled', '0'),
    );
    NotificationService.debugEnsurePermissionOverride = () async => false;
    await pumpPage(tester);

    await tapAndDrain(
      tester,
      find.widgetWithText(SwitchListTile, '今日课程常驻通知'),
    );

    expect(
      find.text('需要开启通知权限才能在通知栏常驻显示今日课程，是否前往系统设置开启？'),
      findsOneWidget,
    );
    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '今日课程常驻通知'),
    );
    expect(tile.value, isFalse);
    expect(await readSetting(tester, 'ongoing_enabled'), '0', reason: '被拒时不改成 1');
  });

  testWidgets('今日课程常驻通知：通知已授权时正常开启', (tester) async {
    await tester.runAsync(
      () => Dao.instance.setSetting('ongoing_enabled', '0'),
    );
    await pumpPage(tester);

    await tapAndDrain(
      tester,
      find.widgetWithText(SwitchListTile, '今日课程常驻通知'),
    );

    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '今日课程常驻通知'),
    );
    expect(tile.value, isTrue);
    expect(await readSetting(tester, 'ongoing_enabled'), '1');
  });
}
