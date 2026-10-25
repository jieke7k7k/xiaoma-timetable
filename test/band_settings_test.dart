import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';

/// 休息时段设置测试（WB_SPEC_209 第 6 节）
///
/// 覆盖：
/// 1. [BandSettings] 默认值（午休/晚间默认显示，起止 12:00–14:00 / 17:10–18:00）；
/// 2. 纯函数 [computeActiveBands]：默认两条、显隐过滤、越界过滤、interval 用自定义时间；
/// 3. 纯函数 [bandTimeToMinutes] / [bandRangeValid]：开始早于结束合法；
/// 4. [BandSettingsNotifier] 持久化（跑 sqflite_common_ffi 内存库）：默认值、
///    开关落库、开始晚于结束不保存、合法起止落库。
void main() {
  group('BandSettings 默认值与纯函数', () {
    test('默认值：两条都显示，起止时间与旧版观感一致', () {
      const band = BandSettings();
      expect(band.lunchVisible, isTrue);
      expect(band.dinnerVisible, isTrue);
      expect(band.lunchStart, '12:00');
      expect(band.lunchEnd, '14:00');
      expect(band.dinnerStart, '17:10');
      expect(band.dinnerEnd, '18:00');
    });

    test('computeActiveBands：默认两条，interval 用自定义时间', () {
      const settings = BandSettings();
      final bands = computeActiveBands(
        lunchAfter: 5,
        dinnerAfter: 9,
        sectionCount: 13,
        settings: settings,
      );
      expect(bands.length, 2);
      expect(bands[0].label, '午休');
      expect(bands[0].after, 5);
      expect(bands[0].interval, '12:00–14:00');
      expect(bands[1].label, '晚间');
      expect(bands[1].after, 9);
      expect(bands[1].interval, '17:10–18:00');
    });

    test('computeActiveBands：关闭的带子被过滤，不再占位', () {
      const settings = BandSettings(lunchVisible: false);
      final bands = computeActiveBands(
        lunchAfter: 5,
        dinnerAfter: 9,
        sectionCount: 13,
        settings: settings,
      );
      expect(bands.length, 1);
      expect(bands.single.label, '晚间');
    });

    test('computeActiveBands：两条都关时为空列表', () {
      const settings = BandSettings(lunchVisible: false, dinnerVisible: false);
      final bands = computeActiveBands(
        lunchAfter: 5,
        dinnerAfter: 9,
        sectionCount: 13,
        settings: settings,
      );
      expect(bands, isEmpty);
    });

    test('computeActiveBands：after 超出总节数被过滤（与旧版口径一致）', () {
      const settings = BandSettings();
      final bands = computeActiveBands(
        lunchAfter: 5,
        dinnerAfter: 13,
        sectionCount: 13,
        settings: settings,
      );
      // 晚间分段点 13 >= 总节数 13，不生效；午休仍生效
      expect(bands.length, 1);
      expect(bands.single.label, '午休');
    });

    test('bandRangeValid / bandTimeToMinutes：开始早于结束才算合法', () {
      expect(bandTimeToMinutes('08:30'), 510);
      expect(bandTimeToMinutes('25:00'), isNull);
      expect(bandTimeToMinutes('bad'), isNull);
      expect(bandRangeValid('12:00', '14:00'), isTrue);
      expect(bandRangeValid('14:00', '12:00'), isFalse);
      expect(bandRangeValid('12:00', '12:00'), isFalse);
      expect(bandRangeValid('', '14:00'), isFalse);
    });
  });

  group('BandSettingsNotifier 持久化（FFI 内存库）', () {
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

    test('默认值：读自空库回退全默认', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final band = await container.read(bandSettingsProvider.future);
      expect(band.lunchVisible, isTrue);
      expect(band.dinnerVisible, isTrue);
      expect(band.lunchStart, '12:00');
      expect(band.lunchEnd, '14:00');
      expect(band.dinnerStart, '17:10');
      expect(band.dinnerEnd, '18:00');
    });

    test('开关持久化：关闭午休写入 app_settings 并更新状态', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(bandSettingsProvider.notifier);
      await container.read(bandSettingsProvider.future);

      await notifier.setLunchVisible(false);
      expect(await Dao.instance.getSetting('band_lunch_visible'), '0');
      expect(container.read(bandSettingsProvider).value!.lunchVisible, isFalse);
      // 只动午休，晚间仍默认显示
      expect(container.read(bandSettingsProvider).value!.dinnerVisible, isTrue);
    });

    test('开始晚于结束不保存', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(bandSettingsProvider.notifier);
      await container.read(bandSettingsProvider.future);

      final ok = await notifier.setLunchTime('14:00', '12:00');
      expect(ok, isFalse);
      // 数据库未被写入，状态保持默认
      expect(await Dao.instance.getSetting('band_lunch_start'), isNull);
      expect(await Dao.instance.getSetting('band_lunch_end'), isNull);
      expect(container.read(bandSettingsProvider).value!.lunchStart, '12:00');
      expect(container.read(bandSettingsProvider).value!.lunchEnd, '14:00');
    });

    test('开始早于结束保存并更新状态', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(bandSettingsProvider.notifier);
      await container.read(bandSettingsProvider.future);

      final ok = await notifier.setLunchTime('11:00', '13:00');
      expect(ok, isTrue);
      expect(await Dao.instance.getSetting('band_lunch_start'), '11:00');
      expect(await Dao.instance.getSetting('band_lunch_end'), '13:00');
      expect(container.read(bandSettingsProvider).value!.lunchStart, '11:00');
      expect(container.read(bandSettingsProvider).value!.lunchEnd, '13:00');
    });
  });
}
