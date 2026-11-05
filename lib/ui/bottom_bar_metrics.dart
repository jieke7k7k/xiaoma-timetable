/// 底部栏几何常量与网格联动留白（WB_SPEC_215 第 2 节新增；WB_SPEC_216 第 1 节改写）。
///
/// 底部栏只有一种形态：图标+文字标签栏，撑满整宽、贴住屏幕底边，顶部一条
/// 细分割线（浅色 0.8dp／深色 0.6dp），两格等宽——图标在上、文字在下，
/// 选中态图标与文字同为琥珀黄（[kTabBarActiveColor]）。
///
/// 胶囊形态已在 2.1.7 同版本修复中整体删除（用户定：只要新标签栏），本文件
/// 不再有任何胶囊口径：`BottomBarStyle` 枚举、`kCapsuleSlotHeight`、
/// `kBottomBarKeyHeight` 一并删除。
///
/// 网格底部留白必须按栏高算，否则要么内容被栏遮住（留白偏小），要么下方
/// 空一大截（留白偏大）。这里的 [bottomBarGridBottomInset] 是唯一口径，
/// 主页周视图与壳内设置页都调它，不各自硬编码数字。
library;

import 'package:flutter/widgets.dart';

/// 滑块与栏体的圆角半径（半圆）。
const double kBottomBarRadius = 26;

/// 标签栏顶部细分割线的粗细（WB_SPEC_218 第 ② 节「栏体描边」：浅色 0.8dp 内高光、
/// 深色 0.6dp 微白边；画在栏体内部，不额外占高）。
/// 2.1.7 之前曾统一锁死 1.0dp，与规格原文不符，复查揪出后按规格分亮度改回。
const double kBottomBarDividerWidthLight = 0.8;

/// 标签栏顶部细分割线粗细（深色主题，见 [kBottomBarDividerWidthLight]）。
const double kBottomBarDividerWidthDark = 0.6;

/// 按当前主题亮度取标签栏顶部细分割线的粗细。
double bottomBarDividerWidth(Brightness brightness) =>
    brightness == Brightness.dark
        ? kBottomBarDividerWidthDark
        : kBottomBarDividerWidthLight;

/// 标签栏栏体高度（**不含**底部安全区）：该 widget 的实测高度 64
/// （图标 24 + 间距 4 + 文字行 ≈17，上下自动留白，合计固定 64；
/// 顶部细分割线用 DecoratedBox 画在栏体内部，不参与布局、不额外增高）。
///
/// 与 `HomeTabBar.height` 同源：改栏体结构时两边一起改，测试会实测对比。
const double kBottomBarTabHeight = 64;

/// 关闭底部栏时的网格底部留白（沿用 2.1.3 的 16）
const double kBottomBarHiddenInset = 16;

/// 标签栏选中态基色（金黄系）：琥珀黄，取 Colors.amber[600]。
///
/// 刻意不用主题 primary（本项目默认种子色是雾绿 / 可可棕一类，与截图里的
/// 琥珀黄不是一回事），写死常量，浅色与深色主题下都用它。
///
/// 2.1.6（WB_SPEC_217）起它有两个下家：
/// - **液态滑动指示器**的金黄渐变直接用它（与 2.1.5 同色，规格第 1 节要求）；
/// - 选中态图标与文字的**前景色**改由 `HomeTabBar.activeColorFor(scheme)` 按
///   主题亮度取 [kTabBarActiveColorLight] / [kTabBarActiveColorDark]——因为
///   滑块本身已经是金黄底，浅色主题下再用这个亮黄会看不清（对比度不足）。
const Color kTabBarActiveColor = Color(0xFFFFB300);

/// 浅色主题下的选中态前景色：深褐黑（压在金黄滑块上仍清楚）。
///
/// 2.1.7（WB_SPEC_218 第 ② 节）按 Argon 轻透参数改：滑块从「满不透明亮金」
/// 降为「#FFE066 65% → #F59F00 45%」的半透明染色，压在它上面的文字改用
/// 深褐黑 #1C1917，对比度 ≥ 4.5:1（实测约 13:1）。
const Color kTabBarActiveColorLight = Color(0xFF1C1917);

/// 深色主题下的选中态前景色：高亮暖白（压在压暗的金黄滑块上仍清楚）。
///
/// 2.1.7（WB_SPEC_218 第 ② 节）改为 #FEF3C7（高亮暖白），取代 2.1.6 的
/// 浅金黄 #FFD54F——滑块本身降到 28%→18% 低不透明，暖白压在暗金上对比度
/// ≥ 4.5:1。
const Color kTabBarActiveColorDark = Color(0xFFFEF3C7);

/// 网格滚动视图底部留白（**不含**底部安全区）。
///
/// - 关栏：16；
/// - 开栏：栏体实测高 64（标签栏是悬浮 overlay，网格视口延伸到底，
///   需要留足栏高避免最后一节被栏压住）。
///
/// 调用方再各自叠加 `MediaQuery.paddingOf(context).bottom`，
/// 因为标签栏把安全区留在栏体之外（栏体自己吃 SafeArea），不能重复计算。
double bottomBarGridBottomInset({required bool showBottomBar}) {
  if (!showBottomBar) return kBottomBarHiddenInset;
  return kBottomBarTabHeight;
}

/// 叠加底部安全区后的完整留白，供 `padding: EdgeInsets.only(bottom: ...)` 直接用。
double bottomBarGridBottomPadding(
  double safeAreaBottom, {
  required bool showBottomBar,
}) {
  final safe = safeAreaBottom.isFinite && safeAreaBottom > 0
      ? safeAreaBottom
      : 0.0;
  return safe + bottomBarGridBottomInset(showBottomBar: showBottomBar);
}
