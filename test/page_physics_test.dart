import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/deliberate_page_physics.dart';

/// 切周翻页物理（1.2.1）：慢速松手只按位置结算、快速甩动才顺势翻页
///
/// 一页宽 400：第 2 页区间为像素 400~800。
/// 框架默认物理在速度超过约 7 px/s 时就把目标页偏移半页——
/// 用例 1/3 正是默认实现会翻页、本实现必须弹回的场景。
void main() {
  const physics = DeliberatePagePhysics();

  FixedScrollMetrics metrics(double pixels) => FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 2000,
        pixels: pixels,
        viewportDimension: 400,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 2.0,
      );

  double settleAt(double pixels, double velocity) {
    final sim = physics.createBallisticSimulation(metrics(pixels), velocity);
    if (sim == null) return pixels;
    // 弹簧模拟足够长时间后应停在目标像素（容差 2px）
    return sim.x(10);
  }

  test('只拖出 10% 就慢速松手 → 弹回当前页（默认物理在此会翻页）', () {
    expect(settleAt(440, 100), closeTo(400, 2));
    expect(settleAt(440, 0), closeTo(400, 2));
  });

  test('明确甩动（≥800 px/s）→ 顺势翻到下一页', () {
    expect(settleAt(440, 1000), closeTo(800, 2));
    expect(settleAt(440, 850), closeTo(800, 2));
  });

  test('反向快甩 → 回到上一页', () {
    expect(settleAt(560, -1000), closeTo(400, 2));
  });

  test('拖过半屏后慢速松手 → 按位置翻页', () {
    expect(settleAt(640, 0), closeTo(800, 2));
    expect(settleAt(560, -100), closeTo(400, 2));
  });

  test('恰好在页边界且无速度 → 不动', () {
    final sim = physics.createBallisticSimulation(metrics(400), 0);
    expect(sim, isNull);
  });
}
