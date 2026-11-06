import 'package:flutter/widgets.dart';

/// 全 App 唯一的路由观察者（复查 Bug 3 / 优化 3）：页面从子页返回时
/// （如设置页从提醒设置页回来）需要重新查询权限状态，靠它感知。
///
/// 用独立文件避免 main.dart 与各页面互相 import 形成循环依赖。
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
