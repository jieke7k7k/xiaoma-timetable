import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/color_schemes.dart';
import 'package:xiaoma_timetable/utils/morandi_palette.dart';

/// 课程配色方案（1.1.1）：色位映射的正确性是整表换色的地基
void main() {
  group('配色方案完整性', () {
    test('每套方案都与莫兰迪同为 16 色（色位一一对应）', () {
      for (final s in kCourseColorSchemes) {
        expect(
          s.colors.length,
          MorandiPalette.colors.length,
          reason: '方案 ${s.id} 颜色数必须与莫兰迪一致',
        );
      }
    });

    test('方案 id 不重复，推荐主题都存在', () {
      final ids = kCourseColorSchemes.map((s) => s.id).toSet();
      expect(ids.length, kCourseColorSchemes.length);
      for (final s in kCourseColorSchemes) {
        expect(
          kThemePresets.any((p) => p.id == s.recommendedThemeId),
          isTrue,
          reason: '方案 ${s.id} 的推荐主题 ${s.recommendedThemeId} 必须存在',
        );
      }
    });
  });

  group('mapCourseColor', () {
    test('莫兰迪方案下恒等（不换色）', () {
      final morandi = courseSchemeById('morandi');
      for (final c in MorandiPalette.colors) {
        expect(mapCourseColor(c, morandi), c);
      }
    });

    test('其他方案按同下标映射', () {
      final macaron = courseSchemeById('macaron');
      for (var i = 0; i < MorandiPalette.colors.length; i++) {
        expect(
          mapCourseColor(MorandiPalette.colors[i], macaron),
          macaron.colors[i],
        );
      }
    });

    test('非色板颜色（自定义色）不被映射，原样保留', () {
      const custom = 0xFF010203;
      expect(MorandiPalette.colors.contains(custom), isFalse);
      for (final s in kCourseColorSchemes) {
        expect(mapCourseColor(custom, s), custom);
      }
    });

    test('切到别的方案再切回莫兰迪可完全还原', () {
      final grape = courseSchemeById('grape');
      final morandi = courseSchemeById('morandi');
      for (final c in MorandiPalette.colors) {
        final shown = mapCourseColor(c, grape);
        // 还原路径：渲染层永远从存储色（莫兰迪）出发映射，存储色从未改变
        expect(mapCourseColor(c, morandi), c);
        expect(shown, grape.colors[MorandiPalette.colors.indexOf(c)]);
      }
    });
  });

  group('lightenColor（1.2.3 深底提亮）', () {
    test('提亮后亮度上升且不改变色相方向', () {
      const base = Color(0xFF1F3A5F); // 深蓝
      final light = lightenColor(base);
      expect(light.computeLuminance(), greaterThan(base.computeLuminance()));
      expect(light.computeLuminance(), lessThan(1.0));
    });
  });

  group('darkenColor（加粗边框取色）', () {
    test('加深后明度下降、色相基本不变', () {
      const base = Color(0xFFAFC3BB);
      final dark = darkenColor(base);
      final baseHsv = HSVColor.fromColor(base);
      final darkHsv = HSVColor.fromColor(dark);
      expect(darkHsv.value, lessThan(baseHsv.value));
      expect((darkHsv.hue - baseHsv.hue).abs(), lessThan(2));
    });
  });

  group('themePresetById', () {
    test('未知 id 回退第一套（雾绿）', () {
      expect(themePresetById('nope').id, 'forest');
      expect(themePresetById('ocean').seed, 0xFF3B6E9C);
    });
  });

  group('buildAppColorScheme（复查 Bug 1/6/7：生产配色唯一入口）', () {
    // WCAG 对比度（与 bottom_bar_style_test 同口径的独立实现）
    double contrast(Color a, Color b) {
      double lum(Color c) {
        double f(int v) {
          final x = v / 255;
          return x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
        }
        return 0.2126 * f((c.r * 255).round()) +
            0.7152 * f((c.g * 255).round()) +
            0.0722 * f((c.b * 255).round());
      }

      final l1 = lum(a);
      final l2 = lum(b);
      return (l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05));
    }

    test('7 个预置：surface 与容器色一律中性（只留 4% 种子倾向）', () {
      // 中性底色：浅纸白 0xFFFAFAF8 / 暗夜黑 0xFF121214；4% 种子最多让
      // 单通道偏离约 10（0.04×255），超了就是染色没压住
      const lightBase = Color(0xFFFAFAF8);
      const darkBase = Color(0xFF121214);
      for (final p in kThemePresets) {
        final seed = Color(p.seed);
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final scheme = buildAppColorScheme(seed, brightness);
          final base = brightness == Brightness.dark ? darkBase : lightBase;
          for (final channel in [
            (scheme.surface.r * 255).round() - (base.r * 255).round(),
            (scheme.surface.g * 255).round() - (base.g * 255).round(),
            (scheme.surface.b * 255).round() - (base.b * 255).round(),
          ]) {
            expect(channel.abs(), lessThanOrEqualTo(12),
                reason: '预置 ${p.id} $brightness 下 surface 不应染色');
          }
          // 容器色与 surface 同为中性梯度：容器之间亮度单调，不跳变
          final containers = [
            scheme.surfaceContainerLowest,
            scheme.surfaceContainerLow,
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
            scheme.surfaceContainerHighest,
          ];
          final lums = containers.map((c) => c.computeLuminance()).toList();
          for (var i = 1; i < lums.length; i++) {
            if (brightness == Brightness.light) {
              expect(lums[i], lessThanOrEqualTo(lums[i - 1] + 0.001),
                  reason: '预置 ${p.id} 浅色容器应越往高越暗');
            } else {
              expect(lums[i], greaterThanOrEqualTo(lums[i - 1] - 0.001),
                  reason: '预置 ${p.id} 深色容器应越往高越亮');
            }
          }
        }
      }
    });

    test('7 个预置：primary 各不相同（种子色真的生效），且与 surface 对比度可读', () {
      final lightPrimaries = <Color>{};
      final darkPrimaries = <Color>{};
      for (final p in kThemePresets) {
        final seed = Color(p.seed);
        final light = buildAppColorScheme(seed, Brightness.light);
        final dark = buildAppColorScheme(seed, Brightness.dark);
        lightPrimaries.add(light.primary);
        darkPrimaries.add(dark.primary);
        // 浅色 primary 在中性纸白上、深色 primary 在暗夜黑上都要够对比
        expect(contrast(light.primary, light.surface), greaterThanOrEqualTo(3.0),
            reason: '预置 ${p.id} 浅色 primary 对比度不足');
        expect(contrast(dark.primary, dark.surface), greaterThanOrEqualTo(3.0),
            reason: '预置 ${p.id} 深色 primary 对比度不足');
        // 正文在 surface 上必须高对比（AA 级 7:1 左右）
        expect(contrast(light.onSurface, light.surface),
            greaterThanOrEqualTo(7.0),
            reason: '预置 ${p.id} 浅色正文对比度不足');
        expect(contrast(dark.onSurface, dark.surface),
            greaterThanOrEqualTo(7.0),
            reason: '预置 ${p.id} 深色正文对比度不足');
      }
      expect(lightPrimaries.length, kThemePresets.length,
          reason: '7 个预置的浅色 primary 必须各不相同');
      expect(darkPrimaries.length, kThemePresets.length,
          reason: '7 个预置的深色 primary 必须各不相同');
    });
  });
}
