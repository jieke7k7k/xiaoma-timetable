import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';

/// 设置首页 QQ 式分级测试（2.0.5，WB_SPEC_205 第 1 节；2.0.6 第 1 节去掉重复小标题；
/// 2.0.7，WB_SPEC_208 第 3 节加分隔线断言）
///
/// 首页只留入口行（图标 + 名称 + 一行副标题 + ›），断言：
/// 1. 9+1 个入口行都在（9 个分类入口 + 智能助手组的两行）；
/// 2. 首页**不存在** Switch / Slider（证明控件已下沉到子页）；
/// 3. 「学期设置」「外观」「提醒」等同名文字在首页各只出现一次——
///    2.0.6 去掉分组小标题后，不再有「小标题 + 入口行」的重复；
/// 4. 首页存在分隔线（Divider 数量大于 0，即智能助手组内两行的 1px 分隔线）。
void main() {
  testWidgets('设置首页：9+1 个入口行 + 无 Switch/Slider + 同名文字各只出现一次', (tester) async {
    // 拉高测试画布，让懒加载的 ListView 把全部入口都建出来再断言
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump();

    // 10 个入口行标题（9 个分类入口 + 智能助手组的两行）
    const entries = [
      '学期设置',
      '外观',
      '提醒',
      '课表工具',
      '和智能助手聊聊',
      '智能助手设置',
      '学期与数据',
      '权限',
      '关于小马课表',
      '桌面小组件',
    ];
    for (final e in entries) {
      expect(find.text(e), findsOneWidget, reason: '入口行「$e」应出现在设置首页');
    }

    // 2.0.6 第 1 节：同名文字（原小标题与入口行重复）各只出现一次，即只剩入口行标题
    const duplicated = [
      '学期设置',
      '外观',
      '提醒',
      '课表工具',
      '学期与数据',
      '权限',
      '关于小马课表',
      '桌面小组件',
    ];
    for (final d in duplicated) {
      expect(find.text(d), findsOneWidget, reason: '「$d」在首页只应出现一次（无重复小标题）');
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

    // 2.0.7（WB_SPEC_208 第 3 节）：首页存在分隔线（智能助手组内两行之间的 1px 分隔线）
    expect(find.byType(Divider), findsWidgets);
  });
}
