import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/page_transitions.dart';

/// 2.1.0 返修测试：页面转场时长（WB_SPEC_212 第 5 节）。
///
/// 2.1.3 起本文件只保留转场断言——同批加的「未解锁不放行受保护路由」守卫测试
/// 随守卫组件与相关入口一并删除（WB_SPEC_214 第 1 节）。
void main() {
  group('页面转场（WB_SPEC_212 第 5 节）', () {
    test('正向与返回时长均为 300ms', () {
      const builder = AppSlidePageTransitionsBuilder(android: true);
      expect(builder.transitionDuration, const Duration(milliseconds: 300));
      expect(
        builder.reverseTransitionDuration,
        const Duration(milliseconds: 300),
      );
      const iosBuilder = AppSlidePageTransitionsBuilder(android: false);
      expect(iosBuilder.transitionDuration, const Duration(milliseconds: 300));
    });
  });
}
