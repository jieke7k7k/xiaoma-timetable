import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/utils/week_parser.dart';
import 'package:xiaoma_timetable/widgets/week_picker.dart';

/// WB_SPEC_232 第 3 节：选周数「点头尾，中间自动连选」
///
/// 覆盖规格第 3 节验收清单：点 3 再点 6 得 3–6、点 6 再点 3 同样 3–6、
/// 点已选的 5 只取消 5、两段区间互不干扰、已选 3–14 时点单周只留区间内单周、
/// 空选点单周得全局单周、快捷按钮清锚点、文本解析后芯片与文本一致、锚点带外圈描边。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  List<int>? lastWeeks;
  int? lastType;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    lastWeeks = null;
    lastType = null;
  });

  tearDown(() async {
    await db.close();
  });

  /// 抽水式等待：让 currentSemesterProvider（真实 sqflite future）落地，
  /// 不留任何固定毫秒断言（WB_SPEC_231 的 sqflite 10 秒锁警告教训）
  Future<void> drain(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpPicker(
    WidgetTester tester, {
    List<int> weeks = const [],
    int weekType = WeekParser.allWeeks,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeekPicker(
                initialWeeks: weeks,
                initialWeekType: weekType,
                onChanged: (w, t) {
                  lastWeeks = w;
                  lastType = t;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await drain(tester);
  }

  Future<void> tapWeek(WidgetTester tester, int w) async {
    await tester.tap(find.byKey(ValueKey('week-chip-$w')));
    await tester.pump();
  }

  Future<void> tapQuick(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('点 3 再点 6 自动连成 3–6（含文本框同步）', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 3);
    // 第一下只选 3，并立起待配对锚点
    expect(lastWeeks, [3]);
    expect(find.byKey(const ValueKey('week-anchor-3')), findsOneWidget);
    await tapWeek(tester, 6);
    expect(lastWeeks, [3, 4, 5, 6]);
    // 连成区间后锚点消失
    expect(find.byKey(const ValueKey('week-anchor-3')), findsNothing);
    expect(fieldText(tester), WeekParser.toText([3, 4, 5, 6], lastType!));
  });

  testWidgets('点 6 再点 3 同样得 3–6（反序自动正序）', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 6);
    await tapWeek(tester, 3);
    expect(lastWeeks, [3, 4, 5, 6]);
  });

  testWidgets('点已选的 5 只取消 5，其余周次不动', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 1);
    await tapWeek(tester, 16);
    expect(lastWeeks!.length, 16);
    await tapWeek(tester, 5);
    expect(lastWeeks!.contains(5), isFalse);
    expect(lastWeeks!.length, 15);
    expect(lastWeeks!.contains(4), isTrue);
    expect(lastWeeks!.contains(6), isTrue);
  });

  testWidgets('两段不连续区间互不干扰：1–6 之后再连 9–14', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 1);
    await tapWeek(tester, 6);
    await tapWeek(tester, 9);
    await tapWeek(tester, 14);
    expect(lastWeeks, [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14]);
  });

  testWidgets('已选 3–14 时点单周只留区间内单周', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 3);
    await tapWeek(tester, 14);
    expect(lastWeeks!.length, 12);
    await tapQuick(tester, '单周');
    expect(lastWeeks, [3, 5, 7, 9, 11, 13]);
    // 单双周语义仍落到周次选择，不设全局 weekType
    expect(lastType, WeekParser.allWeeks);
  });

  testWidgets('已选 3–14 时点双周只留区间内双周', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 3);
    await tapWeek(tester, 14);
    await tapQuick(tester, '双周');
    expect(lastWeeks, [4, 6, 8, 10, 12, 14]);
  });

  testWidgets('空选时点单周得全局单周（1..20 的奇数周）', (tester) async {
    await pumpPicker(tester);
    await tapQuick(tester, '单周');
    expect(lastWeeks, [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]);
  });

  testWidgets('已是纯单周时再点单周仍按全局来（不塌成空集）', (tester) async {
    await pumpPicker(tester);
    await tapQuick(tester, '单周');
    await tapQuick(tester, '单周');
    expect(lastWeeks, [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]);
  });

  testWidgets('快捷按钮会把待配对锚点清掉', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 3); // 立锚点
    expect(find.byKey(const ValueKey('week-anchor-3')), findsOneWidget);
    await tapQuick(tester, '清空');
    expect(find.byKey(const ValueKey('week-anchor-3')), findsNothing);
    // 清空后点 5 是「第一下」，不该跟 3 连成 3–5
    await tapWeek(tester, 5);
    expect(lastWeeks, [5]);
  });

  testWidgets('文本解析失败时待配对锚点也被清掉（Kimi 复审低）', (tester) async {
    await pumpPicker(tester);
    await tapWeek(tester, 3); // 立锚点
    expect(find.byKey(const ValueKey('week-anchor-3')), findsOneWidget);
    await tester.enterText(find.byType(TextField), '瞎写一通');
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.pump();
    // 解析失败：红字提示出现，锚点复位；已选的 3 不动
    expect(find.byKey(const ValueKey('week-anchor-3')), findsNothing);
    expect(lastWeeks, [3]);
    // 复位后点 5 是「第一下」：只把 5 加入选择、不连成区间——
    // 应得 [3, 5]，若锚点没清掉会连成 [3, 4, 5]
    await tapWeek(tester, 5);
    expect(lastWeeks, [3, 5]);
  });

  testWidgets('文本框手输「1-8, 10-16单周」解析后芯片与文本一致', (tester) async {
    await pumpPicker(tester);
    await tester.enterText(find.byType(TextField), '1-8, 10-16单周');
    await tester.tap(find.byIcon(Icons.auto_fix_high));
    await tester.pump();
    // 期望值直接取解析器口径（「单周」= 奇数周，10-16 段内是 11/13/15），
    // 不在这里另立一套解释
    final expected = WeekParser.parse('1-8, 10-16单周').weeks;
    expect(lastWeeks, expected);
    expect(expected.contains(11), isTrue);
    // 芯片与文本框保持一致：文本框保留用户手输的简写（解析不改写原文），
    // 用同一份原文再解析一次，结果必须与当前芯片完全相同
    expect(WeekParser.parse(fieldText(tester)).weeks, lastWeeks);
    expect(fieldText(tester), '1-8, 10-16单周');
  });

  testWidgets('锚点芯片带 1.5dp 外圈描边，且芯片布局尺寸不变', (tester) async {
    await pumpPicker(tester);
    final before = tester.getSize(find.byKey(const ValueKey('week-chip-3')));
    await tapWeek(tester, 3);
    final ring = find.byKey(const ValueKey('week-anchor-3'));
    expect(ring, findsOneWidget);
    final deco = tester.widget<Container>(ring).decoration as BoxDecoration;
    expect((deco.border as Border).top.width, 1.5);
    expect(deco.border!.top.color, Theme.of(tester.element(ring)).colorScheme.primary);
    // 外圈画在盒子里，芯片整体尺寸仍是 38×34，整行不会被顶歪
    expect(tester.getSize(find.byKey(const ValueKey('week-chip-3'))), before);
    expect(before, const Size(38, 34));
  });

  testWidgets('文本框仍在（§1.1 第 2 点：能手输简写）', (tester) async {
    await pumpPicker(tester);
    expect(find.text('周次文本（可选）'), findsOneWidget);
    expect(find.text('如 1-8, 10-16单周'), findsOneWidget);
    // 源码还在，确认不是被悄悄删掉
    expect(File('lib/widgets/week_picker.dart').existsSync(), isTrue);
  });
}
