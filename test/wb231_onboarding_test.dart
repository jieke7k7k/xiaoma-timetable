import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/onboarding_page.dart';

/// WB_SPEC_231 第 3.1 / 3.2 节：引导页 5 条导入路径 + 直达的路由闭环。
///
/// 硬要求（规格第 3.2 节的验收点）：
/// 1. 点任意一条直达按钮时**先写 onboarding_done 标记、再导航**；
/// 2. 目标页由命名路由解析（教务网页抓取在无学期时退化为导入页）；
/// 3. 键名就是 `onboarding_done`（不是 Argon 写错的 `onboarding_completed`）。
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

  /// 用假路由替身接住导航：只断言「跳到了哪个页面」，不真渲染导入页
  Widget harness({required Future<void> Function() onDone}) {
    return ProviderScope(
      child: MaterialApp(
        routes: {
          '/import': (_) => const Scaffold(body: Text('IMPORT_PAGE')),
          '/course-edit': (_) => const Scaffold(body: Text('COURSE_EDIT_PAGE')),
          '/settings-widget': (_) =>
              const Scaffold(body: Text('WIDGET_SETTINGS')),
          '/settings-data': (_) => const Scaffold(body: Text('DATA_SETTINGS')),
        },
        home: OnboardingPage(onDone: onDone),
      ),
    );
  }

  /// 推进真实异步：FFI 内存库的 Future 只在 runAsync 的窗口里才会完成，
  /// 而直达链路是「读学期 → 写标记 → 导航」三段串行，所以要给多轮窗口
  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  /// 读标记必须放进 runAsync：FFI 库的 Future 在假异步里永远不完成（会挂到超时）
  Future<String?> readDone(WidgetTester tester) async {
    return tester.runAsync<String?>(() => Dao.instance.getSetting('onboarding_done'));
  }

  testWidgets('第 1 页列出 5 条导入路径，且没有 Excel 入口', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(onDone: () async {}));
    });
    await settle(tester);

    expect(find.text('课表从哪来'), findsOneWidget);
    expect(find.text('从教务官网导入'), findsOneWidget);
    expect(find.text('导入 ICS 日历文件'), findsOneWidget);
    expect(find.text('拍照 / 相册识别课表'), findsOneWidget);
    expect(find.text('导入 PDF 课表文件'), findsOneWidget);
    expect(find.text('手动建课'), findsOneWidget);
    // 规格第 2.1 / 9 节：全库没有 Excel 导入入口，引导页不得凭空造一个
    expect(find.textContaining('Excel'), findsNothing);
    expect(find.textContaining('xlsx'), findsNothing);
  });

  testWidgets('点 ICS 路径：先写标记再进导入页', (tester) async {
    var marked = false;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        harness(
          onDone: () async {
            // 打标记的同一段逻辑（与根门卫的 onDone 一字一致）
            await Dao.instance.setSetting('onboarding_done', '1');
            marked = true;
          },
        ),
      );
    });
    await settle(tester);

    await tester.tap(find.text('导入 ICS 日历文件'));
    await settle(tester);

    expect(marked, isTrue);
    expect(find.text('IMPORT_PAGE'), findsOneWidget);
    expect(await readDone(tester), '1');
  });

  testWidgets('手动建课：直达课程编辑页', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(onDone: () async {
        await Dao.instance.setSetting('onboarding_done', '1');
      }));
    });
    await settle(tester);

    await tester.tap(find.text('手动建课'));
    await settle(tester);

    expect(find.text('COURSE_EDIT_PAGE'), findsOneWidget);
    expect(await readDone(tester), '1');
  });

  testWidgets('教务网页抓取：没有学期时退化为导入页（不硬 push 缺 id 的抓取页）', (tester) async {
    // 建库时会种一条默认学期，这里先清空，模拟「全新用户还没有学期」
    await tester.runAsync(() => db.delete('semesters'));
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(onDone: () async {
        await Dao.instance.setSetting('onboarding_done', '1');
      }));
    });
    await settle(tester);

    await tester.tap(find.text('从教务官网导入'));
    await settle(tester);

    // 内存库里没有任何学期 → 退化进导入页，由导入页自己的「新建学期」流程兜住
    expect(find.text('IMPORT_PAGE'), findsOneWidget);
    expect(await readDone(tester), '1');
  });

  testWidgets('跳过：只写标记，不导航', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(onDone: () async {
        await Dao.instance.setSetting('onboarding_done', '1');
      }));
    });
    await settle(tester);

    await tester.tap(find.text('跳过'));
    await settle(tester);

    expect(await readDone(tester), '1');
    expect(find.text('IMPORT_PAGE'), findsNothing);
  });
}
