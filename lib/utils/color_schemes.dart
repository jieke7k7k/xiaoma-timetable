import 'package:flutter/material.dart'
    show Brightness, Color, ColorScheme, DynamicSchemeVariant, HSVColor;

import 'morandi_palette.dart';

/// 课程配色方案（界面设置）：每套 16 色，与莫兰迪色板一一对应（同下标同「色位」）。
///
/// 换色原理：课程存的是莫兰迪色板里的 ARGB 值（Course.colorValue）。
/// 渲染时先认出它在莫兰迪色板中的下标，再取当前方案同下标的颜色，
/// 于是切方案 = 整表换色，课程数据一个字不用改，切回莫兰迪完全还原。
/// 不在莫兰迪色板里的颜色（自定义色）不参与映射，原样显示。
class CourseColorScheme {
  const CourseColorScheme({
    required this.id,
    required this.name,
    required this.colors,
    required this.recommendedThemeId,
  });

  final String id;
  final String name;
  final List<int> colors;

  /// 推荐搭配的主题预置 id（界面设置里可一键顺带应用）
  final String recommendedThemeId;
}

/// 全部课程配色方案（第一套即现行莫兰迪，默认）
const List<CourseColorScheme> kCourseColorSchemes = [
  CourseColorScheme(
    id: 'morandi',
    name: '莫兰迪·高级灰',
    colors: MorandiPalette.colors,
    recommendedThemeId: 'forest',
  ),
  CourseColorScheme(
    id: 'macaron',
    name: '马卡龙·甜心',
    colors: [
      0xFFF2C6C2,
      0xFFF5D7C4,
      0xFFF7E3B0,
      0xFFE9EFC0,
      0xFFCDEAC0,
      0xFFBEE3D2,
      0xFFBDE0E4,
      0xFFBCD8EE,
      0xFFC3CBEE,
      0xFFD2C4E8,
      0xFFE4C6E2,
      0xFFF3C6DA,
      0xFFEFC3B8,
      0xFFDCE8B8,
      0xFFC0DCEC,
      0xFFE8CCE0,
    ],
    recommendedThemeId: 'rose',
  ),
  CourseColorScheme(
    id: 'seasalt',
    name: '海盐·蓝调',
    colors: [
      0xFF9DBEDE,
      0xFF8FB0D8,
      0xFFA8C8E8,
      0xFF93C4D8,
      0xFF84B8C8,
      0xFF7FB3B0,
      0xFF8FC0B4,
      0xFFA5CDBE,
      0xFF7E9CC4,
      0xFF94AED2,
      0xFF86B4C4,
      0xFF9CC0D0,
      0xFF7A94B8,
      0xFF8AA8C0,
      0xFFA0BCCE,
      0xFF6F96B4,
    ],
    recommendedThemeId: 'ocean',
  ),
  CourseColorScheme(
    id: 'mint',
    name: '薄荷·清新',
    colors: [
      0xFFA8D8B9,
      0xFF95D0A8,
      0xFFB5E0C0,
      0xFF8FCBA0,
      0xFFA2D5B5,
      0xFF7FC498,
      0xFF98D4C0,
      0xFFAFE0CE,
      0xFF86C9A8,
      0xFFB9E4CF,
      0xFF79B894,
      0xFF93D1B8,
      0xFFA9DEC3,
      0xFF84CCA0,
      0xFF9ED6AE,
      0xFF6FB08E,
    ],
    recommendedThemeId: 'forest',
  ),
  CourseColorScheme(
    id: 'grape',
    name: '葡萄·紫藤',
    colors: [
      0xFFBCAEE0,
      0xFFAEA0D8,
      0xFFC9BEEE,
      0xFFA79BD2,
      0xFFB7A6DE,
      0xFF9C8CC8,
      0xFFC2B2E4,
      0xFFD0C2EC,
      0xFFA394CC,
      0xFFB3A4DC,
      0xFF8F7FBF,
      0xFFBEB0E2,
      0xFFC8C0E8,
      0xFFA8A0D8,
      0xFF9B90C6,
      0xFF8674B5,
    ],
    recommendedThemeId: 'grape',
  ),
  CourseColorScheme(
    id: 'sunset',
    name: '落日·暖阳',
    colors: [
      0xFFF0BE9C,
      0xFFF2AC7E,
      0xFFF5C9A4,
      0xFFEEA87E,
      0xFFF0B490,
      0xFFE89A6C,
      0xFFF3CBA8,
      0xFFF6D3AC,
      0xFFEAA07C,
      0xFFF2BE96,
      0xFFE08E62,
      0xFFEEB08A,
      0xFFF4C39A,
      0xFFE89E78,
      0xFFF0AA80,
      0xFFDA8A64,
    ],
    recommendedThemeId: 'sunset',
  ),
];

