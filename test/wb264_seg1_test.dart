import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/services/backup_service.dart';
import 'package:xiaoma_timetable/services/fonts_service.dart';
import 'package:xiaoma_timetable/services/ongoing_notice_service.dart';
import 'package:xiaoma_timetable/utils/heuristic_parser.dart';
import 'package:xiaoma_timetable/utils/ics_export.dart';

import 'helpers/pump_helpers.dart';

/// WB_SPEC_264 第 1 段（§1 崩溃 / 数据错乱）回归测试
void main() {
  group('S1-2 启发式解析', () {
    test('第3-4节不被误识别为周次', () {
      final drafts = HeuristicParser.parse(['第3-4节', '高等数学']);
      expect(drafts.length, 1);
      // 旧实现会把 3-4 当成第 3~4 周；新实现要求区间后带「周」，默认 1~16 周
      expect(drafts.single.weeks.length, 16);
      // M1（DeepSeek 264 复审 B 段）：只断周次长度咬不住——解析器整行忽略时
      // 周次仍是默认 1~16；必须同时断言节次确实读成 3-4 节
      expect(drafts.single.startSection, 3);
      expect(drafts.single.endSection, 4);
    });

    test('1-16单周只保留单周', () {
      final drafts = HeuristicParser.parse(['1-16单周', '高等数学']);
      expect(drafts.single.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    });

    test('1-16周(双)只保留双周', () {
      final drafts = HeuristicParser.parse(['1-16周(双)', '高等数学']);
      expect(drafts.single.weeks, [2, 4, 6, 8, 10, 12, 14, 16]);
    });

    test('1,3,5周列表形式不变', () {
      final drafts = HeuristicParser.parse(['1,3,5周', '高等数学']);
      expect(drafts.single.weeks, [1, 3, 5]);
    });

    test('4-2节非法区间不落盘，沿用默认节次', () {
      final drafts = HeuristicParser.parse(['4-2节', '高等数学']);
      expect(drafts.single.startSection, 1);
      expect(drafts.single.endSection, 2);
    });

    test('教室不串到下一门无教室课程', () {
      final drafts = HeuristicParser.parse(['高等数学 16-222', '大学物理']);
      expect(drafts.length, 2);
      expect(drafts[0].classroom, '16-222');
      expect(drafts[1].classroom, isNull);
    });
  });

  group('S1-3 星期钳制', () {
    Course fromMapWithDay(int day) => Course.fromMap({
          'id': 1,
          'semesterId': 1,
          'name': '高等数学',
          'colorValue': 0xFF6B8E7B,
          'dayOfWeek': day,
          'startSection': 1,
          'endSection': 2,
          'weeksJson': '[1,2,3]',
        });

    test('dayOfWeek 0 钳到 1，9 钳到 7', () {
      expect(fromMapWithDay(0).dayOfWeek, 1);
      expect(fromMapWithDay(9).dayOfWeek, 7);
      expect(fromMapWithDay(3).dayOfWeek, 3);
    });

    test('ICS 导出跳过非法星期课程并计入 skippedCount', () {
      const semester = Semester(
          id: 1, name: '2026 秋季学期', startDate: '2026-09-07', totalWeeks: 20);
      const slots = [
        TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
        TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
      ];
      final bad = Course(
        id: 7,
        semesterId: 1,
        name: '脏数据课',
        colorValue: 0xFF6B8E7B,
        dayOfWeek: 0,
        startSection: 1,
        endSection: 2,
        weeks: const [1],
      );
      final r = IcsExporter.build(
        semester: semester,
        courses: [bad],
        slots: slots,
        now: DateTime(2026, 10, 15, 12, 30),
      );
      expect(r.eventCount, 0);
      expect(r.skippedCount, 1);
    });
  });

  test('S1-5 importFont 拒绝非 ttf/otf，不写磁盘也不写注册表', () async {
    final f = File('${Directory.systemTemp.path}/wb264_test_font.txt');
    await f.writeAsString('not a font');
    // M10（DeepSeek 264 复审 B 段）：只断异常类型咬不住——必须断言中文提示，
    // 且扩展名校验在一切 IO 之前（见 importFont :116-118），抛错即保证不写盘/不写注册表
    await expectLater(
      () => FontsService.importFont(f, '假字体'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('仅支持导入 .ttf 或 .otf'),
        ),
      ),
    );
    await f.delete();
  });

  group('S1-1 备份导出 FilePicker 通道', () {
    // M9（DeepSeek 264 复审 B 段）：S1-1 的修复是 FilePicker.saveFile 静态方法
    // 转调 platform instance；假 platform 覆盖 saveFile，断言 BackupService
    // 按 URI 方案返回（content:// 原样、file:// 转路径、null 透传取消）。
    late FilePickerPlatform savedInstance;

    setUp(() {
      savedInstance = FilePickerPlatform.instance;
    });

    tearDown(() {
      FilePickerPlatform.instance = savedInstance;
    });

    test('content:// URI 原样返回', () async {
      FilePickerPlatform.instance = _FakeFilePicker(
        Uri.parse('content://com.example/tree/backup.txt'),
      );
      final result = await BackupService.instance.saveTextFile(
        fileName: 'backup.txt',
        content: '{}',
        extension: 'txt',
      );
      expect(result, 'content://com.example/tree/backup.txt');
    });

    test('file:// URI 转成本地路径', () async {
      FilePickerPlatform.instance = _FakeFilePicker(
        Uri.parse('file:///storage/backup.txt'),
      );
      final result = await BackupService.instance.saveTextFile(
        fileName: 'backup.txt',
        content: '{}',
        extension: 'txt',
      );
      expect(result, '/storage/backup.txt');
    });

    test('用户取消返回 null', () async {
      FilePickerPlatform.instance = _FakeFilePicker(null);
      final result = await BackupService.instance.saveTextFile(
        fileName: 'backup.txt',
        content: '{}',
        extension: 'txt',
      );
      expect(result, isNull);
    });
  });

  group('C5/C7 提醒联动（ProviderContainer + 内存库）', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    late Database db;
    late ProviderContainer container;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(db);
      container = ProviderContainer();
      // 预热：让 notifier 的 build 完成，避免首个 await 触发异步初始化
      await container.read(timeSlotsProvider.future);
      await container.read(reminderSettingsProvider.future);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('C5 默认 13 节时 addSection 新增第 14 节（21:20–22:00）', () async {
      final notifier = container.read(timeSlotsProvider.notifier);
      await notifier.addSection();
      final slots = container.read(timeSlotsProvider).value!;
      expect(slots.length, 14);
      expect(slots.last.section, 14);
      expect(slots.last.startTime, '21:20');
      expect(slots.last.endTime, '22:00');
    });

    test('C5 第 13 节改 23:50 后 addSection 不再新增', () async {
      final notifier = container.read(timeSlotsProvider.notifier);
      final slots = container.read(timeSlotsProvider).value!;
      await notifier.updateSlot(
        TimeSlot(
          section: 13,
          startTime: slots[12].startTime,
          endTime: '23:50',
        ),
      );
      await notifier.addSection();
      final after = container.read(timeSlotsProvider).value!;
      // 23:50 + 10 分钟 = 24:00，已到当天上限 23:59，不新增
      expect(after.length, 13);
    });

    test('C7/C8 setEnabled 与 addSection 都会触发常驻通知刷新', () async {
      // 链路是 fire-and-forget（_notifyDataChanged 不 await），轮询等计数涨
      Future<void> waitForRefresh(int before) async {
        for (var i = 0; i < 40; i++) {
          if (OngoingNoticeService.debugRefreshCalls > before) return;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail(
          'OngoingNoticeService.refresh 未在 2 秒内被触发'
          '（计数仍为 $before）',
        );
      }

      var before = OngoingNoticeService.debugRefreshCalls;
      await container.read(reminderSettingsProvider.notifier).setEnabled(true);
      await waitForRefresh(before);

      before = OngoingNoticeService.debugRefreshCalls;
      await container.read(timeSlotsProvider.notifier).addSection();
      await waitForRefresh(before);
    });
  });

  group('C4 草稿课长按菜单无调课/删除', () {
    TestWidgetsFlutterBinding.ensureInitialized();

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
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) => DbHelper.instance.createSchema(d),
        ),
      );
      DbHelper.instance.useDatabaseForTest(db);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('id 为空的草稿课长按只剩编辑课程', (tester) async {
      // M9（DeepSeek 264 复审 B 段）：C4 的修复是删除项与调课项共用
      // canOverride（course.id != null）；草稿课 id 为空，两项都不应出现。
      // 若这条太折腾就记录跳过理由——目前用 provider override 直接喂草稿课。
      // 注意：非编辑模式长按无反应（防误触），须先点铅笔进编辑模式再长按。
      final container = ProviderContainer(
        overrides: [
          coursesProvider.overrideWith(_FixedDraftCourses.new),
          displayWeekProvider.overrideWith(_FixedWeekOne.new),
        ],
      );
      addTearDown(container.dispose);
      await pumpHomeShell(tester, container: container);

      await tester.tap(find.byKey(const ValueKey<String>('edit_mode_entry_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.longPress(find.text('草稿课'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('删除'), findsNothing);
      expect(find.text('调整本次'), findsNothing);
      expect(find.text('编辑课程'), findsOneWidget);
      await finishHomeShell(tester);
    });
  });
}

/// S1-1 假 FilePicker：只覆盖 saveFile，其余方法保持未实现。
class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePickerPlatform {
  _FakeFilePicker(this.uri);

  final Uri? uri;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      uri;
}

/// C4：coursesProvider 只返回一门 id 为空的草稿课（周一 1-2 节，第 1 周）。
class _FixedDraftCourses extends CoursesNotifier {
  @override
  Future<List<Course>> build() async => const [
        Course(
          semesterId: 1,
          name: '草稿课',
          colorValue: 0xFF6B8E7B,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          weeks: [1],
        ),
      ];
}

/// C4：浏览周次固定第 1 周（草稿课只在第 1 周活跃）。
class _FixedWeekOne extends DisplayWeekNotifier {
  @override
  int build() => 1;
}

