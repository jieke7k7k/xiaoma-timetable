import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';

/// WB-202 第 3 项补充：PageController 初始页码与标题周对齐
///
/// 回归冷启动 bug：旧代码在 initState 里按「学期未加载」算出 initialPage=0
/// （第 1 周），而 displayWeekProvider 首值在 build 里才求值（第 6 周），
/// 出现「标题第 6 周、网格第 1 周」。现在 PageController 延迟到学期就绪后
/// 创建，初始页 = 钳制后的显示周 - 1（weekViewInitialPage）。
void main() {
  group('weekViewInitialPage', () {
    test('正常学期：第 6 周 → 第 6 页（冷启动不再停在第 1 周）', () {
      expect(weekViewInitialPage(6, 20), 5);
    });

    test('第 1 周 → 第 1 页', () {
      expect(weekViewInitialPage(1, 20), 0);
    });

    test('学期已结束：第 25 周 / 共 20 周 → 钳到最后一周', () {
      expect(weekViewInitialPage(25, 20), 19);
    });

    test('未开学：第 0 周 → 钳到第 1 周', () {
      expect(weekViewInitialPage(0, 20), 0);
    });

    test('总周数未知（≤0）不限制上限，与 clampForPage 口径一致', () {
      // 总周数 ≤ 0 只保下限 1、不限制上限（调用方保证此时学期已就绪）
      expect(weekViewInitialPage(6, 0), 5);
      expect(weekViewInitialPage(-3, 0), 0);
    });
  });
}
