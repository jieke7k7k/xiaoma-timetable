import 'package:flutter/material.dart' show Brightness, Color, HSVColor;

/// 莫兰迪色系课程色板
///
/// 用户指定：课程背景色使用莫兰迪色系（低饱和度、带灰调的柔和色）。
/// 每门课程存 ARGB int（Course.colorValue），卡片背景直接用该色，
/// 文字统一使用深灰（浅底深字保证可读性）。
/// 深色模式下经 [MorandiPalette.desaturateForDark] 降饱和降明度后再上卡片，
/// 配套文字色见 [darkTextColor] / [darkSubTextColor]。
class MorandiPalette {
  MorandiPalette._();

  /// 课程卡片浅色模式下统一使用的深色文字（莫兰迪浅底上保证可读）
  static const int textColor = 0xFF3B3B3B;

  /// 课程卡片浅色模式下的次级文字（教室等小字）
  static const int subTextColor = 0xFF5A5A5A;

  /// 深色模式下的课程卡片主文字（浅暖灰，与降饱和深底形成足够对比度）
  static const int darkTextColor = 0xFFE8E4DE;

  /// 深色模式下的课程卡片次级文字
  static const int darkSubTextColor = 0xFFBDB9B2;

  /// 深色模式下角标（+N / 备注圆点）的底色：浅暖灰小色块配深字，深浅两套背景上都清晰
  static const int darkBadgeBackground = 0xFFEAE6E0;

  /// 深色模式下角标上的文字色（与浅色模式文字色一致）
  static const int darkBadgeTextColor = textColor;

  /// 16 个莫兰迪色（ARGB int）
  static const List<int> colors = [
    0xFFD9C2C7, // 灰粉
    0xFFC7BFC4, // 藕紫
    0xFFB8BFC7, // 雾蓝
    0xFFAFC3BB, // 灰绿
    0xFFC4CBB5, // 豆绿
    0xFFD3CDB4, // 燕麦
    0xFFD9C9B0, // 奶茶
    0xFFD9BFA9, // 陶土
    0xFFC9AFA0, // 裸棕
    0xFFBFA8A0, // 陶粉
    0xFFC7B8BC, // 烟粉
    0xFFB0BEC5, // 青灰
    0xFFA8B5A0, // 苔藓
    0xFFBFBFA8, // 亚麻
    0xFFC4B8A8, // 浅驼
    0xFFB5A9A6, // 灰玫瑰
  ];

  /// 新课程默认取第一个颜色
  static int get defaultColor => colors[0];

  /// 深色模式的课程底色适配：降低饱和度与明度，返回适合深色背景的柔和色。
  ///
  /// 为什么这么做：莫兰迪色本身是为浅色底设计的（明度 0.72~0.88），原样铺在
  /// 深色界面上会形成大块刺眼的亮色。深色下把明度压到 0.18~0.40 区间、
  /// 饱和度再乘 0.72，得到「暗夜莫兰迪」底色，配 [darkTextColor] 浅字保证对比度。
  ///
  /// [brightness] 传浅色时原样返回（调用方无需自己判断模式，方便统一走此入口，
  /// 也让单元测试可以直接断言「浅色下原样返回」）。
  static Color desaturateForDark(
    Color color, {
    Brightness brightness = Brightness.dark,
  }) {
    if (brightness == Brightness.light) return color;
    final hsv = HSVColor.fromColor(color);
    // 饱和度：莫兰迪本就低饱和，只做温和收敛（×0.72），保留色相辨识度
    final saturation = (hsv.saturation * 0.72).clamp(0.0, 1.0);
    // 明度：压到深色可读区间。上限 0.40 防刺眼，下限 0.18 防止黑底上看不出格子
    final value = (hsv.value * 0.42).clamp(0.18, 0.40);
    return hsv.withSaturation(saturation).withValue(value).toColor();
  }
}
