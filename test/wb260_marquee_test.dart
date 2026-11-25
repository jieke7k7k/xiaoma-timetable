import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/widgets/marquee_text.dart';

/// WB_SPEC_260：状态条跑马灯 MarqueeText 测试。
///
/// 断言：超长文本滚动、短文本静止、文字变化后重置、同一文本重建不重启动画、
/// 包在 InkWell 里点按仍能触发 onTap。
void main() {
  const longText =
      '正在上课 · 实验室 14:00 - 17:10 ｜ 下一节 药物化学 明天 08:00';
  const shortText = '近期暂无课程';

  Widget wrap(String text, {VoidCallback? onTap}) {
    final child = SizedBox(
      width: 300,
      child: MarqueeText(text, style: const TextStyle(fontSize: 13)),
    );
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: onTap == null
              ? child
              : Material(
                  child: InkWell(onTap: onTap, child: child),
                ),
        ),
      ),
    );
  }

  testWidgets('超长文本：出现滚动结构（ClipRect + OverflowBox + Transform）',
      (tester) async {
    await tester.pumpWidget(wrap(longText));
    // 让帧末同步回调跑完，动画启动
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ClipRect), findsOneWidget);
    expect(find.byType(OverflowBox), findsOneWidget);
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsOneWidget);
    // 两份相同文本（第二份包 ExcludeSemantics）
    expect(find.text(longText), findsNWidgets(2));
  });

  testWidgets('超长文本：滚动后 Transform 偏移向左移动', (tester) async {
    await tester.pumpWidget(wrap(longText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final first = tester.widget<Transform>(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform))).transform.getTranslation().x;
    await tester.pump(const Duration(milliseconds: 500));
    final second = tester.widget<Transform>(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform))).transform.getTranslation().x;
    expect(first, lessThan(0));
    expect(second, lessThan(first));
  });

  testWidgets('短文本：静止渲染，无滚动结构', (tester) async {
    await tester.pumpWidget(wrap(shortText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(shortText), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
    expect(find.byType(OverflowBox), findsNothing);
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsNothing);
  });

  testWidgets('文字由长变短：回到静止渲染，不抛异常', (tester) async {
    await tester.pumpWidget(wrap(longText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsOneWidget);

    await tester.pumpWidget(wrap(shortText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(shortText), findsOneWidget);
    expect(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform)), findsNothing);
  });

  testWidgets('同一超长文本重建：动画继续，不抛异常', (tester) async {
    await tester.pumpWidget(wrap(longText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final first = tester.widget<Transform>(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform))).transform.getTranslation().x;

    // 同一文本再建一次（模拟父页面 30 秒重建）
    await tester.pumpWidget(wrap(longText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final second = tester.widget<Transform>(find.descendant(of: find.byType(MarqueeText), matching: find.byType(Transform))).transform.getTranslation().x;

    expect(first, lessThan(0));
    expect(second, lessThan(first));
  });

  testWidgets('包在 InkWell 里：点按仍触发 onTap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(wrap(longText, onTap: () => tapped++));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(MarqueeText));
    await tester.pump();
    expect(tapped, 1);
  });
}
