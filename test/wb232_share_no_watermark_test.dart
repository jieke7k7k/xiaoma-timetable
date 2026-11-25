import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';

import 'helpers/pump_helpers.dart';

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
  group('导出图去水印（Widget）', () {
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

    // L8（DeepSeek 264 复审 B 段）：本地 drain 迁到 helpers 的 drainAsync，
    // 语义对齐——本地 drain 默认 6 轮 × (60ms 真实窗口 + 80ms 泵) + 尾部 settle；
    // drainAsync 同为 60ms/80ms，rounds 显式传 6；尾部 pumpAndSettle 在本页无无限动画时
    // 本可保留，但 drainAsync 的 6 轮已足够排空 DB 异步，settled 后断言一致。
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
      await drainAsync(tester, rounds: 6);

      // 三处水印全无（右上角小字、底部页脚、以及任何变体）
      expect(find.text('小马课表'), findsNothing);
      expect(find.text('由小马课表生成 · 无广告课表'), findsNothing);
      expect(find.textContaining('无广告课表'), findsNothing);

      // 该留的都在：标题（学期名 · 第 X 周课表）与日期范围行
      expect(find.text('默认学期 · 第 3 周课表'), findsOneWidget);
      expect(find.textContaining('月'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await drainAsync(tester, rounds: 2);
    });
  });

  // T13：拆为独立纯 test（不依赖 WidgetTester 与内存 SQLite），
  // 直接单测 share_image_page.dart 抽出的纯函数 buildWeekShareText / buildWeekShareFileName。
  test('分享文案不再带「· 小马课表」，文件名仍保留（文件名不是图内水印）', () {
    final shareText = buildWeekShareText(3);
    final fileName = buildWeekShareFileName(3);

    expect(shareText, '我的课表（第 3 周）');
    expect(shareText, isNot(contains('小马课表')));
    expect(fileName, '小马课表-第3周.png');
  });
}
