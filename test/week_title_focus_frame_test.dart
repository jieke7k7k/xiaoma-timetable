import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';

/// WB_SPEC_221：左上角周数按钮展开态聚焦框。
///
/// - 收起态：1.5 宽透明边框占位（防切换抖动）、底透明、箭头向下；
/// - 展开态：边框 primary(0.75)、底 primary(0.10)、箭头向上且变 primary、
///   文字变 primary；边框宽仍 1.5；
/// - 文字文案、字号（17）、字重（bold）两态都不变。
/// 整页 pump 沿用 home_shell_test 的模式：FFI 内存库、PackageInfo 打桩、
/// sundayDialogNow 锁周一、阻断网络。
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
      version: '2.1.7',
      buildNumber: '32',
      buildSignature: '',
    );
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    // 锁周日时钟，避免周日弹窗 barrier 挡住标题点击
    sundayDialogNow = () => monday;
    String two(int v) => v.toString().padLeft(2, '0');
    final start = '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    final existing = await Dao.instance.getCurrentSemester();
    if (existing == null) {
      await Dao.instance.insertSemester(
        Semester(name: '测试学期', startDate: start, isCurrent: true),
      );
    } else {
      await Dao.instance.updateSemester(existing.copyWith(startDate: start));
    }
  });

  tearDown(() async {
    sundayDialogNow = DateTime.now;
    await db.close();
  });

  /// 反复「真实等待 + 推进假时钟」直到目标出现：学期 provider 首帧是
  /// 真实异步读库，单次 pump 拿不到数据（周视图停在加载态，AppBar 还没出来）。
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    int rounds = 25,
  }) async {
    for (var i = 0; i < rounds; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(home: HomeShell()),
            ),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    await tester.pump();
    await pumpUntil(tester, find.byIcon(Icons.more_vert));
  }

  /// 标题 InkWell 里的 AnimatedContainer（承载聚焦框边框与底色）。
  AnimatedContainer titleFrame(WidgetTester tester) {
    final title = find.ancestor(
      of: find.textContaining(RegExp(r'^第 \d+ 周')),
      matching: find.byType(AnimatedContainer),
    );
    expect(title, findsOneWidget);
    return tester.widget<AnimatedContainer>(title);
  }

  /// 标题文字的当前样式。标题外层还有主题自带的 AnimatedDefaultTextStyle，
  /// 不能用 ancestor 硬找——按 17px 字号精准定位我加的那一层。
  TextStyle titleTextStyle(WidgetTester tester) {
    final animated = find.byWidgetPredicate(
      (w) => w is AnimatedDefaultTextStyle && w.style.fontSize == 17,
    );
    expect(animated, findsOneWidget);
    return tester.widget<AnimatedDefaultTextStyle>(animated).style;
  }

  testWidgets('收起态：透明边框占位 1.5、底透明、箭头向下、文字 17px 粗体',
      (tester) async {
    await pumpHome(tester);

    final frame = titleFrame(tester);
    final decoration = frame.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, Colors.transparent);
    expect(decoration.color, Colors.transparent);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    final style = titleTextStyle(tester);
    expect(style.fontSize, 17);
    expect(style.fontWeight, FontWeight.bold);

    // 清掉 App 启动联动留下的挂起 Timer（220 轮教训：结尾不 pump 满假时间
    // 会报 "A Timer is still pending"）。
    await tester.pump(const Duration(seconds: 60));
  });

  /// 收起态前置断言（复审 L3）：点标题前先确认当前确在收起态，
  /// 否则首帧即展开时报错位置会后移、定位绕。
  void expectCollapsed(WidgetTester tester) {
    final frame = titleFrame(tester);
    final decoration = frame.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, Colors.transparent);
    expect(decoration.color, Colors.transparent);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
  }

  testWidgets('点标题展开：框变 primary 描边＋淡底，箭头文字同变 primary',
      (tester) async {
    await pumpHome(tester);
    expectCollapsed(tester);

    final primary = Theme.of(
      tester.element(find.byType(WeekViewPage)),
    ).colorScheme.primary;

    final titleInkWell = find.ancestor(
      of: find.textContaining(RegExp(r'^第 \d+ 周')),
      matching: find.byType(InkWell),
    );
    expect(titleInkWell, findsOneWidget);
    await tester.tap(titleInkWell);
    // 180ms 过渡动画跑完（pumpAndSettle 在真实 FFI 定时器下易挂，
    // 用推进假时钟代替）
    await tester.pump(const Duration(milliseconds: 300));

    final frame = titleFrame(tester);
    final decoration = frame.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, primary.withValues(alpha: 0.75));
    expect(decoration.color, primary.withValues(alpha: 0.10));
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    final arrow =
        tester.widget<Icon>(find.byIcon(Icons.expand_less));
    expect(arrow.color, primary);
    expect(titleTextStyle(tester).color, primary);

    // 清掉 App 启动联动留下的挂起 Timer（220 轮教训：结尾不 pump 满假时间
    // 会报 "A Timer is still pending"）。
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('再点收起：框与底回透明、箭头回向下，文字文案不变',
      (tester) async {
    await pumpHome(tester);
    expectCollapsed(tester);

    final titleInkWell = find.ancestor(
      of: find.textContaining(RegExp(r'^第 \d+ 周')),
      matching: find.byType(InkWell),
    );
    await tester.tap(titleInkWell);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    await tester.tap(titleInkWell);
    await tester.pump(const Duration(milliseconds: 300));

    final frame = titleFrame(tester);
    final decoration = frame.decoration as BoxDecoration;
    final border = decoration.border as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, Colors.transparent);
    expect(decoration.color, Colors.transparent);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // 文案、字号、字重两态都不变
    final style = titleTextStyle(tester);
    expect(style.fontSize, 17);
    expect(style.fontWeight, FontWeight.bold);
    expect(
      find.textContaining(RegExp(r'^第 \d+ 周')),
      findsOneWidget,
    );

    // 清掉 App 启动联动留下的挂起 Timer（220 轮教训：结尾不 pump 满假时间
    // 会报 "A Timer is still pending"）。
    await tester.pump(const Duration(seconds: 60));
  });
}
