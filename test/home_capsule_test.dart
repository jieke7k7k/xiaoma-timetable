import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/widgets/home_capsule.dart';

/// 悬浮胶囊纯 UI 测试（WB_SPEC_213 第 2/3 节；2.1.3 WB_SPEC_214 第 1 节改写）
///
/// [HomeCapsule] 不依赖 Riverpod（选中态由构造参数传入），可直接构造做
/// widget 测试，无需打 DB/网络。2.1.3 起胶囊恒为两键，断言：
/// 1. 只有［课表｜设置］两键，第三个键（此前解锁后才会出现的那一个）不存在；
/// 2. 无该键的图标、无 Push 路由动作——点两键只走回调，不产生新页面；
/// 3. 课表键 / 设置键回调正确（课表键双职责由 HomeShell 层封装，这里只验键回调）；
/// 4. 字体放大 1.3 倍时胶囊不纵向溢出。
void main() {
  Widget wrap(HomeCapsule capsule) =>
      MaterialApp(home: Scaffold(body: Center(child: capsule)));

  /// 胶囊内的可点键数量：用 InkWell 计数比找文案更抗改文案
  int keyCount(WidgetTester tester) => tester.widgetList<InkWell>(
    find.descendant(
      of: find.byType(HomeCapsule),
      matching: find.byType(InkWell),
    ),
  ).length;

  testWidgets('恒两键［课表｜设置］，无第三个键、无对应图标', (tester) async {
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ),
    );

    expect(find.text('课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(keyCount(tester), 2);
    // 第三个键（此前解锁后出现的那个）的图标必须彻底消失
    expect(find.byIcon(Icons.smart_toy_outlined), findsNothing);
  });

  testWidgets('课表键与设置键回调', (tester) async {
    HomeShellTab? selected;
    var scheduleTaps = 0;
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
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

  testWidgets('选中态跟随 activeTab：设置选中时课表不高亮', (tester) async {
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.settings,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ),
    );

    final scheme = Theme.of(
      tester.element(find.byType(HomeCapsule)),
    ).colorScheme;
    final settingsText = tester.widget<Text>(find.text('设置'));
    final scheduleText = tester.widget<Text>(find.text('课表'));
    expect(settingsText.style?.color, scheme.primary);
    expect(scheduleText.style?.color, scheme.onSurfaceVariant);
  });

  testWidgets('两键都不 Push 新页面（纯视图切换）', (tester) async {
    await tester.pumpWidget(
      wrap(
        HomeCapsule(
          activeTab: HomeShellTab.schedule,
          onSelectTab: (_) {},
          onTapSchedule: () {},
        ),
      ),
    );

    await tester.tap(find.text('课表'));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 仍在同一页：胶囊还在、没有额外路由压栈（有返回箭头就说明 Push 了）
    expect(find.byType(HomeCapsule), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('字体放大 1.3 倍：胶囊不纵向溢出（复审 P0-1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Center(
              child: HomeCapsule(
                activeTab: HomeShellTab.schedule,
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
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
