import 'package:flutter/material.dart';

/// 全 App 统一的页面转场（WB_SPEC_212 第 5 节）：标准右滑转场，全 App 不混用。
///
/// - 时长固定 300ms（正向与返回一致，见下方两个覆写）；
/// - 曲线统一用 [Curves.fastOutSlowIn]（规格第 5 节二选一的定版）；
/// - 系统「移除动画」（无障碍）开启时直接返回子页、转场时长归零。
/// - 明确不做预测性返回（2026-10-26 用户亲口定）：不用
///   PredictiveBackPageTransitionsBuilder，Android 14+ 返回手势走系统默认
///   行为，不做返回预览动画；转场因此可以自由定曲线，不受手势 1:1 映射约束。
class AppSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const AppSlidePageTransitionsBuilder({required this.android});

  /// 保留平台参数（主题按平台注册），但两平台行为已统一：均标准右滑、
  /// 均不做预测性返回。
  final bool android;

  /// 规格第 5 节定版时长：MaterialPageRoute 取 builder 的这个值建动画控制器。
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  static final Animatable<Offset> _slideTween =
      Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.fastOutSlowIn));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 无障碍：系统开启「移除动画」时转场时长归零（直接返回子页）
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // 标准右滑：新页从右滑入；旧页不动（不做预测性返回预览）。
    return SlideTransition(position: animation.drive(_slideTween), child: child);
  }
}
