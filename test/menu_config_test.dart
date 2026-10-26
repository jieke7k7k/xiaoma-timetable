import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/menu_config.dart';
import 'package:xiaoma_timetable/providers/providers.dart';

/// 菜单配置测试（WB_SPEC_212 第 2 / 4 节）
///
/// 覆盖：
/// 1. [MenuConfig.defaults]：六项全显示、顺序与第 4 节定版一致；
/// 2. 纯函数 [visibleMenuItems]：默认六项 + 设置殿后；六项全关仍恒含设置；
/// 3. 纯函数 [MenuConfig.reorder]：拖拽排序语义、order 重新连续赋值；
/// 4. [MenuConfig.fromEncoded]：损坏/空/缺项兜底；
/// 5. [MenuConfigNotifier] 持久化（FFI 内存库）：默认值、开关落库、
///    拖拽排序重进 App 仍一致、恢复默认。
void main() {
  group('MenuConfig 默认值与纯函数', () {
    test('默认配置：六项全显示，顺序与第 4 节定版一致', () {
      final cfg = MenuConfig.defaults();
      expect(cfg.items.length, 6);
      expect(cfg.items.every((e) => e.visible), isTrue);
      expect(
        cfg.items.map((e) => e.id).toList(),
        [
          'course-search',
          'free-time',
          'share-image',
          'semester-manage',
          'exam-countdown',
          'import',
        ],
      );
      expect(cfg.items.map((e) => e.order).toList(), [0, 1, 2, 3, 4, 5]);
    });

    test('visibleMenuItems：默认返回六项 + 固定设置殿后', () {
      final items = visibleMenuItems(MenuConfig.defaults());
      expect(items.length, 7);
      expect(items.first.id, 'course-search');
      expect(items.last.id, 'settings');
      expect(items.last.title, '设置');
    });

    test('visibleMenuItems：六项全关仍恒含设置（无设置入口死局）', () {
      var cfg = MenuConfig.defaults();
      for (final e in cfg.items) {
        cfg = cfg.copyWithVisible(e.id, false);
      }
      final items = visibleMenuItems(cfg);
      expect(items.length, 1);
      expect(items.single.id, 'settings');
    });

    test('copyWithVisible：只改目标项，其余项不变', () {
      final cfg = MenuConfig.defaults().copyWithVisible('free-time', false);
      expect(cfg.byId('free-time').visible, isFalse);
      expect(cfg.byId('course-search').visible, isTrue);
      expect(cfg.byId('import').visible, isTrue);
    });

    test('reorder：按 ReorderableListView 回调语义移动并重新连续赋值 order', () {
      // 把最后一项（import）拖到最前：oldIndex 5 -> newIndex 0
      final cfg = MenuConfig.defaults().reorder(5, 0);
      expect(
        cfg.items.map((e) => e.id).toList(),
        [
          'import',
          'course-search',
          'free-time',
          'share-image',
          'semester-manage',
          'exam-countdown',
        ],
      );
      expect(cfg.items.map((e) => e.order).toList(), [0, 1, 2, 3, 4, 5]);
    });

    test('encode → fromEncoded 往返一致', () {
      final cfg = MenuConfig.defaults()
          .copyWithVisible('import', false)
          .reorder(5, 0);
      final restored = MenuConfig.fromEncoded(cfg.encode());
      expect(
        restored.items.map((e) => e.id).toList(),
        cfg.items.map((e) => e.id).toList(),
      );
      expect(
        restored.items.map((e) => e.visible).toList(),
        cfg.items.map((e) => e.visible).toList(),
      );
    });

    test('fromEncoded：null/空/损坏回退全默认，缺项补齐', () {
      expect(MenuConfig.fromEncoded(null).items.length, 6);
      expect(MenuConfig.fromEncoded('').items.length, 6);
      expect(MenuConfig.fromEncoded('not json').items.length, 6);
      expect(MenuConfig.fromEncoded('[]').items.length, 6);
      expect(MenuConfig.fromEncoded('{"a":1}').items.length, 6);
      // 只给一项：该项按存储值，其余回默认
      final partial = MenuConfig.fromEncoded(
        '[{"id":"course-search","visible":false,"order":0}]',
      );
      expect(partial.byId('course-search').visible, isFalse);
      expect(partial.byId('free-time').visible, isTrue);
    });
  });

  group('MenuConfigNotifier 持久化（FFI 内存库）', () {
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

    test('默认值：空库回退全显示默认顺序', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final cfg = await container.read(menuConfigProvider.future);
      expect(cfg.items.length, 6);
      expect(cfg.items.every((e) => e.visible), isTrue);
      expect(cfg.items.first.id, 'course-search');
    });

    test('setVisible 落库并更新状态', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(menuConfigProvider.notifier);
      await container.read(menuConfigProvider.future);

      await notifier.setVisible('free-time', false);
      expect(await Dao.instance.getSetting('home_menu_config'), isNotNull);
      expect(
        container.read(menuConfigProvider).value!.byId('free-time').visible,
        isFalse,
      );
    });

    test('reorder 持久化且重进 App（重建 provider）仍一致', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(menuConfigProvider.notifier);
      await container.read(menuConfigProvider.future);
      await notifier.reorder(5, 0);

      // 模拟重进 App：新建容器重新读库
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final cfg2 = await container2.read(menuConfigProvider.future);
      expect(
        cfg2.items.map((e) => e.id).toList(),
        container.read(menuConfigProvider).value!.items.map((e) => e.id).toList(),
      );
    });

    test('reset 恢复默认（全显示 + 定版顺序）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(menuConfigProvider.notifier);
      await container.read(menuConfigProvider.future);
      await notifier.setVisible('free-time', false);
      await notifier.reorder(5, 0);
      await notifier.reset();

      final cfg = container.read(menuConfigProvider).value!;
      expect(cfg.items.every((e) => e.visible), isTrue);
      expect(cfg.items.first.id, 'course-search');
      expect(cfg.items.last.id, 'import');
    });

    test('并发写串行化：同时开关 + 排序，两项改动都不丢（2.1.0 返修 P1）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(menuConfigProvider.notifier);
      await container.read(menuConfigProvider.future);

      await Future.wait([
        notifier.setVisible('free-time', false),
        notifier.reorder(5, 0),
      ]);

      final cfg = container.read(menuConfigProvider).value!;
      expect(cfg.byId('free-time').visible, isFalse);
      expect(cfg.items.first.id, 'import');
      // 落库与内存一致
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      final cfg2 = await container2.read(menuConfigProvider.future);
      expect(cfg2.byId('free-time').visible, isFalse);
      expect(cfg2.items.first.id, 'import');
    });

    test('加载未完成时操作：先读已存配置再写，不拿默认值覆盖（2.1.0 返修 P1）',
        () async {
      // 先存一份非默认配置
      await Dao.instance.setSetting(
        'home_menu_config',
        MenuConfig.defaults().copyWithVisible('free-time', false).encode(),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(menuConfigProvider.notifier);
      // 故意不等 future：操作应在内部等加载完成后再基于已存配置改
      await notifier.setVisible('import', false);

      final cfg = container.read(menuConfigProvider).value!;
      expect(cfg.byId('free-time').visible, isFalse);
      expect(cfg.byId('import').visible, isFalse);
    });
  });
}
