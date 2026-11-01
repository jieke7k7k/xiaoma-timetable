/// 底部栏几何常量与网格联动留白（WB_SPEC_215 第 2 节）。
///
/// 2.1.4 起底部栏有两种形态，**都不悬浮**（无悬浮间距、无悬浮阴影）：
/// - [BottomBarStyle.bar]（通栏贴底）：栏体撑满整宽、贴住屏幕底边（含底部安全区），
///   栏内「课表｜设置」两键各自做成胶囊圆角键（圆角 26、最小高 52）；
/// - [BottomBarStyle.capsule]（胶囊贴底）：栏体本身是胶囊（圆角 26、宽度随内容自适应），
///   下移贴底，只保留底部安全区内边距。
///
/// 网格底部留白必须按当前形态算，否则要么内容被栏遮住（留白偏小），
/// 要么下方空一大截（留白偏大）。这里的 [bottomBarGridBottomInset] 是唯一口径，
/// 主页周视图与壳内设置页都调它，不各自硬编码数字。
library;

import '../models/ui_settings.dart';

/// 键体最小高度（两种形态共用同一观感：胶囊圆角 26 + 最小高 52）
const double kBottomBarKeyHeight = 52;

/// 键体与胶囊栏体的圆角半径（半圆胶囊）
const double kBottomBarRadius = 26;

/// 通栏形态栏体的上下内边距（栏体色块内部留给键的呼吸空间）
const double kBottomBarVerticalPadding = 8;

/// 通栏形态栏体的左右内边距
const double kBottomBarHorizontalPadding = 12;

/// 两键之间的水平间距
const double kBottomBarKeyGap = 12;

/// 通栏形态栏体高度（**不含**底部安全区）：52 键高 + 上下各 8 内边距 = 68
const double kBottomBarBarHeight =
    kBottomBarKeyHeight + kBottomBarVerticalPadding * 2;

/// 胶囊形态栏体高度（**不含**底部安全区）：就是胶囊自身的最小高 52
const double kBottomBarCapsuleHeight = kBottomBarKeyHeight;

/// 关闭底部栏时的网格底部留白（沿用 2.1.3 的 16）
const double kBottomBarHiddenInset = 16;

/// 网格滚动视图底部留白（**不含**底部安全区）。
///
/// - 关栏：16；
/// - 通栏贴底：栏体高 68；
/// - 胶囊贴底：胶囊高 52。
///
/// 调用方再各自叠加 `MediaQuery.paddingOf(context).bottom`，
/// 因为两形态都把安全区留在栏体之外（栏体自己吃 SafeArea），不能重复计算。
double bottomBarGridBottomInset({
  required bool showBottomBar,
  required BottomBarStyle style,
}) {
  if (!showBottomBar) return kBottomBarHiddenInset;
  return style == BottomBarStyle.capsule
      ? kBottomBarCapsuleHeight
      : kBottomBarBarHeight;
}

/// 叠加底部安全区后的完整留白，供 `padding: EdgeInsets.only(bottom: ...)` 直接用。
double bottomBarGridBottomPadding(
  double safeAreaBottom, {
  required bool showBottomBar,
  required BottomBarStyle style,
}) {
  final safe = safeAreaBottom.isFinite && safeAreaBottom > 0
      ? safeAreaBottom
      : 0.0;
  return safe +
      bottomBarGridBottomInset(showBottomBar: showBottomBar, style: style);
}
