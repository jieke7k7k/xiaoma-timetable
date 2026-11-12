import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';

/// 固定浏览周次，避免依赖真实时钟算出来的「本周」
class _FixedWeek extends DisplayWeekNotifier {
  @override
  int build() => 3;
}

/// WB_SPEC_232 第 4 节：导出图片去水印（三处全删）
///
/// 覆盖规格第 9 节第 5 组验收：导出图 widget 树里没有「小马课表」
/// 「由小马课表生成」字样；分享文字不含「· 小马课表」；
/// 导出页自身预览与导出图一致（同一棵子树，预览即导出内容）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Future<void> drain(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('导出图里找不到任何「小马课表」字样，标题与日期行还在', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [displayWeekProvider.overrideWith(_FixedWeek.new)],
        child: const MaterialApp(home: ShareImagePage()),
      ),
    );
    await drain(tester);

    // 三处水印全无（右上角小字、底部页脚、以及任何变体）
    expect(find.text('小马课表'), findsNothing);
    expect(find.text('由小马课表生成 · 无广告课表'), findsNothing);
    expect(find.textContaining('无广告课表'), findsNothing);

    // 该留的都在：标题（学期名 · 第 X 周课表）与日期范围行
    expect(find.text('默认学期 · 第 3 周课表'), findsOneWidget);
    expect(find.textContaining('月'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester, rounds: 2);
  });

  testWidgets('分享文案不再带「· 小马课表」，文件名仍保留（文件名不是图内水印）',
      (tester) async {
    // 分享走系统 Intent，widget 测试里拿不到；这里直接盯源码字面量，
    // 防止有人把它加回去（规格第 4 节第 3 点与「不动」清单）
    final src = File('lib/pages/share_image_page.dart').readAsStringSync();
    expect(src.contains("text: '我的课表（第 \$week 周）'"), isTrue);
    // 只盯「分享文案」那句旧字面量（注释里出现同样的字眼不算）
    expect(src.contains("'我的课表（第 \$week 周）· 小马课表'"), isFalse);
    // 文件名不动
    expect(src.contains("name: '小马课表-第\$week周.png'"), isTrue);
  });
}
