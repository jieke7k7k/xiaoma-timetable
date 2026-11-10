import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/app_styles.dart';

/// Q8 全 App 圆润化：圆角 token 分档值（Flash-Lite 方案，用户已确认）。
///
/// chip 8→10、card 12→14、sheet 16→20、dialog 20→24、logo 24→28。
/// main.dart 的 cardTheme/bottomSheetTheme 与 AppDialog 都直接取 token，
/// 改这里会自动带过去；本测试锁住分档值，防止手滑改回。
void main() {
  group('AppRadii', () {
    test('分档圆角值', () {
      expect(AppRadii.chip, 10);
      expect(AppRadii.card, 14);
      // WB_SPEC_230 第 3.3 节：菜单圆角 16（三处 ⋮ 菜单与全局 popupMenuTheme 共用）
      expect(AppRadii.menu, 16);
      expect(AppRadii.sheet, 20);
      expect(AppRadii.dialog, 24);
      expect(AppRadii.logo, 28);
    });

    test('层级递进：chip < card < menu < sheet < dialog < logo', () {
      expect(AppRadii.chip, lessThan(AppRadii.card));
      expect(AppRadii.card, lessThan(AppRadii.menu));
      expect(AppRadii.menu, lessThan(AppRadii.sheet));
      expect(AppRadii.sheet, lessThan(AppRadii.dialog));
      expect(AppRadii.dialog, lessThan(AppRadii.logo));
    });
  });
}
