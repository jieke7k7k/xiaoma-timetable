import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/widgets/home_capsule.dart';

/// 悬浮胶囊底部栏测试（WB_SPEC_213 第 2 节）
///
/// 2.1.2 起底部栏以「悬浮胶囊」形态回归：默认开、壳内默认停在课表一级视图，
/// 底部居中胶囊两键［课表｜设置］。断言：
/// 1. 根页面仍渲染 WeekViewPage（课表一级视图）+ 悬浮胶囊；
/// 2. 不再用 IndexedStack 三页签 / NavigationBar / BottomNavigationBar；
/// 3. 胶囊两键存在、无「主页」键（沿用 2.1.1 去底栏后的等价断言口径）；
/// 4. 点「设置」键切到壳内设置根页，且无左上角返回箭头。
///
/// HomeShell 的启动联动 / WeekViewPage 的公告检查会走平台通道与网络，这里用
/// PackageInfo 打桩 + HttpOverrides 阻断网络，并把首帧放进 runAsync 里让真实
/// 的 FFI 数据库操作跑完（否则 sqflite 的锁警告定时器会挂在假时钟上导致
/// 「Timer is still pending」）。断言只针对「主页结构」，不依赖这些侧效结果。
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
      version: '2.1.2',
      buildNumber: '27',
      buildSignature: '',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            const ProviderScope(child: MaterialApp(home: HomeShell())),
          );
          await tester.pump();
          // 让启动联动里的真实 FFI 数据库操作在这里跑完并释放锁定时器
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    await tester.pump();
  }

  testWidgets('主页渲染 WeekViewPage + 悬浮胶囊两键，无 IndexedStack/NavigationBar', (tester) async {
    await pumpHome(tester);

    // 课表一级视图 + 悬浮胶囊都存在
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(HomeCapsule), findsOneWidget);
    // 三页签结构已删除（胶囊是自绘悬浮胶囊，不是系统底栏）
    expect(find.byType(IndexedStack), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // 胶囊两键，无「主页」键
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主页'), findsNothing);

    // 卸载主页，取消 WeekViewPage 的分钟级刷新定时器
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点胶囊设置键切到壳内设置根页，且无返回箭头', (tester) async {
    await pumpHome(tester);

    // 此刻只有胶囊上的「设置」键这一处文字
    await tester.tap(find.text('设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SettingsPage), findsOneWidget);
    // 壳内一级视图：设置根页不显示左上角返回箭头
    expect(find.byType(BackButton), findsNothing);

    // 设置页挂载触发的两次数据库查询各带一个 10 秒锁警告定时器（假时钟），
    // 测完前把假时钟拨过 10 秒让它们触发释放，否则 teardown 报 Timer pending。
    // 注意：runAsync 的真实延时拨不动假时钟，这里必须用 pump 推进假时间。
    await tester.pump(const Duration(seconds: 11));

    await tester.pumpWidget(const SizedBox());
  });
}