/// 按 id 取方案；找不到回退莫兰迪
CourseColorScheme courseSchemeById(String id) => kCourseColorSchemes.firstWhere(
  (s) => s.id == id,
  orElse: () => kCourseColorSchemes.first,
);

/// 把课程存储色（莫兰迪色）映射为当前方案下应显示的 ARGB。
/// 非莫兰迪色（自定义色等）原样返回，保证用户自选色不被方案覆盖。
int mapCourseColor(int storedValue, CourseColorScheme scheme) {
  final idx = MorandiPalette.colors.indexOf(storedValue);
  if (idx < 0) return storedValue;
  return scheme.colors[idx];
}

/// 全软件主题预置（种子色，整套界面配色由 ColorScheme.fromSeed 推导）
class ThemePreset {
  const ThemePreset({required this.id, required this.name, required this.seed});

  final String id;
  final String name;
  final int seed;
}

const List<ThemePreset> kThemePresets = [
  // 2026-11-05 Argon 方案 Q2：种子色换高饱和版（原低饱和莫兰迪色经
  // ColorScheme.fromSeed 的 tonalSpot 二次降饱和会发灰发脏）。
  ThemePreset(id: 'forest', name: '雾绿', seed: 0xFF3E7B67),
  ThemePreset(id: 'ocean', name: '海盐蓝', seed: 0xFF3B6E9C),
  ThemePreset(id: 'grape', name: '葡萄紫', seed: 0xFF6B5B95),
  ThemePreset(id: 'sunset', name: '落日橙', seed: 0xFFD96B43),
  ThemePreset(id: 'rose', name: '玫瑰粉', seed: 0xFFC85A7C),
  ThemePreset(id: 'cocoa', name: '可可棕', seed: 0xFF8C6246),
  ThemePreset(id: 'graphite', name: '曜石灰', seed: 0xFF475569),
];

/// 按 id 取主题预置；找不到回退第一套（雾绿，即原默认）
ThemePreset themePresetById(String id) => kThemePresets.firstWhere(
  (p) => p.id == id,
  orElse: () => kThemePresets.first,
);

/// 全 App 生产配色唯一入口（复查 Bug 1 / 优化 2）。
///
/// `ColorScheme.fromSeed` 的 tonalSpot 会给 surface 与容器色染上种子倾向，
/// 整屏看起来像被主题色罩住；这里用 fidelity 保真（primary 等关键色更贴
/// 近种子色）再把 surface 与整套容器色一并 copyWith 成中性梯度，只留
/// 4% 种子倾向。中性底色（浅纸白／暗夜黑）与容器梯度见下方常量。
///
/// main.dart 浅/深两处与导出图、测试都走这里，不再各造一套配色。
ColorScheme buildAppColorScheme(Color seed, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  // 只留 4% 种子倾向：与 surface 固定中性同口径（Argon 方案 Q2）。
  Color neutral(Color base) =>
      Color.alphaBlend(seed.withValues(alpha: 0.04), base);
  return ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  ).copyWith(
    surface: neutral(
      isDark ? const Color(0xFF121214) : const Color(0xFFFAFAF8),
    ),
    surfaceContainerLowest: neutral(
      isDark ? const Color(0xFF0B0B0D) : const Color(0xFFFFFFFF),
    ),
    surfaceContainerLow: neutral(
      isDark ? const Color(0xFF161618) : const Color(0xFFF7F4EF),
    ),
    surfaceContainer: neutral(
      isDark ? const Color(0xFF1D1D21) : const Color(0xFFF0EBE3),
    ),
    surfaceContainerHigh: neutral(
      isDark ? const Color(0xFF26262B) : const Color(0xFFE8E2D7),
    ),
    surfaceContainerHighest: neutral(
      isDark ? const Color(0xFF2F2F36) : const Color(0xFFDFD8CA),
    ),
  );
}

/// 由基础色推出加深版（边框用）：HSV 明度与饱和度各收敛一档，同色系深一号。
/// 把颜色提亮一档（与白色按比例混合），深色底色的边框/描边用（1.2.3 B4）
Color lightenColor(Color color, {double factor = 0.35}) =>
    Color.alphaBlend(const Color(0xFFFFFFFF).withValues(alpha: factor), color);

Color darkenColor(Color color, {double factor = 0.72}) {
  final hsv = HSVColor.fromColor(color);
  return hsv
      .withValue((hsv.value * factor).clamp(0.0, 1.0))
      .withSaturation((hsv.saturation * 1.15).clamp(0.0, 1.0))
      .toColor();
}
