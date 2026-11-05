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
      expect(AppRadii.sheet, 20);
      expect(AppRadii.dialog, 24);
      expect(AppRadii.logo, 28);
    });

    test('层级递进：chip < card < sheet < dialog < logo', () {
      expect(AppRadii.chip, lessThan(AppRadii.card));
      expect(AppRadii.card, lessThan(AppRadii.sheet));
      expect(AppRadii.sheet, lessThan(AppRadii.dialog));
      expect(AppRadii.dialog, lessThan(AppRadii.logo));
    });
  });
}
