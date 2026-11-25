import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/main.dart';

/// 条件轮询等待：在 FFI 内存库跨 isolate 异步场景下，以短周期「真实异步窗口 + 推进假时钟」
/// 替代固定 1500ms 死等（WB_SPEC_264 T12）。一旦 [predicate] 成立立即返回，不空转。
/// 超时直接 fail 并报出 [label]，避免静默通过后在后面的断言里报看不懂的错（M15/L5）。
Future<void> pumpUntilCondition(
  WidgetTester tester,
  bool Function() predicate, {
  int maxRounds = 50,
  Duration realWait = const Duration(milliseconds: 40),
  Duration pumpStep = const Duration(milliseconds: 50),
  String? label,
}) async {
  for (var i = 0; i < maxRounds; i++) {
    if (predicate()) return;
    await tester.runAsync(() => Future.delayed(realWait));
    await tester.pump(pumpStep);
  }
  if (!predicate()) {
    fail('等待超时：${label ?? '条件'} 在 $maxRounds 轮内未成立');
  }
}

/// 条件轮询直到 [finder] 匹配到至少一个元素（WB_SPEC_264 T12）。
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxRounds = 50,
  Duration realWait = const Duration(milliseconds: 40),
  Duration pumpStep = const Duration(milliseconds: 50),
}) =>
    pumpUntilCondition(
      tester,
      () => finder.evaluate().isNotEmpty,
      maxRounds: maxRounds,
      realWait: realWait,
      pumpStep: pumpStep,
      label: '查找 $finder',
    );

/// 轻量排空若干轮真实异步与假时钟帧（替代 pumpAndSettle，避免在 FFI / 周期定时器下挂死）。
Future<void> drainAsync(
  WidgetTester tester, {
  int rounds = 5,
  Duration realWait = const Duration(milliseconds: 60),
  Duration pumpStep = const Duration(milliseconds: 80),
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future.delayed(realWait));
    await tester.pump(pumpStep);
  }
}

/// 挂载 [HomeShell]（阻断真实网络）并轮询等待 [readyPredicate] 或 [readyFinder] 就绪。
Future<void> pumpHomeShell(
  WidgetTester tester, {
  ProviderContainer? container,
  Finder? readyFinder,
  bool Function()? readyPredicate,
}) async {
  final child = const MaterialApp(home: HomeShell());
  final root = container == null
      ? ProviderScope(child: child)
      : UncontrolledProviderScope(container: container, child: child);

  await tester.runAsync(() async {
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(root);
        await tester.pump();
      },
      createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
    );
  });
  await tester.pump();

  final predicate = readyPredicate ??
      () => (readyFinder ?? find.byIcon(Icons.more_vert)).evaluate().isNotEmpty;
  await pumpUntilCondition(
    tester,
    predicate,
    label:
        '等待 HomeShell 就绪 (${(readyFinder ?? find.byIcon(Icons.more_vert)).toString()})',
  );
}

/// HomeShell / WeekViewPage 用例收尾（WB_SPEC_264 T11）：
/// 先卸载 widget 树触发 dispose（取消周期定时器），再排空启动联动残留延时任务，
/// 避免 teardown 报「A Timer is still pending」。
Future<void> finishHomeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(
    () => Future.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump(const Duration(seconds: 60));
}
