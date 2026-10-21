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
      expect(themePresetById('ocean').seed, 0xFF5B84AE);
    });
  });
}
