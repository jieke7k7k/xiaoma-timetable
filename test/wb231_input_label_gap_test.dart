import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/ui/app_styles.dart';
import 'package:xiaoma_timetable/ui/clean_gap_input_border.dart';

/// WB_SPEC_231 第 12.1 节：输入框标签留空改按 1B。
///
/// 像素级效果以真机目视验收为准（规格第 12.3 节），widget 测试断言：
/// - 全局主题五态边框都换成 1B 的 [CleanGapOutlineInputBorder]、gapPadding 6、
///   填充色取 `surfaceContainerHighest`、`filled: false`（原生填充停掉）、
///   contentPadding 是 Argon 给的 (14, 18, 14, 10)；
/// - 编辑页 8 处带标签的输入框都没有各自手写边框（全局改一处、全站生效）；
/// - 1B 的几何：标签浮起时填充/描边整体下移 `9.0 * gapPercentage`，框顶横线
///   在标签缺口处**不断**；空态框停在原位。
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

  void expect1B(InputDecorationThemeData theme, ColorScheme scheme) {
    for (final border in [
      theme.border,
      theme.enabledBorder,
      theme.focusedBorder,
      theme.errorBorder,
      theme.focusedErrorBorder,
    ]) {
      expect(border, isA<CleanGapOutlineInputBorder>());
      final gap = border! as CleanGapOutlineInputBorder;
      expect(gap.gapPadding, 6.0, reason: '1B 不动 gapPadding');
      expect(gap.fillColor, scheme.surfaceContainerHighest,
          reason: '填充由边框自画，色值与主题同一 token');
      // 圆角、描边宽度沿用 AppRadii.chip / 原生行为
      expect(gap.borderRadius, BorderRadius.circular(AppRadii.chip));
    }
  }

  testWidgets('浅色/深色全局主题：五态边框全是 1B 边框、原生填充已停、内边距是 Argon 值',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const ProviderScope(child: SimpleTimetableApp()));
    });
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect1B(app.theme!.inputDecorationTheme, app.theme!.colorScheme);
    expect1B(
      app.darkTheme!.inputDecorationTheme,
      app.darkTheme!.colorScheme,
    );
    // 1B：原生填充必须关掉，否则「原生一层 + 边框自画一层」叠出双层色差
    expect(app.theme!.inputDecorationTheme.filled, isFalse);
    expect(app.darkTheme!.inputDecorationTheme.filled, isFalse);
    // Argon 给的配套内边距：上 18 / 下 10（框顶下移后仍让文字视觉居中）
    expect(
      app.theme!.inputDecorationTheme.contentPadding,
      const EdgeInsets.fromLTRB(14, 18, 14, 10),
    );
    expect(
      app.darkTheme!.inputDecorationTheme.contentPadding,
      const EdgeInsets.fromLTRB(14, 18, 14, 10),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('编辑页 8 处输入框都不手写边框（全部继承全局主题）', (tester) async {
    // 拉高画布，让 ListView 把备注（页面最下面那个输入框）也建出来
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CourseEditPage()),
        ),
      );
    });
    // 新建页 _load 会先等课程列表就绪（§12 第二批补测 1 的修复）：
    // 固定 300ms＋200ms 的抽水不够把排队的库查询都跑完，sqflite 的
    // 10 秒锁警告定时器会在 teardown 时还挂着（“A Timer is still pending”）；
    // 按轮次抽干、再 pumpAndSettle，等页面真正静止再断言。
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    // 5 个 TextField（课程名 / 老师 / 教室 / 周次文本 / 备注）都没有手写边框
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    final textLabels = <String>{};
    for (final f in fields) {
      expect(f.decoration?.border, isNull);
      expect(f.decoration?.enabledBorder, isNull);
      expect(f.decoration?.focusedBorder, isNull);
      final label = f.decoration?.labelText;
      if (label != null) textLabels.add(label);
    }
    // 3 个 DropdownButtonFormField（星期 / 开始节次 / 结束节次）同样没有手写边框
    final dropdowns = tester
        .widgetList<DropdownButtonFormField<int>>(
          find.byType(DropdownButtonFormField<int>),
        )
        .toList();
    expect(dropdowns.length, 3);
    for (final d in dropdowns) {
      expect(d.decoration.border, isNull);
      expect(d.decoration.enabledBorder, isNull);
      expect(d.decoration.focusedBorder, isNull);
      textLabels.add(d.decoration.labelText!);
    }
    // 8 处带标签的输入框齐了
    expect(textLabels, {
      '课程名 *',
      '老师（可空）',
      '教室（可空）',
      '星期',
      '开始节次',
      '结束节次',
      '周次文本（可选）',
      '备注（可空）',
    });

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('1B 几何（逐像素）', () {
    const canvasW = 200;
    const canvasH = 120;

    /// 以 [gapPercentage] 画出边框，返回按 (x, y) 取色的函数
    Future<Color Function(int x, int y)> paintAndSample(
      WidgetTester tester,
      CleanGapOutlineInputBorder border, {
      double? gapStart,
      double gapExtent = 0.0,
      double gapPercentage = 0.0,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      border.paint(
        canvas,
        const Rect.fromLTWH(0, 0, 160, 80),
        gapStart: gapStart,
        gapExtent: gapExtent,
        gapPercentage: gapPercentage,
        textDirection: TextDirection.ltr,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(canvasW, canvasH);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      return (int x, int y) {
        final o = (y * canvasW + x) * 4;
        return Color.fromARGB(
          bytes[o + 3],
          bytes[o],
          bytes[o + 1],
          bytes[o + 2],
        );
      };
    }

    // 只画填充（borderSide 为 none），便于单看「框顶落在哪一行」
    const fillOnly = CleanGapOutlineInputBorder(
      borderSide: BorderSide.none,
      fillColor: Color(0xFFFF0000),
    );
    // 填充红 + 白描边 2px：用来验「框顶横线在标签缺口处不断」
    const withBorder = CleanGapOutlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFFFFFFF), width: 2),
      fillColor: Color(0xFFFF0000),
    );

    testWidgets('空态（gapExtent == 0）：框停在原位，标签区照常是框内填充', (tester) async {
      await tester.runAsync(() async {
        final at = await paintAndSample(tester, fillOnly);
        // rect.top = 0 → 框顶就是 y=0，y=1 已是填充
        expect(at(80, 1).a, 1.0);
        expect(at(80, 1), const Color(0xFFFF0000));
        // 框底在 y=80，之外是透明（没有被整体下移撑出去）
        expect(at(80, 82).a, 0.0);
      });
    });

    testWidgets('标签满浮起（percentage == 1）：整个框下移 9dp，框顶以上是透明', (tester) async {
      await tester.runAsync(() async {
        final at = await paintAndSample(
          tester,
          fillOnly,
          gapStart: 60,
          gapExtent: 40,
          gapPercentage: 1.0,
        );
        // 原 rect.top = 0 → 下移 9：y=7 还在框外（完全透明），y=10 已在框内
        expect(at(80, 7).a, 0.0, reason: '标签下方要留出可见间隙，不能贴住框顶');
        expect(at(80, 10), const Color(0xFFFF0000));
      });
    });

    testWidgets('浮起进度按 gapPercentage 比例下移（0.5 → 4.5dp）', (tester) async {
      await tester.runAsync(() async {
        final at = await paintAndSample(
          tester,
          fillOnly,
          gapStart: 60,
          gapExtent: 40,
          gapPercentage: 0.5,
        );
        expect(at(80, 2).a, 0.0, reason: '下移 4.5dp：y=2 还在框外');
        expect(at(80, 7), const Color(0xFFFF0000), reason: 'y=7 已在框内');
      });
    });

    testWidgets('框顶横线在标签缺口处不断（不画缺口，一笔画完）', (tester) async {
      await tester.runAsync(() async {
        final at = await paintAndSample(
          tester,
          withBorder,
          gapStart: 60,
          gapExtent: 40,
          gapPercentage: 1.0,
        );
        // 框顶落在 y=9；描边 2px 覆盖 y=8~10。x=80 正落在标签缺口范围内
        //（gapStart-padding .. gapStart+extent+padding），1B 下这里仍是描边色
        expect(at(80, 9), const Color(0xFFFFFFFF),
            reason: '缺口位置也要有描边——横线完整不断才是 1B');
        // 缺口两侧同样是描边
        expect(at(20, 9), const Color(0xFFFFFFFF));
        expect(at(140, 9), const Color(0xFFFFFFFF));
      });
    });
  });

  test('构造/copyWith：只带 fillColor，换态不丢填充色', () {
    const border = CleanGapOutlineInputBorder(
      fillColor: Color(0xFFE7E3DA),
    );
    expect(border.gapPadding, 6.0);

    final copy = border.copyWith(
      borderSide: const BorderSide(color: Color(0xFF000000), width: 1.5),
    );
    expect(copy.fillColor, const Color(0xFFE7E3DA),
        reason: 'focusedBorder 一换态不能丢掉自画填充色');
    expect(copy.gapPadding, 6.0);
    expect(copy.borderSide.width, 1.5);
  });
}
