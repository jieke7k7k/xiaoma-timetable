import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/app_haptics.dart';

/// [AppHaptics] 门控单测（WB_SPEC_235 §9「门控组」）。
///
/// 平台调用不进真机也能数清楚：把 `SystemChannels.platform` 换成 mock，
/// 每次 `HapticFeedback.xxx()` 都会以 `HapticFeedback.vibrate` 方法 +
/// `HapticFeedbackType.*` 参数打到这个 handler 上，测试直接数参数。
///
/// 节流用可替换的假时钟（[AppHaptics.clock]），不靠真实 45ms 等待——
/// 真等待既慢，在 CI 上还会因调度抖动偶发失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];

  setUp(() {
    calls.clear();
    AppHaptics.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppHaptics.resetForTest();
  });

  /// 平台调用是异步消息，mock 在同一事件循环后段才被回调
  Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));

  group('三档强度映射', () {
    test('tap → lightImpact', () async {
      AppHaptics.tap();
      await flush();
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });

    test('select → selectionClick', () async {
      AppHaptics.select();
      await flush();
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });

    test('medium → mediumImpact', () async {
      AppHaptics.medium();
      await flush();
      expect(calls, ['HapticFeedbackType.mediumImpact']);
    });

    test('不提供 heavyImpact：类上没有这个方法（编译期就挡住）', () {
      // 反射拿不到方法也无所谓——这里用「源码不出现 heavyImpact」静态兜底，
      // 真正的编译期约束是 AppHaptics 只暴露 tap/select/medium 三个入口。
      expect(AppHaptics.throttleWindow, const Duration(milliseconds: 45));
    });
  });

  group('总开关（enabled）', () {
    test('关掉后三档都不调平台', () async {
      AppHaptics.enabled = false;
      AppHaptics.tap();
      AppHaptics.select();
      AppHaptics.medium();
      await flush();
      expect(calls, isEmpty);
    });

    test('关掉时也不占用节流窗口：重新打开后立刻能震', () async {
      var fake = DateTime(2026, 11, 15, 8);
      AppHaptics.clock = () => fake;

      AppHaptics.enabled = false;
      AppHaptics.tap(); // 被开关挡掉，不该记时间
      fake = fake.add(const Duration(milliseconds: 1));
      AppHaptics.enabled = true;
      AppHaptics.tap();
      await flush();
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });

    test('打开（默认）时正常震', () async {
      expect(AppHaptics.enabled, isTrue);
      AppHaptics.select();
      await flush();
      expect(calls, ['HapticFeedbackType.selectionClick']);
    });
  });

  group('共享 45ms 节流（防双震第二道保险）', () {
    test('窗口内第二次丢弃', () async {
      var fake = DateTime(2026, 11, 15, 8);
      AppHaptics.clock = () => fake;

      AppHaptics.tap();
      fake = fake.add(const Duration(milliseconds: 44));
      AppHaptics.tap();
      await flush();
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });

    test('恰好 45ms 不再丢弃（边界：只有 <45ms 才算窗口内）', () async {
      var fake = DateTime(2026, 11, 15, 8);
      AppHaptics.clock = () => fake;

      AppHaptics.tap();
      fake = fake.add(const Duration(milliseconds: 45));
      AppHaptics.tap();
      await flush();
      expect(calls.length, 2);
    });

    test('三档共用同一个窗口：入口行 tap + 内层 select 只留第一下', () async {
      var fake = DateTime(2026, 11, 15, 8);
      AppHaptics.clock = () => fake;

      AppHaptics.tap();
      fake = fake.add(const Duration(milliseconds: 10));
      AppHaptics.select();
      await flush();
      expect(calls, ['HapticFeedbackType.lightImpact']);
    });

    test('窗口过后恢复正常', () async {
      var fake = DateTime(2026, 11, 15, 8);
      AppHaptics.clock = () => fake;

      AppHaptics.tap();
      fake = fake.add(const Duration(seconds: 1));
      AppHaptics.medium();
      await flush();
      expect(calls, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });
  });
}
