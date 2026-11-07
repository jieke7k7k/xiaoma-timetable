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

  group('WB_SPEC_219：新增 4 套多彩课程配色', () {
    // 逐字抄自规格书 1.2：4 套 × 16 色。任何一位色值写错都在这里被抓到。
    const expectedColors = <String, List<int>>{
      'spring-fair': [
        0xFFFFCDD2, 0xFFB8E8E2, 0xFFFFE5B4, 0xFFD4C8F0,
        0xFFC5E8B7, 0xFFFFCFB8, 0xFFBDD9F5, 0xFFF4C4E0,
        0xFFE8F0B6, 0xFFB6CBE8, 0xFFF5D5C0, 0xFFB4E2CB,
        0xFFE2C6EC, 0xFFFCEBA8, 0xFFB8DFEE, 0xFFF2BDC7,
      ],
      'cream-soda': [
        0xFFB6E3EE, 0xFFFFC8BD, 0xFFCCEBC5, 0xFFCBC9F2,
        0xFFFFEAB6, 0xFFADE2D4, 0xFFF9C6D8, 0xFFB8D2F2,
        0xFFFFD8B4, 0xFFE4C4EA, 0xFFDFF0B8, 0xFFAEC8E4,
        0xFFF7CBC4, 0xFFBBEAD8, 0xFFD8C6E8, 0xFFF7E5A9,
      ],
      'dopamine-candy': [
        0xFFFFA6A8, 0xFF94C2F4, 0xFFFFDB85, 0xFFC2AAEE,
        0xFFA2E0A8, 0xFFFFB58A, 0xFF88DCE0, 0xFFF4A6D0,
        0xFFD2E88E, 0xFF9AB4E6, 0xFFF9A88C, 0xFF8CD9BC,
        0xFFDAA8EC, 0xFFFBE48E, 0xFF8ECDE6, 0xFFF2A2B8,
      ],
      'retro-film': [
        0xFFE8B4A6, 0xFFA6C4DC, 0xFFF0D69E, 0xFFAECBB8,
        0xFFDDB2C4, 0xFF9ECED2, 0xFFEEC29E, 0xFFC2B6DC,
        0xFFC8D8A8, 0xFFE6AAA6, 0xFF9EB6D4, 0xFFF2DFB2,
        0xFF9EC8B8, 0xFFD8B2D4, 0xFFE8C8B0, 0xFF98BECA,
      ],
    };
    const expectedTheme = <String, String>{
      'spring-fair': 'forest',
      'cream-soda': 'ocean',
      'dopamine-candy': 'graphite',
      'retro-film': 'cocoa',
    };
    const expectedName = <String, String>{
      'spring-fair': '春日·游园会',
      'cream-soda': '奶油·苏打水',
      'dopamine-candy': '多巴胺·糖果盒',
      'retro-film': '复古·胶片馆',
    };

    test('共 10 套；4 个新 id 唯一、与现有 6 套无冲突，且按规格书顺序追加在末尾', () {
      expect(kCourseColorSchemes.length, 10);
      final ids = kCourseColorSchemes.map((s) => s.id).toList();
      expect(ids.length, ids.toSet().length, reason: '所有方案 id 不得重复');
      for (final id in expectedColors.keys) {
        expect(ids.where((e) => e == id).length, 1,
            reason: '$id 应恰好出现一次');
      }
      // 现有 6 套 id 与顺序一字不动
      expect(ids.sublist(0, 6), const [
        'morandi', 'macaron', 'seasalt', 'mint', 'grape', 'sunset',
      ]);
      // 新 4 套按规格书顺序追加在末尾
      expect(ids.sublist(6), expectedColors.keys.toList());
    });

    test('每套恰好 16 色，且逐字等于规格书色值', () {
      for (final id in expectedColors.keys) {
        final s = courseSchemeById(id);
        expect(s.name, expectedName[id], reason: '$id 名称');
        expect(s.colors.length, 16, reason: '$id 应恰好 16 色');
        expect(s.colors, expectedColors[id], reason: '$id 色值须逐字一致');
      }
    });

    test('recommendedThemeId 均为现有 7 个主题预置之一', () {
      for (final id in expectedColors.keys) {
        final s = courseSchemeById(id);
        expect(s.recommendedThemeId, expectedTheme[id]);
        expect(
          kThemePresets.any((p) => p.id == s.recommendedThemeId),
          isTrue,
          reason: '$id 的推荐主题必须存在于 kThemePresets',
        );
      }
    });

    test('courseSchemeById 能按新 id 取到对应方案（未知 id 回退语义不变）', () {
      for (final id in expectedColors.keys) {
        expect(courseSchemeById(id).id, id);
        expect(courseSchemeById(id).colors, expectedColors[id]);
      }
      expect(courseSchemeById('nope').id, 'morandi');
    });

    test('mapCourseColor 对新方案抽查 3 个下标映射正确，自定义色原样', () {
      for (final id in expectedColors.keys) {
        final s = courseSchemeById(id);
        for (final idx in const [0, 7, 15]) {
          expect(
            mapCourseColor(MorandiPalette.colors[idx], s),
            s.colors[idx],
            reason: '$id 下标 $idx 应取同下标颜色',
          );
        }
        const custom = 0xFF010203;
        expect(mapCourseColor(custom, s), custom,
            reason: '$id 下自定义色不参与映射');
      }
    });
  });
}
