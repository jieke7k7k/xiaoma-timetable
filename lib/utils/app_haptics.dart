import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 全 App 按键震动反馈的统一门控（WB_SPEC_235 第 3 节）。
///
/// 为什么要有这一层：2.5.0 之前震动是各处零散直接调 `HapticFeedback.xxx()`，
/// 既没有总开关、也没法统一节流——同一次点击被「入口行 + 内层 InkWell」
/// 各震一下就成了双震。这里把「震不震」「震多重」「多久内只震一次」三件事
/// 收在一处，调用点一律只写 [tap] / [select] / [medium]。
///
/// 三档强度（与系统 [HapticFeedback] 的对应关系）：
/// - [tap]    → `lightImpact`：轻点按钮、切 Tab、菜单项，最轻的一档；
/// - [select] → `selectionClick`：选择类反馈（开关、芯片、选择器、滑杆档位）；
/// - [medium] → `mediumImpact`：需要更明确的确认（保存、长按进入操作）。
///
/// **`heavyImpact` 不提供**（规格明令禁用）：这一版要的是「轻微反馈」，
/// 重震动在安静场合很突兀，且 Android 各机型对 heavy 的实现差异大。
///
/// 节流：[throttleWindow]（45ms）内只震动一次，且三档**共用一个窗口**——
/// 入口行与其内部 InkWell 在极短时间内先后响应时，第二次直接丢弃。
/// 这是「防双震」的第二道保险（第一道是共用组件的
/// `enableFeedback: false`，见 `SettingsEntryRow` 等）。
///
/// 开关：[enabled] 由 `UiSettingsNotifier.build()` 与 `apply()` 两处同步
/// （只有这两处写，别在页面里散着改），持久化字段是 `UiSettings.enableHaptics`。
///
/// 平台调用只走 `HapticFeedback`，不申请 `VIBRATE` 权限、不碰通知震动
/// （规格 §8 红线）。
class AppHaptics {
  AppHaptics._();

  /// 全局开关：false 时三档全部静默（连节流窗口也不占用）。
  static bool enabled = true;

  /// 共享节流窗口：45ms 内的第二次及以后的震动一律丢弃。
  static const Duration throttleWindow = Duration(milliseconds: 45);

  /// 上一次真正触发震动的时刻；null = 还没震过。
  static DateTime? _lastFiredAt;

  /// 时钟（测试用假时钟替换，生产就是 [DateTime.now]）。
  ///
  /// 之所以可替换：45ms 是真实时间窗口，单测里 `await Future.delayed(45ms)`
  /// 既慢又不稳，直接推假时钟最干净。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// 轻点反馈（最轻档）：按钮、Tab、菜单项、弹窗按钮。
  static void tap() => _fire(HapticFeedback.lightImpact);

  /// 选择反馈：开关、芯片、选择器、滑杆档位变化。
  static void select() => _fire(HapticFeedback.selectionClick);

  /// 中档反馈：保存、长按进入某操作等需要明确确认的动作。
  static void medium() => _fire(HapticFeedback.mediumImpact);

  /// 统一出口：先看总开关、再过共享节流，最后才真正调平台。
  static void _fire(Future<void> Function() haptic) {
    if (!enabled) return;
    final now = clock();
    final last = _lastFiredAt;
    if (last != null && now.difference(last) < throttleWindow) return;
    _lastFiredAt = now;
    // 平台调用是 fire-and-forget：震动失败（如模拟器无马达）不该冒泡成异常，
    // 更不能让一次按键因为震动失败而中断业务流程。
    haptic();
  }

  /// 复位门控状态（仅测试用：清节流窗口与开关）。
  @visibleForTesting
  static void resetForTest() {
    enabled = true;
    _lastFiredAt = null;
    clock = DateTime.now;
  }
}
