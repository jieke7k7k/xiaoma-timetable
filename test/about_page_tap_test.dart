import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/about_page.dart';

/// 关于页版本行「连点无响应」测试（2.1.3 WB_SPEC_214 第 5 节）
///
/// 2.1.2 及以前版本行是隐藏入口：连点 5 次解锁、写设置、弹提示。2.1.3 把它改回
/// 纯展示，本文件就是防止它被重新接上手势——连点 5~10 次必须：
/// 1. 不跳转（导航栈 push 次数不变，仍在关于页）；
/// 2. 不弹任何提示（无 SnackBar / Dialog）；
/// 3. 不写任何设置（数据库 app_settings 一条都没多）；
/// 4. 版本行本身文案与状态不变（没有加载态、没有闪烁）。
class _PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

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
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.1.3',
      buildNumber: '28',
      buildSignature: '',
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 渲染关于页：真库 + 阻断网络（通道服务会尝试读远端，失败即回退缓存）
  Future<_PushCounter> pumpAbout(WidgetTester tester) async {
    final counter = _PushCounter();
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            MaterialApp(navigatorObservers: [counter], home: const AboutPage()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return counter;
  }

  testWidgets('版本行连点 10 次：无跳转、无提示、不写设置', (tester) async {
    final counter = await pumpAbout(tester);

    final versionRow = find.text('版本 2.1.3（28）');
    expect(versionRow, findsOneWidget, reason: '版本行应正常显示为纯文本');
    final pushesBefore = counter.pushes;
    expect(pushesBefore, 1, reason: '初始只有关于页这一层路由');

    for (var i = 0; i < 10; i++) {
      await tester.tap(versionRow);
      await tester.pump(const Duration(milliseconds: 80));
    }
    // 连点期间可能触发的动画/帧都排空，避免「延迟一跳」被漏判
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    // 1) 没有跳转：仍在关于页，push 次数没变
    expect(find.byType(AboutPage), findsOneWidget);
    expect(counter.pushes, pushesBefore);
    // 2) 没有任何提示
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    // 3) 版本行状态未变（没有 loading 文案、内容一致）
    expect(versionRow, findsOneWidget);
    expect(find.text('版本加载中…'), findsNothing);

    // 4) 一个设置键都没写（旧实现会在第 5 次点击时落库解锁标记）
    final settings = await tester.runAsync(
      () => Dao.instance.getAllSettings(),
    );
    expect(settings, isNotNull);
    expect(settings, isEmpty);
  });

  testWidgets('连点 5 次（阈值）也不触发任何反应', (tester) async {
    final counter = await pumpAbout(tester);
    final versionRow = find.text('版本 2.1.3（28）');
    final pushesBefore = counter.pushes;

    for (var i = 0; i < 5; i++) {
      await tester.tap(versionRow);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(counter.pushes, pushesBefore);
    expect(find.byType(SnackBar), findsNothing);
    final settings = await tester.runAsync(
      () => Dao.instance.getAllSettings(),
    );
    expect(settings, isEmpty);
  });
}
