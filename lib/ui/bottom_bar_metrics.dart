/// 底部栏几何常量与网格联动留白（WB_SPEC_215 第 2 节新增；WB_SPEC_216 第 1 节改写）。
///
/// 底部栏只有一种形态：图标+文字标签栏，撑满整宽、贴住屏幕底边，顶部一条
/// 0.5dp 细分割线（主题 outlineVariant，浅色 0.45／深色 0.25），两格等宽——
/// 图标在上、文字在下，选中态图标与文字同为主题 primary，底部另有一根
/// 20×3dp 小短条指示选中项（2026-11-05 用户反馈后按 Argon Q1 方案改为
/// 「无框」选中态：金黄滑块与固定琥珀黄已整体删除）。
///
/// 胶囊形态已在 2.1.7 同版本修复中整体删除（用户定：只要新标签栏），本文件
/// 不再有任何胶囊口径：`BottomBarStyle` 枚举、`kCapsuleSlotHeight`、
/// `kBottomBarKeyHeight` 一并删除。
///
/// 网格底部留白必须按栏高算，否则要么内容被栏遮住（留白偏小），要么下方
/// 空一大截（留白偏大）。这里的 [bottomBarGridBottomInset] 是唯一口径，
/// 主页周视图与壳内设置页都调它，不各自硬编码数字。
library;

/// 标签栏栏体高度（**不含**底部安全区）：该 widget 的实测高度 64
/// （图标 23 + 间距 4 + 文字行 ≈17，上下自动留白，合计固定 64；
/// 顶部细分割线用 DecoratedBox 画在栏体内部，不参与布局、不额外增高）。
///
/// 与 `HomeTabBar.height` 同源：改栏体结构时两边一起改，测试会实测对比。
const double kBottomBarTabHeight = 64;

/// 关闭底部栏时的网格底部留白（沿用 2.1.3 的 16）
const double kBottomBarHiddenInset = 16;

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
