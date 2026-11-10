import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/settings_page.dart';
import 'package:xiaoma_timetable/pages/settings_sections.dart';
import 'package:xiaoma_timetable/services/permission_service.dart';
import 'package:xiaoma_timetable/ui/settings_icon_box.dart';

/// 设置图标上色测试（WB_SPEC_222：语义化分组柔和彩色底块）。
///
/// 断言：
/// 1. 组件级：5 个分类在浅色／深色下，方块 32×32、圆角 10、图标 20，
///    图标色等于规格书字面值，底色透明度浅 0.18／深 0.22（system 组浅 0.12／深 0.18），
///    底色随 primary 变化（不是写死色值）；
/// 2. 首页级：7 行入口 leading 分类与映射表一致，chevron 20dp，分隔线 indent 72，
///    分组标题颜色 onSurfaceVariant 60%；
/// 3. 二级页级：抽查学期页 badge→schedule、提醒页 pin→reminder、数据页 backup→data、
///    小组件页 widgets→appearance、权限页 shield→schedule。
void main() {
  // 浅色／深色下各分类的期望图标色（规格书 §3 映射表字面值）。
  const lightIcons = {
    SettingsIconCategory.schedule: Color(0xFF2F6BB3),
    SettingsIconCategory.appearance: Color(0xFF7A3B9B),
    SettingsIconCategory.reminder: Color(0xFFD35400),
    SettingsIconCategory.data: Color(0xFF1E8449),
    SettingsIconCategory.system: Color(0xFF616A6B),
    // WB_SPEC_230 第 3.3 节：destructive 走 M3 error 红
    SettingsIconCategory.destructive: Color(0xFFB3261E),
  };
  const darkIcons = {
    SettingsIconCategory.schedule: Color(0xFF7AB3F0),
    SettingsIconCategory.appearance: Color(0xFFB07BD0),
    SettingsIconCategory.reminder: Color(0xFFF5A623),
    SettingsIconCategory.data: Color(0xFF58D68D),
    SettingsIconCategory.system: Color(0xFFAEB6BF),
    SettingsIconCategory.destructive: Color(0xFFF2B8B5),
  };
  const bases = {
    SettingsIconCategory.schedule: Color(0xFF4A90D9),
    SettingsIconCategory.appearance: Color(0xFF8E44AD),
    SettingsIconCategory.reminder: Color(0xFFF39C12),
    SettingsIconCategory.data: Color(0xFF27AE60),
    SettingsIconCategory.system: Color(0xFF7F8C8D),
    SettingsIconCategory.destructive: Color(0xFFB3261E),
  };

  // 222 复审优化建议 3：枚举字面值直达断言——实现方手滑改错枚举色值时，
  // 失败信息直接指向枚举本身，而不是公式算出的期望值。
  test('枚举色值字面值与规格书 §3 一致', () {
    for (final category in SettingsIconCategory.values) {
      expect(category.base, bases[category]);
      expect(category.lightIcon, lightIcons[category]);
      expect(category.darkIcon, darkIcons[category]);
    }
  });

  group('SettingsIconBox 组件', () {
    Future<void> pumpBox(
      WidgetTester tester,
      SettingsIconCategory category, {
      required bool dark,
      Color primary = const Color(0xFF8C6246),
    }) async {
      final scheme = dark
          ? ColorScheme.dark(primary: primary)
          : ColorScheme.light(primary: primary);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Scaffold(
            body: Center(
              child: SettingsIconBox(
                icon: Icons.event_outlined,
                category: category,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // MaterialApp 用 AnimatedTheme 包主题：二次 pump 换主题时要等 200ms
      // 动画走完，否则读到的还是旧主题的 primary。
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final category in SettingsIconCategory.values) {
      testWidgets('浅色：$category 方块 32×32、圆角 10、图标 20、图标色与透明度符合规格',
          (tester) async {
        await pumpBox(tester, category, dark: false);
        final box = find.byType(SettingsIconBox);
        expect(tester.getSize(box), const Size(32, 32));
        final container = tester.widget<Container>(
          find.descendant(of: box, matching: find.byType(Container)),
        );
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(10));
        final scheme = Theme.of(tester.element(box)).colorScheme;
        // WB_SPEC_230 第 3.3 节：destructive 与 system 同档透明度，且底色
        // 直接取 scheme.error（不混 primary），图标也用 scheme.error。
        final destructive = category == SettingsIconCategory.destructive;
        final expectedAlpha = (category == SettingsIconCategory.system ||
                destructive)
            ? 0.12
            : 0.18;
        final expectedBg = destructive
            ? scheme.error.withValues(alpha: expectedAlpha)
            : Color.lerp(
                bases[category]!,
                scheme.primary,
                0.15,
              )!.withValues(alpha: expectedAlpha);
        expect(decoration.color, expectedBg);
        final icon = tester.widget<Icon>(
          find.descendant(of: box, matching: find.byType(Icon)),
        );
        expect(icon.size, 20);
        expect(icon.color, destructive ? scheme.error : lightIcons[category]);
      });

      testWidgets('深色：$category 图标色与透明度符合规格', (tester) async {
        await pumpBox(tester, category, dark: true);
        final box = find.byType(SettingsIconBox);
        final container = tester.widget<Container>(
          find.descendant(of: box, matching: find.byType(Container)),
        );
        final decoration = container.decoration as BoxDecoration;
        final scheme = Theme.of(tester.element(box)).colorScheme;
        final destructive = category == SettingsIconCategory.destructive;
        final expectedAlpha = (category == SettingsIconCategory.system ||
                destructive)
            ? 0.18
            : 0.22;
        final expectedBg = destructive
            ? scheme.error.withValues(alpha: expectedAlpha)
            : Color.lerp(
                bases[category]!,
                scheme.primary,
                0.15,
              )!.withValues(alpha: expectedAlpha);
        expect(decoration.color, expectedBg);
        final icon = tester.widget<Icon>(
          find.descendant(of: box, matching: find.byType(Icon)),
        );
        expect(icon.color, destructive ? scheme.error : darkIcons[category]);
      });
    }

    testWidgets('底色随 primary 变化（不是写死色值）', (tester) async {
      Color bgOf() {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(SettingsIconBox),
            matching: find.byType(Container),
          ),
        );
        return (container.decoration as BoxDecoration).color!;
      }

      await pumpBox(tester, SettingsIconCategory.schedule, dark: false);
      final first = bgOf();
      await pumpBox(
        tester,
        SettingsIconCategory.schedule,
        dark: false,
        primary: const Color(0xFF3B6E9C),
      );
      expect(bgOf(), isNot(first), reason: '换主题时底色应跟着 primary 走');
    });

    // WB_SPEC_230 第 3.3 节：destructive 必须稳定是「错误红」，不走
    // Color.lerp(base, primary, 0.15)——混了主色会把红带偏成砖红。
    testWidgets('destructive：换 primary 底色不变、图标始终取 scheme.error',
        (tester) async {
      Color bgOf() {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(SettingsIconBox),
            matching: find.byType(Container),
          ),
        );
        return (container.decoration as BoxDecoration).color!;
      }

      Color iconOf() => tester
          .widget<Icon>(
            find.descendant(
              of: find.byType(SettingsIconBox),
              matching: find.byType(Icon),
            ),
          )
          .color!;

      await pumpBox(tester, SettingsIconCategory.destructive, dark: false);
      final firstBg = bgOf();
      final firstIcon = iconOf();
      final lightError = Theme.of(tester.element(find.byType(SettingsIconBox)))
          .colorScheme
          .error;
      expect(firstIcon, lightError);
      expect(
        firstBg,
        lightError.withValues(alpha: 0.12),
        reason: 'destructive 底色应为 scheme.error 12%（浅色）',
      );

      await pumpBox(
        tester,
        SettingsIconCategory.destructive,
        dark: false,
        primary: const Color(0xFF3B6E9C),
      );
      expect(bgOf(), firstBg, reason: 'destructive 底色不应跟随 primary 变化');
      expect(iconOf(), firstIcon);
    });
  });

  group('设置首页与二级页', () {
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
      // 权限页用测试替身，不走平台通道。
      PermissionService.debugStatusOverride = () async =>
          const PermissionSnapshot(
            notification: true,
            exactAlarm: true,
            battery: true,
          );
    });

    tearDown(() async {
      PermissionService.debugStatusOverride = null;
      await db.close();
    });

    Future<void> pumpPage(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1200, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: page)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// 某行标题所在 ListTile 里的图标盒分类。
    SettingsIconCategory categoryOfRow(WidgetTester tester, String title) {
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(ListTile),
      );
      final box = find.descendant(
        of: tile,
        matching: find.byType(SettingsIconBox),
      );
      expect(box, findsOneWidget, reason: '「$title」行应有一个图标盒');
      return tester.widget<SettingsIconBox>(box).category;
    }

    testWidgets('首页：7 行入口分类与映射表一致', (tester) async {
      await pumpPage(tester, const SettingsPage());
      const expected = {
        '当前学期与周次': SettingsIconCategory.schedule,
        '课表工具箱': SettingsIconCategory.schedule,
        '节次时间设置': SettingsIconCategory.schedule,
        '外观与底栏': SettingsIconCategory.appearance,
        '桌面小组件': SettingsIconCategory.appearance,
        '上课提醒': SettingsIconCategory.reminder,
        '数据备份与换机': SettingsIconCategory.data,
      };
      for (final e in expected.entries) {
        expect(
          categoryOfRow(tester, e.key),
          e.value,
          reason: '「${e.key}」行分类应为 ${e.value}',
        );
      }
    });

    testWidgets('首页：chevron 20dp、分隔线 indent 72、分组标题 onSurfaceVariant 60%',
        (tester) async {
      await pumpPage(tester, const SettingsPage());
      // 期望值从泵入的主题里取：ColorScheme.light() 在当前 Flutter 里
      // 是动态推导的构造，与 ThemeData 默认 scheme 不一致，不能直接拿它算。
      final theme = Theme.of(tester.element(find.byType(SettingsPage)));
      final expectedMuted =
          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
      final chevrons = find.byIcon(Icons.chevron_right);
      expect(chevrons, findsWidgets);
      for (final element in chevrons.evaluate()) {
        final icon = element.widget as Icon;
        expect(icon.size, 20, reason: '行尾箭头应为 20dp');
        expect(icon.color, expectedMuted);
      }
      final dividers = find.byType(Divider);
      expect(dividers, findsWidgets);
      for (final element in dividers.evaluate()) {
        final divider = element.widget as Divider;
        expect(divider.indent, 72, reason: '分隔线应与标题文字左缘对齐（x=72）');
        expect(divider.endIndent, 16);
        expect(divider.thickness, 0.5);
      }
      for (final g in ['课表与学期', '展示与桌面', '数据与安全']) {
        final text = tester.widget<Text>(find.text(g));
        expect(
          text.style?.color,
          expectedMuted,
          reason: '分组「$g」标题应为 onSurfaceVariant 60%',
        );
      }
    });

    testWidgets('首页 ⋮ 菜单：权限自检→schedule，关于→system', (tester) async {
      await pumpPage(tester, const SettingsPage());
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(categoryOfRow(tester, '权限自检'),
          SettingsIconCategory.schedule);
      expect(categoryOfRow(tester, '关于小马课表'),
          SettingsIconCategory.system);
    });

    testWidgets('学期页：学期名称／开学日期／总周数均为 schedule', (tester) async {
      await pumpPage(tester, const SemesterSettingsPage());
      for (final title in ['学期名称', '开学日期', '总周数']) {
        expect(categoryOfRow(tester, title), SettingsIconCategory.schedule);
      }
    });

    testWidgets('提醒页：四行均为 reminder', (tester) async {
      await pumpPage(tester, const RemindersSettingsPage());
      for (final title in ['上课提醒', '上课播报', '今日课程常驻通知', '提前提醒']) {
        expect(categoryOfRow(tester, title), SettingsIconCategory.reminder);
      }
    });

    testWidgets('数据页：六行均为 data', (tester) async {
      await pumpPage(tester, const DataSettingsPage());
      for (final title in
          ['导入课表', '学期管理', '备份到文件', '从备份恢复', '导出课表（ICS）', '数据管理']) {
        expect(categoryOfRow(tester, title), SettingsIconCategory.data);
      }
    });

    testWidgets('小组件页：说明行 appearance，部件状态行 system', (tester) async {
      await pumpPage(tester, const WidgetSettingsPage());
      expect(categoryOfRow(tester, '今日课程小组件'),
          SettingsIconCategory.appearance);
      expect(categoryOfRow(tester, '立即刷新桌面小部件'),
          SettingsIconCategory.appearance);
      expect(categoryOfRow(tester, '部件状态'), SettingsIconCategory.system);
    });

    testWidgets('权限页：权限行为 schedule', (tester) async {
      await pumpPage(tester, const PermissionsSettingsPage());
      expect(categoryOfRow(tester, '权限'), SettingsIconCategory.schedule);
    });
  });
}
