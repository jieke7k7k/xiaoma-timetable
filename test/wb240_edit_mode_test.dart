import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';

/// WB_SPEC_242：240 的常驻 26dp 横栏（EditModeBanner）已删，改挂悬浮
/// 胶囊飘窗（EditModeToast）。本文件原为 240 的横栏验证，现改为 242
/// 的飘窗与胶囊验证。
void main() {
  group('WB_SPEC_242 编辑模式飘窗（一删横栏、一改胶囊、一替飘窗）验证', () {
    testWidgets('EditModeTitlePill 胶囊文案与 EditModeToast 飘窗逐字对齐', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const EditModeTitlePill()),
            body: Column(
              children: [EditModeToast(onDismiss: () {})],
            ),
          ),
        ),
      );

      // 1. AppBar 胶囊只写「✏️ 编辑模式」
      expect(find.text('✏️ 编辑模式'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('appbar_edit_mode_pill')),
        findsOneWidget,
      );

      // 2. 悬浮胶囊飘窗：新版文案（「已锁定滑动」已删），高 38dp
      final toastFinder = find.byKey(const ValueKey<String>('edit_mode_toast'));
      expect(toastFinder, findsOneWidget);
      expect(find.text('点空格加课 · 长按课程编辑'), findsOneWidget);
      expect(tester.getSize(toastFinder).height, 38.0);

      // 3. 无 2 秒 SnackBar，无常驻横栏
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('edit_mode_persistent_banner')),
        findsNothing,
      );

      // 收尾：把飘窗的 3 秒定时器跑完再结束，否则 teardown 报 Timer pending。
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
