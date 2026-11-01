/// 底部栏几何常量与网格联动留白（WB_SPEC_215 第 2 节新增；WB_SPEC_216 第 1 节改写）。
///
/// 2.1.5 起底部栏有两种形态，**都贴底、都不悬浮**（无悬浮间距、无悬浮阴影）：
/// - [BottomBarStyle.tab]（图标+文字标签栏，默认）：栏体撑满整宽、贴住屏幕底边，
///   顶部一条 1 逻辑像素细分割线，两格等宽——图标在上、文字在下，
///   选中态图标与文字同为琥珀黄（[kTabBarActiveColor]）；
/// - [BottomBarStyle.capsule]（胶囊贴底）：栏体本身是胶囊（圆角 26、宽度随内容自适应），
///   贴底，只保留底部安全区内边距。
///
/// 2.1.4 的「通栏贴底」（id `bar`）已整体删除，旧库里残留的 `bar` 由
/// `BottomBarStyle.fromId` 回落到 [BottomBarStyle.tab]。
///
/// 网格底部留白必须按当前形态算，否则要么内容被栏遮住（留白偏小），
/// 要么下方空一大截（留白偏大）。这里的 [bottomBarGridBottomInset] 是唯一口径，
/// 主页周视图与壳内设置页都调它，不各自硬编码数字。
library;

import 'package:flutter/widgets.dart';

import '../models/ui_settings.dart';

/// 键体最小高度（胶囊形态沿用；标签栏高度见 [kBottomBarTabHeight]）
const double kBottomBarKeyHeight = 52;

/// 键体与胶囊栏体的圆角半径（半圆胶囊）
const double kBottomBarRadius = 26;

/// 标签栏顶部细分割线的粗细（1 逻辑像素，画在栏体内部，不额外占高）
const double kBottomBarDividerWidth = 1;

/// 标签栏栏体高度（**不含**底部安全区）：该 widget 的实测高度 64
/// （图标 24 + 间距 4 + 文字行 ≈17，上下自动留白，合计固定 64；
/// 顶部 1 像素分割线用 DecoratedBox 画在栏体内部，不参与布局、不额外增高）。
///
/// 与 `HomeTabBar.height` 同源：改栏体结构时两边一起改，测试会实测对比。
const double kBottomBarTabHeight = 64;

/// 胶囊形态栏体高度（**不含**底部安全区）：就是胶囊自身的最小高 52
const double kBottomBarCapsuleHeight = kBottomBarKeyHeight;

/// 关闭底部栏时的网格底部留白（沿用 2.1.3 的 16）
const double kBottomBarHiddenInset = 16;

/// 标签栏选中态前景色（图标与文字同色）：琥珀黄，取 Colors.amber[600]。
///
/// 刻意不用主题 primary（本项目默认种子色是雾绿 / 可可棕一类，与截图里的
/// 琥珀黄不是一回事），写死常量，浅色与深色主题下都用它。
const Color kTabBarActiveColor = Color(0xFFFFB300);

/// 网格滚动视图底部留白（**不含**底部安全区）。
///
/// - 关栏：16；
/// - 标签栏：栏体实测高 64；
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
      : kBottomBarTabHeight;
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
