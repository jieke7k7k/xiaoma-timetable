import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/widgets/home_tab_bar.dart';

/// WB_SPEC_223：周数跳转条点外面收起（只收起，不触发底下操作）。
///
/// 整页 pump 沿用 week_title_focus_frame_test 的模式：FFI 内存库、
/// PackageInfo 打桩、sundayDialogNow 锁周一、阻断网络。
/// 另种一门周一 1–2 节的课（带周一 9 点考试），覆盖课程卡片点按、
/// 表头点按、长按三条线；路由哨兵记录一切 push（详情表／菜单／
/// 弹窗／新建表／切页都是路由），断言「只收起」时哨兵必须为空。
/// 共 20 例：12 例原有（点按层＋守卫 2／9／10＋滚动＋结构＋语义）＋
/// 8 例 223 复审补测（横幅 4 例 guard 5–8、编辑按钮 guard 1、
/// ⋮ 菜单 guard 3、状态条 guard 4、布局等价）；横幅测试用
/// seedChannelCache 往 channel_state.json 里预置缓存造横幅条件。
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
    final semester = await Dao.instance.getCurrentSemester();
    // 周一 1–2 节的课，全 20 周上；周一 9 点一场考试（表头打红点、
    // 点表头会弹当天考试弹窗——没守卫时这条线会漏）。
    await Dao.instance.insertCourse(
      Course(
        semesterId: semester!.id!,
        name: '药化',
        colorValue: 0xFF6B8E7B,
        dayOfWeek: 1,
        startSection: 1,
        endSection: 2,
        weeks: List.generate(20, (i) => i + 1),
        examDate:
            DateTime(monday.year, monday.month, monday.day, 9)
                .millisecondsSinceEpoch,
      ),
    );
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

  Future<void> pumpHome(
    WidgetTester tester,
    _RouteSpy spy, {
    List<Override> overrides = const [],
    Size physicalSize = const Size(1170, 2532),
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 2.5.0（WB_SPEC_233 §6）底部栏默认关：本文件多数用例走真实 provider 且
    // 依赖「点底部栏」的场景，这里预置「底栏开」+ 一次性迁移标志以保持原语义。
    await tester.runAsync(() async {
      await Dao.instance.setSetting(
        'ui_settings',
        const UiSettings(showBottomBar: true).encode(),
      );
      await Dao.instance.setSetting(UiSettingsNotifier.kDefaultsMigratedKey, '1');
    });

    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: overrides,
              child: MaterialApp(
                home: const HomeShell(),
                navigatorObservers: [spy],
              ),
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
    // 课程卡片要等课程 provider 读库完成后才渲染
    await pumpUntil(tester, find.text('药化'));
    spy.pushed.clear();
  }

  /// 标题 InkWell（点它切换跳转条）。
  Finder titleInkWell() => find.ancestor(
        of: find.textContaining(RegExp(r'^第 \d+ 周')),
        matching: find.byType(InkWell),
      );

  void expectCollapsed(WidgetTester tester) {
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  }

  void expectExpanded(WidgetTester tester) {
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  }

  /// 纵向滚动条的当前位移：按 axis 挑，别用 find.byType(Scrollable).first
  ///（PageView 的横向 Scrollable 也在树里，first 的顺序不可靠）。
  double vPixels(WidgetTester tester) {
    final states = tester.stateList<ScrollableState>(find.byType(Scrollable));
    return states
        .firstWhere((s) => s.position.axis == Axis.vertical)
        .position
        .pixels;
  }

  Future<void> openJumper(WidgetTester tester) async {
    expectCollapsed(tester);
    await tester.tap(titleInkWell());
    // 两次 pump：第一次跑 rebuild、AnimatedSize 刚起动画（第一帧仍按旧尺寸
    // 布局，高度还是 0，此时点跳转条格子会打到下面的网格上）；第二次才把
    // 200ms 动画跑完。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expectExpanded(tester);
  }

  /// 标题当前周次数字（「第 X 周」里的 X）。
  int currentWeek(WidgetTester tester) {
    final text = tester
        .widget<Text>(find.textContaining(RegExp(r'^第 \d+ 周')))
        .data!;
    return int.parse(RegExp(r'\d+').firstMatch(text)!.group(0)!);
  }

  /// 横幅测试用的通道内容（223 复审 Bug 1/2 补测）：
  /// 最新版 2.1.7/2032——PackageInfo 打桩的 buildNumber 是 32，
  /// 2032 > 32 触发更新横幅；一条非重要公告触发公告横幅
  ///（重要公告会走弹窗，不进横幅，所以 level 必须是 normal）。
  const _channelJson = '''
{"latest":{"versionName":"2.1.7","versionCode":2032,"notes":"","downloadUrl":"","releaseUrl":""},
 "announcements":[{"id":"test-ann-1","title":"测试公告","body":"测试公告正文","date":"2026-11-07","level":"normal"}]}
''';

  /// 往 channel_state.json 里预置缓存，让 _loadChannel 首帧就读到通道内容。
  /// _loadChannel 先读 ChannelService.cached()（状态文件里的 cache 字段），
  /// 再静默 fetch（测试环境网络被阻断，fetch 回退缓存）——所以只写缓存就够了，
  /// 不用伪造 HTTP 响应。path_provider 在测试里没接 mock，
  /// getApplicationDocumentsDirectory 会抛 MissingPluginException，
  /// 但 _readState 全 catch 返回 {}，所以这里给它接一个返回临时目录的 mock。
  /// 只在横幅测试里用，用完就清，不影响其他测试。
  Future<void> seedChannelCache(WidgetTester tester) async {
    final tempDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('channel-test-'),
    );
    // runAsync 的返回是可空的，createTemp 不会真返回 null，这里断言一次
    // 拿到非空路径，后面 mock、写文件、tearDown 清理都用它。
    final dirPath = tempDir!.path;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return dirPath;
      }
      return null;
    });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await Directory(dirPath).delete(recursive: true);
    });
    await tester.runAsync(() async {
      final f = File('$dirPath/channel_state.json');
      await f.writeAsString(jsonEncode({
        'cache': _channelJson,
        'seenIds': <String>[],
        'dismissedIds': <String>[],
      }));
    });
  }

  /// 某横幅的关闭按钮：两个横幅的关闭按钮 tooltip 都是「关闭」，
  /// 按纵坐标区分——更新横幅在上、公告横幅在下。
  Future<void> tapBannerClose(
    WidgetTester tester, {
    required bool first,
  }) async {
    final closes = find.byTooltip('关闭');
    expect(closes, findsNWidgets(2));
    final centers = closes.evaluate().map((e) {
      final box = e.renderObject as RenderBox;
      return box.localToGlobal(box.size.center(Offset.zero));
    }).toList()
      ..sort((a, b) => a.dy.compareTo(b.dy));
    await tester.tapAt(first ? centers.first : centers.last);
  }

  /// 当前／下一节课状态条：三种文案之一（正在上课／下一节／近期暂无课程）。
  Finder focusBarText() =>
      find.textContaining(RegExp(r'正在上课|下一节|近期暂无课程'));

  testWidgets('点课程卡片只收起：详情不打开', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(find.text('药化'));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 卡片本身还在（没进详情、没消失）
    expect(find.text('药化'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点表头某天只收起：考试弹窗不出现', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    // 周一格（'一'）：当天有考试，平时点它弹当天考试弹窗
    await tester.tap(find.text('一'));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    expect(find.textContaining('日的考试'), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点底部栏「设置」只收起：不切页', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(find.byKey(kHomeTabBarSettingsKey));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 还停留在课表视图，没进设置页
    expect(find.byType(WeekViewPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点底部栏「课表」只收起：不回本周', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    // 先切到非本周（点跳转条第 12 周），再点底部栏「课表」格
    await openJumper(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AnimatedSize),
        matching: find.text('12'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentWeek(tester), 12);
    expectCollapsed(tester);

    await openJumper(tester);
    await tester.tap(find.byKey(kHomeTabBarScheduleKey));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 周次没变（没触发回到本周）
    expect(currentWeek(tester), 12);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点右上角「＋」只收起：新建表不出现', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    expect(find.text('手动新建课程'), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('纵向拖动收起且滚动继续', (tester) async {
    final spy = _RouteSpy();
    // 默认开着「自适应一屏」，网格恰好一屏、纵向没有滚动余量，
    // 拖了也量不到位移——这里把 autoFit 关掉（固定 46 格高）。
    // 还要把视口压矮（390×500 逻辑）：全高 844 时纵向 maxScrollExtent
    // 实测在 0.0～87.5 之间飘（横幅异步加载会改网格高度），拖动量不到；
    // 矮视口下滚动余量稳定在 250 以上，拖动位移才可测。
    await pumpHome(
      tester,
      spy,
      overrides: [
        uiSettingsProvider.overrideWith(_FixedUiSettingsNotifier.new),
      ],
      physicalSize: const Size(1170, 1500),
    );
    await openJumper(tester);

    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsOneWidget);
    final before = vPixels(tester);
    // 必须用 timedDrag，不能用 tester.drag：drag 内部只发两段位移
    //（先一段 18px、再一段余量），而 SingleChildScrollView 是
    // DragStartBehavior.start + 本页 touchSlop 30——第一段没过阈值，
    // 第二段过阈值那一下整段位移被当作「拖动起点」丢掉，松手时还没
    // 有过一次有效滚动，量到 0。timedDrag 按 60Hz 发多段小位移，
    // 过阈值后的位移才会真正滚动（实测可滚满 maxScrollExtent）。
    await tester.timedDrag(
      scrollable,
      const Offset(0, -300),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    final after = vPixels(tester);
    // 滚动真的发生了（点按层没把拖动吞掉）
    expect(after, greaterThan(before));
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('横向滑切周收起且周次真的切了', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    final weekBefore = currentWeek(tester);
    await openJumper(tester);

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pump(const Duration(milliseconds: 500));

    expectCollapsed(tester);
    expect(currentWeek(tester), weekBefore + 1);
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('长按课程卡片只收起：菜单／高亮都不出', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.longPress(find.text('药化'));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 高亮选区中央的加号图标没出现（长按没起高亮）
    expect(find.byIcon(Icons.add), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点标题切换照常：收起后再点重新展开', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(titleInkWell());
    await tester.pump(const Duration(milliseconds: 300));
    expectCollapsed(tester);

    await tester.tap(titleInkWell());
    await tester.pump(const Duration(milliseconds: 300));
    expectExpanded(tester);
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点周数格子跳周＋收起', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(AnimatedSize),
        matching: find.text('12'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expectCollapsed(tester);
    expect(currentWeek(tester), 12);
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('结构：AnimatedSize 顶部对齐＋缓动，收起占位只缩高度',
      (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);

    final animatedSize =
        tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(animatedSize.alignment, Alignment.topCenter);
    expect(animatedSize.curve, Curves.easeOutCubic);
    // 收起态子节点：宽无限、高 0（只做纯高度动画）
    final placeholder = animatedSize.child as SizedBox;
    expect(placeholder.width, double.infinity);
    expect(placeholder.height, 0);
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('语义：展开时标题带 expanded', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    final node = tester.getSemantics(
      find.textContaining(RegExp(r'^第 \d+ 周')),
    );
    expect(node.flagsCollection.isExpanded, Tristate.isTrue);
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });

  // ── 223 复审补测（Bug 1 高、Bug 2 中、Bug 4 低）─────────────────

  testWidgets('点更新横幅「去看看」只收起：不进关于页', (tester) async {
    final spy = _RouteSpy();
    await seedChannelCache(tester);
    await pumpHome(tester, spy);
    await pumpUntil(tester, find.text('有新版本 2.1.7 可用'));
    await openJumper(tester);

    await tester.tap(find.text('去看看'));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 横幅还在（守卫拦住了跳转，没进 /about）
    expect(find.text('有新版本 2.1.7 可用'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点更新横幅关闭按钮只收起：横幅不消失', (tester) async {
    final spy = _RouteSpy();
    await seedChannelCache(tester);
    await pumpHome(tester, spy);
    await pumpUntil(tester, find.text('有新版本 2.1.7 可用'));
    await openJumper(tester);

    await tapBannerClose(tester, first: true);
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 横幅还在（守卫拦住了 dismiss，没被关掉）
    expect(find.text('有新版本 2.1.7 可用'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点公告横幅「查看」只收起：不进公告页', (tester) async {
    final spy = _RouteSpy();
    await seedChannelCache(tester);
    await pumpHome(tester, spy);
    await pumpUntil(tester, find.text('公告：测试公告'));
    await openJumper(tester);

    await tester.tap(find.text('查看'));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 横幅还在（守卫拦住了跳转，没进 /announcements）
    expect(find.text('公告：测试公告'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点公告横幅关闭按钮只收起：横幅不消失', (tester) async {
    final spy = _RouteSpy();
    await seedChannelCache(tester);
    await pumpHome(tester, spy);
    await pumpUntil(tester, find.text('公告：测试公告'));
    await openJumper(tester);

    await tapBannerClose(tester, first: false);
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 横幅还在（守卫拦住了 dismiss，没被关掉）
    expect(find.text('公告：测试公告'), findsOneWidget);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点编辑按钮只收起：编辑模式不开', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 编辑模式没开：「完成」按钮和开启提示都没出现
    expect(find.text('完成'), findsNothing);
    expect(find.textContaining('编辑模式已开启'), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点 ⋮ 只收起：菜单不弹出', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);
    await openJumper(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 菜单没弹出来：展开时 ⋮ 是普通按钮（guard 3 的结构性替换），
    // 若被改回 PopupMenuButton，这一下会弹出菜单项。
    expect(find.byType(PopupMenuItem), findsNothing);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('点状态条只收起：不回本周', (tester) async {
    final spy = _RouteSpy();
    // 状态条默认关着（showClassBroadcast 默认 false），这里打开它。
    await pumpHome(
      tester,
      spy,
      overrides: [
        uiSettingsProvider.overrideWith(_BroadcastUiSettingsNotifier.new),
      ],
    );
    // 先切到非本周（第 12 周），再展开、点状态条
    await openJumper(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AnimatedSize),
        matching: find.text('12'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(currentWeek(tester), 12);
    expectCollapsed(tester);

    await openJumper(tester);
    await tester.tap(focusBarText());
    await tester.pump(const Duration(milliseconds: 300));

    expectCollapsed(tester);
    expect(spy.pushed, isEmpty);
    // 周次没变（没触发回到本周）
    expect(currentWeek(tester), 12);
    await tester.pump(const Duration(seconds: 60));
  });

  testWidgets('布局等价：网格高＝剩余空间－表头－分割线', (tester) async {
    final spy = _RouteSpy();
    await pumpHome(tester, spy);

    // 223 把表头＋分割线＋网格收进同一个 Expanded 的 Stack，
    // 规格 §3.2 承诺网格高度与重组前一致（先扣表头＋分割线再把
    // 剩余分给网格）。这里直接量三者：分割线高 1，网格顶边紧贴
    // 分割线底边、底边与 Stack 底边重合，表头＋1＋网格＝Stack 高。
    void expectGridFillsStack() {
      final stack = find.byWidgetPredicate(
        (w) => w is NotificationListener<ScrollStartNotification>,
      );
      expect(stack, findsOneWidget);
      final divider = find.byType(Divider);
      expect(divider, findsOneWidget);
      final scrollable = find.byType(SingleChildScrollView);
      expect(scrollable, findsOneWidget);
      final stackTop = tester.getTopLeft(stack).dy;
      final stackBottom = tester.getBottomRight(stack).dy;
      final dividerTop = tester.getTopLeft(divider).dy;
      final scrollTop = tester.getTopLeft(scrollable).dy;
      final scrollBottom = tester.getBottomRight(scrollable).dy;
      expect(scrollTop - dividerTop, 1);
      expect(scrollBottom, stackBottom);
      expect(
        (dividerTop - stackTop) + 1 + tester.getSize(scrollable).height,
        stackBottom - stackTop,
      );
    }

    expectGridFillsStack();
    await openJumper(tester);
    await tester.pump(const Duration(milliseconds: 300));
    // 展开态同样成立：Stack 被跳转条顶掉一块，网格跟着缩一块，
    // 差值正好是跳转条高度，没有多扣也没有少扣。
    expectGridFillsStack();
    expect(spy.pushed, isEmpty);
    await tester.pump(const Duration(seconds: 60));
  });
}

/// 记录一切路由 push 的哨兵：课程详情表、长按菜单、考试弹窗、
/// 新建表、切页全是路由，断言「只收起」时它必须为空。
class _RouteSpy extends NavigatorObserver {
  final pushed = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route.settings.name);
  }
}

/// 固定界面设置（只关 autoFit）：纵向拖动测试用——默认自适应一屏时
/// 网格没有滚动余量，拖动量不到位移。
class _FixedUiSettingsNotifier extends UiSettingsNotifier {
  @override
  Future<UiSettings> build() async =>
      const UiSettings(autoFitHeight: false);
}

/// 固定界面设置（只开状态条）：状态条守卫测试用——
/// showClassBroadcast 默认 false，状态条不渲染。
class _BroadcastUiSettingsNotifier extends UiSettingsNotifier {
  @override
  Future<UiSettings> build() async =>
      const UiSettings(showClassBroadcast: true);
}
