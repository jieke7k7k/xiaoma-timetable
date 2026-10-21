import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/utils/color_schemes.dart';

/// 界面设置（1.1.1）：默认值、持久化往返、非法值钳制与回退
void main() {
  group('UiSettings 默认值', () {
    test('空/缺失一律默认：格高 46、圆角 12、莫兰迪、雾绿、系统字体', () {
      final ui = UiSettings.fromEncoded(null);
      expect(ui.cellHeight, 46);
      expect(ui.cornerRadius, 12);
      expect(ui.showGridLines, isTrue);
      expect(ui.boldBorder, isFalse);
      expect(ui.axisShowTime, isTrue);
      expect(ui.cardTextScale, 1.0);
      expect(ui.colorSchemeId, 'morandi');
      expect(ui.themePresetId, 'forest');
      expect(ui.themeCustomColor, isNull);
      expect(ui.fontId, 'system');
      expect(ui.fontFamily, isNull);
      expect(UiSettings.fromEncoded('').cellHeight, 46);
      expect(UiSettings.fromEncoded('坏掉的 json').cellHeight, 46);
    });

    test('编码→解码往返不丢字段', () {
      const ui = UiSettings(
        cellHeight: 64,
        cornerRadius: 4,
        showGridLines: false,
        boldBorder: true,
        axisShowTime: false,
        cardTextScale: 1.2,
        showClassroom: false,
        showTeacher: true,
        showNote: false,
        colorSchemeId: 'grape',
        themePresetId: 'ocean',
        themeCustomColor: 0xFF123456,
        fontId: 'lxgw',
      );
      final back = UiSettings.fromEncoded(ui.encode());
      expect(back.cellHeight, 64);
      expect(back.cornerRadius, 4);
      expect(back.showGridLines, isFalse);
      expect(back.boldBorder, isTrue);
      expect(back.axisShowTime, isFalse);
      expect(back.cardTextScale, 1.2);
      expect(back.showClassroom, isFalse);
      expect(back.showNote, isFalse);
      expect(back.colorSchemeId, 'grape');
      expect(back.themePresetId, 'ocean');
      expect(back.themeCustomColor, 0xFF123456);
      expect(back.fontId, 'lxgw');
      expect(back.fontFamily, 'LXGWWenKai');
    });

    test('越界值被钳制：格高、圆角、字号系数', () {
      final ui = UiSettings.fromEncoded(
          '{"cellHeight": 200, "cornerRadius": -3, "cardTextScale": 9}');
      expect(ui.cellHeight, 96);
      expect(ui.cornerRadius, 0);
      expect(ui.cardTextScale, UiSettings.textScaleMax);
      final low = UiSettings.fromEncoded('{"cellHeight": 10}');
      expect(low.cellHeight, 44);
      final lowScale = UiSettings.fromEncoded('{"cardTextScale": 0.1}');
      expect(lowScale.cardTextScale, UiSettings.textScaleMin);
    });

    test('旧版三档字号自动迁移为缩放系数，老设置不丢', () {
      expect(UiSettings.fromEncoded('{"cardTextSize": 0}').cardTextScale, 0.92);
      expect(UiSettings.fromEncoded('{"cardTextSize": 1}').cardTextScale, 1.0);
      expect(UiSettings.fromEncoded('{"cardTextSize": 2}').cardTextScale, 1.08);
      // 旧档越界先钳档位再迁移
      expect(UiSettings.fromEncoded('{"cardTextSize": 9}').cardTextScale, 1.08);
      // 新键存在时优先于旧键
      expect(
          UiSettings.fromEncoded('{"cardTextScale": 1.25, "cardTextSize": 0}')
              .cardTextScale,
          1.25);
    });

    test('主题种子：自定义色优先于预置；预置查不到回退雾绿', () {
      const custom = UiSettings(themeCustomColor: 0xFF000001);
      expect(custom.themeSeedValue, 0xFF000001);
      const preset = UiSettings(themePresetId: 'ocean');
      expect(preset.themeSeedValue, themePresetById('ocean').seed);
      const bad = UiSettings(themePresetId: '不存在的id');
      expect(bad.themeSeedValue, 0xFF6B8E7B);
    });

    test('copyWith 清除自定义主题色', () {
      const ui = UiSettings(themeCustomColor: 0xFF111111);
      final cleared = ui.copyWith(clearThemeCustomColor: true);
      expect(cleared.themeCustomColor, isNull);
      expect(cleared.themeSeedValue, 0xFF6B8E7B);
    });
  });
}
