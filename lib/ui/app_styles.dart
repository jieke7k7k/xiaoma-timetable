/// 全局视觉规范常量（阶段五·视觉打磨）
///
/// 圆角与间距统一从这里取值，不要在页面里到处硬编码，
/// 保证所有页面的卡片、弹层、间距视觉一致。
/// 间距只允许 8 / 12 / 16 三档（微调场景可用 4 / 24）。
class AppRadii {
  AppRadii._();

  /// 卡片圆角（列表卡片、课程格子、图标底座等统一 12px）
  static const double card = 12;

  /// 弹层圆角（BottomSheet 顶部圆角）
  static const double sheet = 16;

 /// 小元素圆角（周次跳转块、快捷按钮等 chip 级元素）
  static const double chip = 8;

  /// 启动页 Logo 等大块圆角
  static const double logo = 24;
}

class AppSpacing {
  AppSpacing._();

  /// 微间距（图标与文字间、卡片内部小间隔）
  static const double xs = 4;

  /// 小间距（同组元素之间）
  static const double s = 8;

  /// 中间距（分组内条目之间、卡片间距）
  static const double m = 12;

  /// 大间距（分组之间、页面左右留白）
  static const double l = 16;
}
