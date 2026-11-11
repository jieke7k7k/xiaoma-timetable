import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/main.dart';
import 'package:xiaoma_timetable/pages/course_edit_page.dart';
import 'package:xiaoma_timetable/ui/clean_gap_input_border.dart';

/// WB_SPEC_231 第 11 节：输入框标签留空。
///
/// 像素级效果以真机目视验收为准（规格第 8 / 11.4 节），widget 测试只断言
/// 「结构对」：全局主题的五态边框都换成了 [CleanGapOutlineInputBorder]、
/// gapPadding 是 6、衬底两色取对，且编辑页 8 处带标签的输入框都没有各自
/// 手写边框（全部继承全局主题，一处改全站生效）。
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

  void expectCleanGap(InputDecorationThemeData theme, ColorScheme scheme) {
    for (final border in [
      theme.border,
      theme.enabledBorder,
      theme.focusedBorder,
      theme.errorBorder,
      theme.focusedErrorBorder,
    ]) {
      expect(border, isA<CleanGapOutlineInputBorder>());
      final gap = border! as CleanGapOutlineInputBorder;
      expect(gap.gapPadding, 6.0, reason: 'gapPadding 采纳 4.0 → 6.0');
      expect(gap.pageBackgroundColor, scheme.surface);
      expect(gap.fillColor, scheme.surfaceContainerHighest);
      // 圆角、描边宽度沿用 AppRadii.chip / 原生行为
      expect(gap.borderRadius, BorderRadius.circular(10));
    }
  }

  testWidgets('浅色/深色全局主题：五态边框全部换成带缺口的双色衬底边框', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const ProviderScope(child: SimpleTimetableApp()));
    });
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expectCleanGap(app.theme!.inputDecorationTheme, app.theme!.colorScheme);
    expectCleanGap(
      app.darkTheme!.inputDecorationTheme,
      app.darkTheme!.colorScheme,
    );
    // 填充与主题的其它 token 一字未动
    expect(app.theme!.inputDecorationTheme.filled, isTrue);
    expect(
      app.theme!.inputDecorationTheme.fillColor,
      app.theme!.colorScheme.surfaceContainerHighest,
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
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump(const Duration(milliseconds: 200));

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

  test('带缺口的边框：缺口处画双色衬底，不抛异常；无缺口时只走原生绘制', () {
    const border = CleanGapOutlineInputBorder(
      pageBackgroundColor: Color(0xFFF5F2EC),
      fillColor: Color(0xFFE7E3DA),
    );
    expect(border.gapPadding, 6.0);

    for (final gap in <double?>[null, 40.0]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      border.paint(
        canvas,
        const Rect.fromLTWH(0, 0, 200, 56),
        gapStart: gap,
        gapExtent: gap == null ? 0 : 30,
        textDirection: TextDirection.ltr,
      );
      // 录制不抛异常即通过（像素效果靠真机目视）
      expect(recorder.endRecording(), isNotNull);
    }

    // copyWith 要保住衬底两色，否则 focusedBorder 一换就丢色
    final copy = border.copyWith(
      borderSide: const BorderSide(color: Color(0xFF000000), width: 1.5),
    );
    expect(copy.pageBackgroundColor, const Color(0xFFF5F2EC));
    expect(copy.fillColor, const Color(0xFFE7E3DA));
    expect(copy.gapPadding, 6.0);
  });
}
