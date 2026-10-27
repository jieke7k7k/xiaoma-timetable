import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/widgets/home_capsule.dart';

/// 悬浮胶囊纯 UI 测试（WB_SPEC_213 第 2/3 节）
///
/// [HomeCapsule] 不依赖 Riverpod（解锁状态由构造参数传入），可直接构造做
/// widget 测试，无需打 DB/网络：
/// 1. 未解锁两键［课表｜设置］、无助手键；
/// 2. 解锁三键［助手｜课表｜设置］、课表居中；
/// 3. 课表键 / 设置键回调正确（课表键双职责由 HomeShell 层封装，这里只验键回调）；
/// 4. 助手键 Push 全屏聊天页（无胶囊、有返回键）。
void main() {
  Widget wrap(HomeCapsule capsule) => MaterialApp(
    routes: {
      // 真实 /ai-chat 是 AiRouteGuard(AiChatPage)，自带 AppBar（返回箭头）且无胶囊
      '/ai-chat': (_) => Scaffold(
        appBar: AppBar(title: Text('智能助手')),
        body: Text('聊天页占位'),
      ),
    },
    home: Scaffold(body: Center(child: capsule)),
  );

  testWidgets('未解锁：两键［课表｜设置］，无助手键', (tester) async {
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
          unlocked: false,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ),
    );

    expect(find.text('课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('助手'), findsNothing);
  });

  testWidgets('解锁：三键［助手｜课表｜设置］，课表居中', (tester) async {
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
          unlocked: true,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ),
    );

    expect(find.text('助手'), findsOneWidget);
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    // 课表居中：助手在课表左侧、设置在课表右侧
    final a = tester.getCenter(find.text('助手'));
    final b = tester.getCenter(find.text('课表'));
    final c = tester.getCenter(find.text('设置'));
    expect(a.dx, lessThan(b.dx));
    expect(b.dx, lessThan(c.dx));
  });

  testWidgets('课表键与设置键回调', (tester) async {
    HomeShellTab? selected;
    var scheduleTaps = 0;
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
          unlocked: false,
          onSelectTab: (t) => selected = t,
          onTapSchedule: () => scheduleTaps++,
        ),
      ),
    );

    await tester.tap(find.text('设置'));
    expect(selected, HomeShellTab.settings);

    await tester.tap(find.text('课表'));
    expect(scheduleTaps, 1);
  });

  testWidgets('助手键：Push 全屏聊天页（无胶囊、有返回键）', (tester) async {
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
          unlocked: true,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ),
    );

    await tester.tap(find.text('助手'));
    await tester.pumpAndSettle();

    // 聊天页是独立全屏路由：看不到胶囊、能看到返回键与占位内容
    expect(find.text('聊天页占位'), findsOneWidget);
    expect(find.byType(HomeCapsule), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('字体放大 1.3 倍：胶囊不纵向溢出（复审 P0-1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: Center(
              child: HomeCapsule(
                activeTab: HomeShellTab.schedule,
                unlocked: true,
                onSelectTab: (_) {},
                onTapSchedule: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('助手'), findsOneWidget);
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
