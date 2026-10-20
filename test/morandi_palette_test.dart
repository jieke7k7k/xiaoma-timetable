import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xiaoma_timetable/utils/morandi_palette.dart';

/// 深色模式降饱和函数（MorandiPalette.desaturateForDark）的单元测试
///
/// 验收点（阶段五·深色适配）：
/// 1. 浅色模式下原样返回（不做任何变换）；
/// 2. 深色模式下饱和度与明度确实降低；
/// 3. 明度输出落在深色可读区间 [0.18, 0.40]，极端输入（纯白/近黑）被夹紧。
void main() {
  group('浅色模式：原样返回', () {
    test('色板 16 色在浅色下不做任何变换', () {
      for (final c in MorandiPalette.colors) {
        final input = Color(c);
        expect(
          MorandiPalette.desaturateForDark(input, brightness: Brightness.light),
          same(input),
          reason:
              '浅色下应返回原对象：0x${c.toRadixString(16)}',
        );
      }
    });
  });

  group('深色模式：降饱和降明度', () {
    test('色板 16 色深色下饱和度与明度均降低', () {
      for (final c in MorandiPalette.colors) {
        final input = Color(c);
        final inHsv = HSVColor.fromColor(input);
        final out =
            MorandiPalette.desaturateForDark(input, brightness: Brightness.dark);
        final outHsv = HSVColor.fromColor(out);

        expect(outHsv.saturation, lessThan(inHsv.saturation),
            reason: '饱和度应降低：0x${c.toRadixString(16)}');
        expect(outHsv.value, lessThan(inHsv.value),
            reason: '明度应降低：0x${c.toRadixString(16)}');
        // 色相保持不变，课程颜色辨识度不丢
        // HSV↔RGB 8-bit 量化会导致几度内的色相漂移，属不可避免误差，
        // 对低饱和的莫兰迪课程色而言视觉上不可察觉，故容差放宽到 8 度。
        expect(outHsv.hue, closeTo(inHsv.hue, 8.0),
            reason: '色相应保持：0x${c.toRadixString(16)}');
        // 不透明度不变
        expect((out.a * 255.0).round().clamp(0, 255), 255);
      }
    });

    test('输出明度落在深色可读区间 [0.18, 0.40]', () {
      for (final c in MorandiPalette.colors) {
        final out = MorandiPalette.desaturateForDark(Color(c),
            brightness: Brightness.dark);
        final v = HSVColor.fromColor(out).value;
        expect(v, inInclusiveRange(0.18, 0.40),
            reason: '明度越界：0x${c.toRadixString(16)}');
      }
    });

    test('极端亮色（纯白）被压到明度上限附近，不刺眼', () {
      final out = MorandiPalette.desaturateForDark(
        Colors.white,
        brightness: Brightness.dark,
      );
      final hsv = HSVColor.fromColor(out);
      expect(hsv.value, lessThanOrEqualTo(0.40));
      expect(hsv.saturation, 0.0); // 白色无饱和度，降饱和后仍是中性色
    });

    test('极端暗色被抬到明度下限附近，深底上仍可见', () {
      // 近黑输入（明度约 0.13）：若按比例缩放会更黑，必须被下限夹住
      final out = MorandiPalette.desaturateForDark(
        const Color(0xFF221510),
        brightness: Brightness.dark,
      );
      final hsv = HSVColor.fromColor(out);
      expect(hsv.value, greaterThanOrEqualTo(0.18));
    });

    test('同一课程色在深浅两模式下色相一致（仅明度/饱和度变化）', () {
      const sample = 0xFFAFC3BB; // 灰绿
      final light = MorandiPalette.desaturateForDark(Color(sample),
          brightness: Brightness.light);
      final dark =
          MorandiPalette.desaturateForDark(Color(sample));
      // HSV↔RGB 8-bit 量化会导致几度内的色相漂移，属不可避免误差，
      // 对低饱和的莫兰迪课程色而言视觉上不可察觉，故容差放宽到 8 度。
      expect(
        HSVColor.fromColor(dark).hue,
        closeTo(HSVColor.fromColor(light).hue, 8.0),
      );
    });
  });
}
