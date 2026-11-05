import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/course_tools_page.dart';

/// 课表工具二级页测试（WB_SPEC_218 第 ④ 节）。
///
/// 2.1.7 起「菜单管理」从设置首页移入本页底部（路由不变，仅归拢层级），
/// 断言：
/// 1. 六个功能入口齐全（课程搜索 / 空闲时段 / 考试倒计时 / 导出课表图片 /
///    日期备注 / 菜单管理）；
/// 2. 菜单管理排在列表最底部（不再单独占设置首页一行）。
void main() {
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: CourseToolsPage()),
    );
    await tester.pump();
  }

  testWidgets('六个功能入口齐全', (tester) async {
    await pumpPage(tester);

    const titles = [
      '课程搜索',
      '空闲时段',
      '考试倒计时',
      '导出课表图片',
      '日期备注',
      '菜单管理',
    ];
    for (final t in titles) {
      expect(find.text(t), findsOneWidget, reason: '课表工具应显示「$t」');
    }
    // 六个入口 = 六行 ListTile
    expect(find.byType(ListTile), findsNWidgets(6));
  });

  testWidgets('菜单管理排在列表最底部（WB_SPEC_218 第 ④ 节移入）', (tester) async {
    await pumpPage(tester);

    // 菜单管理是最后一行：其纵坐标比其它任一行都靠下
    final menuY = tester.getTopLeft(find.text('菜单管理')).dy;
    for (final t in ['课程搜索', '空闲时段', '考试倒计时', '导出课表图片', '日期备注']) {
      expect(
        tester.getTopLeft(find.text(t)).dy,
        lessThan(menuY),
        reason: '「$t」应在「菜单管理」之上',
      );
    }
  });
}
