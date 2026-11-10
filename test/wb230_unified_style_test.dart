import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/app_choice_chip.dart';
import 'package:xiaoma_timetable/ui/app_popup_menu.dart';
import 'package:xiaoma_timetable/ui/app_styles.dart';
import 'package:xiaoma_timetable/ui/settings_icon_box.dart';
import 'package:xiaoma_timetable/widgets/app_dialog.dart';

/// WB_SPEC_230「全 App 风格统一」的组件级验收测试。
///
/// 覆盖规格第 9 节要求自动化的四项：
/// 1. 主页菜单 id → 语义色映射全表（7 项 + 未知 id 回落 schedule）；
/// 2. 菜单圆角 token（AppRadii.menu = 16）与三处菜单共用的构造器形态；
/// 3. [AppChoiceChip] 选中／未选中两态的底色、描边宽度、字重；
/// 4. `showAppConfirmDialog` 的 `barrierDismissible` 透传（含破坏性确认按钮色）。
///
/// 说明：`inputDecorationTheme` 是否压扁多行输入框无法在单测里可靠断言
/// （要真机软键盘顶起才暴露），按规格第 9 节以真机截图验收，不在此处硬造。
void main() {
  group('菜单（第 3 节）', () {
    test('主页菜单 id → 语义色全表，未知 id 回落 schedule', () {
      // 6 个可配置项 + 固定末尾「设置」，逐项对齐规格 3.2 节上色表
      expect(categoryForMenuId('course-search'), SettingsIconCategory.schedule);
      expect(categoryForMenuId('free-time'), SettingsIconCategory.data);
      expect(categoryForMenuId('share-image'), SettingsIconCategory.appearance);
      expect(categoryForMenuId('semester-manage'),
          SettingsIconCategory.schedule);
      expect(categoryForMenuId('exam-countdown'),
          SettingsIconCategory.reminder);
      expect(categoryForMenuId('import'), SettingsIconCategory.data);
      expect(categoryForMenuId('settings'), SettingsIconCategory.system);
      // 未知 id（理论上不会出现）回落课表蓝，绝不抛异常
      expect(categoryForMenuId('not-a-real-id'),
          SettingsIconCategory.schedule);
      expect(categoryForMenuId(''), SettingsIconCategory.schedule);
    });

    test('菜单圆角 token = 16，且夹在 card 与 sheet 之间', () {
      expect(AppRadii.menu, 16);
      expect(AppRadii.card, lessThan(AppRadii.menu));
      expect(AppRadii.menu, lessThan(AppRadii.sheet));
    });

    testWidgets('buildAppPopupMenuItem：彩色图标块 + 标题 + 零内边距', (tester) async {
      final item = buildAppPopupMenuItem<String>(
        value: '/course-search',
        icon: Icons.search,
        category: SettingsIconCategory.schedule,
        title: '课程搜索',
      );
      expect(item.value, '/course-search');
      // PopupMenuItem 的语义节点要求挂在真正的菜单里，故用 PopupMenuButton
      // 打开后断言（与三处 ⋮ 菜单的实际渲染路径一致）。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PopupMenuButton<String>(
                itemBuilder: (_) => [item],
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsIconBox), findsOneWidget);
      expect(find.text('课程搜索'), findsOneWidget);
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      expect(tile.contentPadding, EdgeInsets.zero);
      // 三处菜单共用同一构造器：分类原样落到图标块上
      final box = tester.widget<SettingsIconBox>(find.byType(SettingsIconBox));
      expect(box.category, SettingsIconCategory.schedule);
      expect(box.icon, Icons.search);
    });
  });

  group('单选 Chip（第 6 节）', () {
    Future<BoxDecoration> pumpChip(
      WidgetTester tester, {
      required bool selected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppChoiceChip(
                label: '使用读取到的作息',
                selected: selected,
                onSelected: () {},
              ),
            ),
          ),
        ),
      );
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppChoiceChip),
          matching: find.byType(Container),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('选中态：主色 12% 底 + 1.5dp 主色描边 + w600', (tester) async {
      final deco = await pumpChip(tester, selected: true);
      final cs = Theme.of(tester.element(find.byType(AppChoiceChip)))
          .colorScheme;
      expect(deco.color, cs.primary.withValues(alpha: 0.12));
      expect(deco.borderRadius, BorderRadius.circular(AppRadii.chip));
      final border = deco.border! as Border;
      expect(border.top.color, cs.primary);
      expect(border.top.width, 1.5);
      final text = tester.widget<Text>(find.text('使用读取到的作息'));
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.style?.fontSize, 12);
      expect(text.style?.color, cs.primary);
    });

    testWidgets('未选中态：灰 30% 底 + 1.0dp outlineVariant 描边 + 常规字重',
        (tester) async {
      final deco = await pumpChip(tester, selected: false);
      final cs = Theme.of(tester.element(find.byType(AppChoiceChip)))
          .colorScheme;
      expect(deco.color, cs.surfaceContainerHighest.withValues(alpha: 0.3));
      final border = deco.border! as Border;
      expect(border.top.color, cs.outlineVariant);
      expect(border.top.width, 1.0);
      final text = tester.widget<Text>(find.text('使用读取到的作息'));
      expect(text.style?.fontWeight, FontWeight.normal);
      expect(text.style?.color, cs.onSurface);
    });

    testWidgets('点按回调只触发一次（选中态由调用方维护）', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppChoiceChip(
                label: '灵动',
                selected: false,
                onSelected: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppChoiceChip));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('expanded: true 时占满可用宽（并排两枚等宽）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: Row(
                children: [
                  AppChoiceChip(
                    label: 'A',
                    selected: true,
                    onSelected: () {},
                    expanded: true,
                  ),
                  const SizedBox(width: 8),
                  AppChoiceChip(
                    label: 'B',
                    selected: false,
                    onSelected: () {},
                    expanded: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final chips = find.byType(AppChoiceChip);
      expect(chips, findsNWidgets(2));
      final w0 = tester.getSize(chips.at(0)).width;
      final w1 = tester.getSize(chips.at(1)).width;
      expect(w0, closeTo(w1, 0.01), reason: '两枚应等宽（各占一半）');
      expect(w0, greaterThan(100), reason: '应撑满可用宽而不是按内容宽');
    });
  });

  group('统一弹窗（第 4 节）', () {
    testWidgets('showAppConfirmDialog：barrierDismissible 透传给 showDialog',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      // barrierDismissible: false —— 点遮罩不关闭（permission_guide 的用法）
      final future = showAppConfirmDialog(
        ctx,
        title: '允许小马课表发通知',
        message: '上课提醒、今日课程常驻通知和备注都走通知栏。',
        confirmLabel: '去设置',
        cancelLabel: '跳过',
        barrierDismissible: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget,
          reason: 'barrierDismissible: false 时点遮罩不应关闭');
      // 点「跳过」正常返回 false
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(await future, isFalse);
      expect(find.byType(AppDialog), findsNothing);
    });

    testWidgets('showAppConfirmDialog：默认点遮罩可关闭', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final future = showAppConfirmDialog(
        ctx,
        title: '切换学期',
        message: '确定切换吗？',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(await future, isNull, reason: '点遮罩取消返回 null');
    });

    testWidgets('破坏性确认：确认按钮用 error 色；非破坏性用默认色',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      Color? confirmBg() {
        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('删除'),
            matching: find.byType(FilledButton),
          ),
        );
        return button.style?.backgroundColor?.resolve(<WidgetState>{});
      }

      final cs = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
      final destructive = showAppConfirmDialog(
        ctx,
        title: '删除学期',
        message: '确定删除吗？',
        confirmLabel: '删除',
        destructive: true,
      );
      await tester.pumpAndSettle();
      expect(confirmBg(), cs.error, reason: '破坏性确认按钮应为 error 色');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await destructive;

      final normal = showAppConfirmDialog(
        ctx,
        title: '切换学期',
        message: '确定切换吗？',
        confirmLabel: '删除',
      );
      await tester.pumpAndSettle();
      expect(confirmBg(), isNot(cs.error), reason: '非破坏性确认按钮不标红');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await normal;
    });

    testWidgets('showAppInfoDialog：barrierDismissible 默认 true，可显式关掉',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final future = showAppInfoDialog(
        ctx,
        title: '部分条目解析失败',
        message: '第 3 行缺少课程名',
        actionLabel: '知道了',
        barrierDismissible: false,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await future;
      expect(find.byType(AppDialog), findsNothing);
    });
  });
}
