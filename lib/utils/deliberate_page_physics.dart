import 'package:flutter/widgets.dart';

/// 切周专用翻页物理（1.2.1 修复「滑动太灵敏」）
///
/// 根因（框架源码 page_view.dart 的 PageScrollPhysics._getTargetPixels）：
/// 默认翻页在松手速度超过 tolerance.velocity 时把目标页强制偏移半页再取整，
/// 而该阈值 = 20 / 设备像素比，真机上仅约 7 px/s——任何一次自然松手
/// （哪怕只拖出几个像素）都会被判成翻页。调大 touchSlop 只能推迟拖动开始，
/// 管不到松手判定，所以 1.1.1 的降灵敏没有治好。
///
/// 本物理把判定改成「明确滑动才翻周」：
/// - 松手速度 ≥ [flingVelocityThreshold]（800 px/s，明确甩动）→ 顺势翻一页；
/// - 低于该速度 → 只按拖动位置结算：拖过半屏才翻页，否则弹回当前周。
/// 越界（第一周/最后一周之外）仍交回父类处理回弹。
class DeliberatePagePhysics extends PageScrollPhysics {
  const DeliberatePagePhysics({super.parent});

  /// 甩页速度门槛（逻辑像素/秒）：超过它才承认是「甩向下一页」
  static const double flingVelocityThreshold = 800;

  @override
  DeliberatePagePhysics applyTo(ScrollPhysics? ancestor) =>
      DeliberatePagePhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // 越界且不往回：交父类回弹到最近的页边界
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    // 本 App 的 PageView 视口占比恒为 1.0，一页宽 = viewportDimension
    final page = position.pixels / position.viewportDimension;
    final double targetPage;
    if (velocity > flingVelocityThreshold) {
      targetPage = page.floorToDouble() + 1;
    } else if (velocity < -flingVelocityThreshold) {
      targetPage = page.ceilToDouble() - 1;
    } else {
      targetPage = page.roundToDouble();
    }
    final target = (targetPage * position.viewportDimension)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }
}
