import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';

/// 设置首页 QQ 式分级测试（2.0.5，WB_SPEC_205 第 1 节）
///
/// 首页只保留分组标题 + 每类一行入口行，断言：
/// 1. 9 个分类入口（分组标题）都在；
/// 2. 首页**不存在** Switch / Slider（证明控件已下沉到子页）。
void main() {
  testWidgets('设置首页：9 个分类入口 + 无 Switch/Slider', (tester) async {
    // 拉高测试画布，让懒加载的 ListView 把全部入口都建出来再断言
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();

    // 9 个分类（分组标题，每个分类至少出现一次）
    const categories = [
      '学期设置',
      '外观',
      '提醒',
      '课表工具',
      '智能助手',
      '学期与数据',
      '权限',
      '关于小马课表',
      '桌面小组件',
    ];
    for (final c in categories) {
      expect(find.text(c), findsWidgets, reason: '分类「$c」应出现在设置首页');
    }

    // 各分类入口行的一行副标题（证明入口行存在，而不只是分组标题）
    expect(find.text('学期名称、开学日期、总周数'), findsOneWidget);
    expect(find.text('主题、实时预览、格子外观、课程配色与显示字体'), findsOneWidget);
    expect(find.text('上课提醒、上课播报、今日课程常驻通知、提前提醒'), findsOneWidget);
    expect(find.text('导入课表、学期管理、备份恢复、导出 ICS、数据管理'), findsOneWidget);
    expect(find.text('通知、精确闹钟、电池优化'), findsOneWidget);
    expect(find.text('今日课程小组件的添加说明'), findsOneWidget);

    // 首页不出现任何开关 / 滑杆（外观/提醒等控件已下沉到子页）
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });
}
