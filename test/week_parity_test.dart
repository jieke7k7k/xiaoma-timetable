import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/week_calc.dart';

/// 单双周计算（2.0.0 主页左上角那枚小标识的口径）
void main() {
  group('WeekCalc.parityLabel', () {
    test('奇数周是单周、偶数周是双周', () {
      expect(WeekCalc.parityLabel(1), '单周');
      expect(WeekCalc.parityLabel(2), '双周');
      expect(WeekCalc.parityLabel(7), '单周');
      expect(WeekCalc.parityLabel(20), '双周');
    });

    test('未开学（week ≤ 0）不显示', () {
      expect(WeekCalc.parityLabel(0), isNull);
      expect(WeekCalc.parityLabel(-3), isNull);
    });

    test('学期已结束（超过总周数）不显示', () {
      expect(WeekCalc.parityLabel(21, totalWeeks: 20), isNull);
      expect(WeekCalc.parityLabel(20, totalWeeks: 20), '双周');
    });

    test('总周数未知（≤ 0）时只按周次本身判断', () {
      expect(WeekCalc.parityLabel(21), '单周');
      expect(WeekCalc.parityLabel(21, totalWeeks: 0), '单周');
    });

    test('与 weekTypeText 口径一致（同一周次给同样的单双周）', () {
      for (var w = 1; w <= 20; w++) {
        expect(WeekCalc.parityLabel(w), WeekCalc.weekTypeText(w));
      }
    });
  });
}
