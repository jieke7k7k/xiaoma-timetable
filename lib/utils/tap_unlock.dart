/// 连点解锁计数器（WB_SPEC_212 第 3 节·开发者选项解锁）。
///
/// 关于页版本行连续点击 [requiredTaps] 次、且全部落在 [window] 时间窗内即
/// 解锁。纯 Dart、无平台依赖，方便单测。
///
/// 计时走单调时钟，绝不读系统墙钟：默认用内部 [Stopwatch] 的 elapsed，
/// 系统时间回拨/前跳不会影响 2 秒窗口判断；测试可注入 [monotonicNow]
/// 伪造单调时间。
///
/// 设计上「误触一次不解锁、不弹窗、不提示」：计数只进内存，未达阈值时
/// 外部无任何可见反馈；一旦某次点击距上次超过窗口，自动从头重计。
class TapUnlockCounter {
  TapUnlockCounter({
    this.requiredTaps = 5,
    this.window = const Duration(seconds: 2),
    Duration Function()? monotonicNow,
  }) : _monotonicNow = monotonicNow ?? _defaultClock;

  /// 进程内共享的单调时钟：构造时即启动，永不读墙钟。
  static final Stopwatch _sharedStopwatch = Stopwatch()..start();
  static Duration _defaultClock() => _sharedStopwatch.elapsed;

  /// 解锁所需的连续点击次数（关于页定版：连点 5 次）。
  final int requiredTaps;

  /// 从第一次点击到解锁的全部时间窗（定版：2 秒内）。
  final Duration window;

  final Duration Function() _monotonicNow;

  final List<Duration> _taps = [];

  /// 记录一次点击。返回「本次点击是否触发了解锁」。
  ///
  /// 每记一次就丢弃窗口外的旧点击：既保证窗口内计数，又避免列表无限增长。
  bool tap() {
    final now = _monotonicNow();
    _taps.removeWhere((t) => now - t > window);
    _taps.add(now);
    if (_taps.length < requiredTaps) return false;
    // 达到阈值即解锁并清空，避免同一次会话里重复触发
    final unlocked = now - _taps.first <= window;
    if (unlocked) _taps.clear();
    return unlocked;
  }

  /// 重置计数（解锁成功后调用方也可自行重置；此处为可测性保留）。
  void reset() => _taps.clear();
}
