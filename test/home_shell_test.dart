import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';

/// 去底栏测试（WB_SPEC_212 第 1 节）
///
/// 等价断言：主页（HomeShell）不再渲染 IndexedStack 三页签结构、也不再渲染
/// 底栏（原 `_HomeBottomBar` 已删除），根页面只剩周课表主页 WeekViewPage。
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
      version: '2.1.0',
      buildNumber: '25',
      buildSignature: '',
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('主页只渲染 WeekViewPage，不再有 IndexedStack 与底栏', (tester) async {
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(home: HomeShell()),
            ),
          );
          await tester.pump();
          // 让启动联动里的真实 FFI 数据库操作在这里跑完并释放锁定时器
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });

    // 根页面只剩周课表主页
    expect(find.byType(WeekViewPage), findsOneWidget);
    // 三页签结构已删除
    expect(find.byType(IndexedStack), findsNothing);
    // 底栏（无论系统 NavigationBar 还是自绘底栏）都不存在
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // 原底栏三键文案不再出现
    expect(find.text('主页'), findsNothing);

    // 卸载主页，取消 WeekViewPage 的分钟级刷新定时器
    await tester.pumpWidget(const SizedBox());
  });
}
