/// 底部栏几何常量与网格联动留白（WB_SPEC_215 第 2 节新增；WB_SPEC_216 第 1 节改写）。
///
/// 2.1.5 起底部栏有两种形态，**都贴底、都不悬浮**（无悬浮间距、无悬浮阴影）：
/// - [BottomBarStyle.tab]（图标+文字标签栏，默认）：栏体撑满整宽、贴住屏幕底边，
///   顶部一条细分割线（浅色 0.8dp／深色 0.6dp），两格等宽——图标在上、文字在下，
///   选中态图标与文字同为琥珀黄（[kTabBarActiveColor]）；
/// - [BottomBarStyle.capsule]（胶囊占位式，WB_SPEC_218 第 ① 节）：胶囊外形
///   不变（圆角 26、宽度随内容自适应），但改为主布局底部一整条专属槽位
///   （高 64 + 底部安全区、背景与页面底色一致），胶囊在槽位内居中，课表
///   网格滚动视口截断在槽位上方，内容永远不滑到胶囊下面去。
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

/// 胶囊占位式专属槽位**最小**高度（**不含**底部安全区，WB_SPEC_218 第 ① 节；
/// 2.1.7 复查 Bug 5 后由固定高改为最小高）。
///
/// 常规字体下 64 = 胶囊高 52 + 上下各 6 空隙：胶囊在槽位内垂直居中，距课表
/// 滚动区底边与系统手势栏顶边各留 6dp。系统字体放大时胶囊纵向伸展，槽位
/// 用 padding 式布局随内容长高（见 main.dart _buildCapsuleSlot），不顶破、
/// 不溢出黄条。槽位是主布局底部一整条不滚动区域（背景与页面底色一致），
/// 课表网格滚动视口截断在槽位上方，内容永远不滑到胶囊下面。
const double kCapsuleSlotHeight = 64;

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
/// - 标签栏：栏体实测高 64（玻璃标签栏仍是悬浮 overlay，网格视口延伸到底，
///   需要留足栏高避免最后一节被栏压住）；
/// - 胶囊占位式：0（WB_SPEC_218 第 ① 节）——胶囊改成主布局底部一整条专属
///   槽位，槽位自己占布局高度，网格滚动视口截断在槽位上方，不再需要按
///   胶囊高度留白。
///
/// 调用方再各自叠加 `MediaQuery.paddingOf(context).bottom`，
/// 因为标签栏形态把安全区留在栏体之外（栏体自己吃 SafeArea），不能重复计算；
/// 胶囊占位式则由槽位吃掉安全区，网格完全不叠加。
double bottomBarGridBottomInset({
  required bool showBottomBar,
  required BottomBarStyle style,
}) {
  if (!showBottomBar) return kBottomBarHiddenInset;
  if (style == BottomBarStyle.capsule) return 0;
  return kBottomBarTabHeight;
}

/// 叠加底部安全区后的完整留白，供 `padding: EdgeInsets.only(bottom: ...)` 直接用。
///
/// 胶囊占位式（WB_SPEC_218 第 ① 节）返回 0：槽位已把底部安全区一并吃掉，
/// 网格不再叠加，否则会与槽位的 SafeArea 重复留白、下面空一截。
double bottomBarGridBottomPadding(
  double safeAreaBottom, {
  required bool showBottomBar,
  required BottomBarStyle style,
}) {
  if (showBottomBar && style == BottomBarStyle.capsule) return 0;
  final safe = safeAreaBottom.isFinite && safeAreaBottom > 0
      ? safeAreaBottom
      : 0.0;
  return safe +
      bottomBarGridBottomInset(showBottomBar: showBottomBar, style: style);
}
