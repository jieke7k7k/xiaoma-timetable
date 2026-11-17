import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';

void main() {
  group('WB_SPEC_240 编辑模式修订版（一删、二改、一替）验证', () {
    testWidgets('EditModeTitlePill 与 EditModeBanner 尺寸及文案逐字对齐样品', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const EditModeTitlePill()),
            body: const Column(children: [EditModeBanner()]),
          ),
        ),
      );

      // 1. AppBar 胶囊只写「✏️ 编辑模式」
      expect(find.text('✏️ 编辑模式'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('appbar_edit_mode_pill')),
        findsOneWidget,
      );

      // 2. 常驻 26dp 提示条高度与逐字文案
      final bannerFinder = find.byKey(
        const ValueKey<String>('edit_mode_persistent_banner'),
      );
      expect(bannerFinder, findsOneWidget);
      expect(find.text('点空白格加课 · 长按课程可编辑（已锁定滑动）'), findsOneWidget);
      expect(tester.getSize(bannerFinder).height, 26.0);

      // 3. 无 2 秒 SnackBar
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
