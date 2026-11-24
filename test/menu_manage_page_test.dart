import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/menu_manage_page.dart';

/// 菜单管理子页测试（WB_SPEC_212 第 4 节；WB_SPEC_257 五项收口与新默认顺序）
///
/// 覆盖：
/// 1. 页面结构：五个可自定义项 + 五枚拖拽手柄 + 五枚显隐开关 + 「恢复默认」；
/// 2. 显隐开关接线：点开关后该项显隐状态更新；
/// 3. 拖拽排序接线：拖第一行手柄后顺序改变。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MenuManagePage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('渲染：五个可自定义项 + 五枚手柄/开关 + 恢复默认', (tester) async {
    await pumpPage(tester);

    const titles = [
      '导出课表图片',
      '考试倒计时',
      '空闲时段',
      '课程搜索',
      '学期管理',
    ];
    for (final t in titles) {
      expect(find.text(t), findsOneWidget, reason: '菜单管理应显示「$t」');
    }
    expect(find.text('导入课表'), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(5));
    expect(find.byType(Switch), findsNWidgets(5));
    expect(find.text('恢复默认'), findsOneWidget);
    // 「设置」不在这里（固定显示、不可自定义）
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('显隐开关接线：点第一项开关后该项变为隐藏', (tester) async {
    await pumpPage(tester);

    // 初始全显示：第一枚开关（导出课表图片）为开
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);

    await tester.tap(find.byType(Switch).first);
    // 让真实 DB 写在 runAsync 里落盘，再回来重建
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  testWidgets('拖拽排序接线：把第一行手柄向下拖后顺序改变', (tester) async {
    await pumpPage(tester);

    final firstHandle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(firstHandle));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    // 让真实 DB 写落盘
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // 导出课表图片被拖下去：考试倒计时应排到它上面
    final examY = tester.getTopLeft(find.text('考试倒计时')).dy;
    final shareY = tester.getTopLeft(find.text('导出课表图片')).dy;
    expect(examY, lessThan(shareY));
  });
}
