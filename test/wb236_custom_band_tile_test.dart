import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/dao.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/pages/time_settings_page.dart';
import 'package:xiaoma_timetable/ui/settings_line_frame.dart';
import 'package:xiaoma_timetable/utils/app_haptics.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';

import 'helpers/pump_helpers.dart';

/// WB_SPEC_236 §4：_BandTile 自画段头验收（弃 ExpansionTile 后）。
///
/// 覆盖：无灰块、分隔线、箭头、点按切换、初始展开跟传入值、select 震动、
/// 动画中途从上往下（80ms 取帧，第 6 节顶边贴着段头底边）、落定后下午四行
/// 完整在框内（每行 56dp）、§6 新文案与 360dp 不溢出。
/// §7/§8 的整页用例在 test/week_jumper_outside_tap_test.dart（复用
/// 那里的整页 pump），不在这里重复。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  var fakeNow = DateTime(2026, 11, 16, 21);
  final hapticCalls = <String>[];

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.5.0',
      buildNumber: '39',
      buildSignature: '',
    );
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    sundayDialogNow = () => monday;
    String two(int v) => v.toString().padLeft(2, '0');
    final start = '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    // T3：createSchema 已种入默认学期（isCurrent=1），先清空再插入测试学期
    await db.delete('semesters');
    await Dao.instance.insertSemester(
      Semester(name: '测试学期', startDate: start, isCurrent: true),
    );
    // T10：默认锁定上午 09:00，避免测试在 12:00 / 18:00 整点分界跨分钟抖动
    timeSettingsNow = () => DateTime(2026, 11, 16, 9, 0);
    // 235 同款：假时钟 + 平台震动捕获，避免 45ms 节流让计数不稳
    fakeNow = DateTime(2026, 11, 16, 21);
    hapticCalls.clear();
    AppHaptics.resetForTest();
    AppHaptics.clock = () => fakeNow;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        hapticCalls.add(call.arguments as String);
      }
      return null;
    });
  });

  tearDown(() async {
    sundayDialogNow = DateTime.now;
    timeSettingsNow = DateTime.now;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppHaptics.resetForTest();
    await db.close();
  });

  /// 360dp 宽 pump（物理 1080×2400 @3.0），与 §6 溢出断言同口径。
  /// 与其它 FFI widget 测试同款：runAsync 真实等待 500ms 再补泵，
  /// 光 pumpAndSettle 等不到跨 isolate 的 provider 首帧（会停在空 slots）。
  Future<void> pumpTimePage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TimeSettingsPage(),
        ),
      ),
    );
    await pumpUntil(tester, find.text('共 13 节 · 上5 下4 晚4'));
  }

  Finder bandHeader(String name) => find.descendant(
        of: find.byKey(Key('time_band_$name')),
        matching: find.byType(GestureDetector),
      ).first;

  Future<void> tapBandHeader(WidgetTester tester, String name) async {
    fakeNow = fakeNow.add(const Duration(milliseconds: 100));
    await tester.tap(bandHeader(name));
  }

  testWidgets('_BandTile：无灰块、分隔线、箭头、切换与震动', (tester) async {
    await pumpTimePage(tester);
    final expected = currentTimeBand(timeSettingsNow());

    // 初始展开跟传入值：只有当前时段的子项在树里
    const firstSections = {'morning': 1, 'afternoon': 6, 'evening': 10};
    for (final band in TimeBand.values) {
      expect(
        find.text('第 ${firstSections[band.name]} 节'),
        band == expected ? findsOneWidget : findsNothing,
        reason: '只有当前时段 $expected 默认展开',
      );
    }

    // 无灰块：三个段头的子树里 ListTile / InkWell 均为零
    for (final band in TimeBand.values) {
      final header = bandHeader(band.name);
      expect(
        find.descendant(of: header, matching: find.byType(ListTile)),
        findsNothing,
      );
      expect(
        find.descendant(of: header, matching: find.byType(InkWell)),
        findsNothing,
      );
    }

    // 先确保下午段收起（与当前时段无关，状态确定后再断言）
    if (find.text('第 6 节').evaluate().isNotEmpty) {
      await tapBandHeader(tester, 'afternoon');
      await tester.pumpAndSettle();
    }
    expect(find.text('第 6 节'), findsNothing);
    hapticCalls.clear();

    // 收起时：无 Divider、箭头 turns 0.0
    expect(
      find.descendant(
        of: find.byKey(const Key('time_band_afternoon')),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(const Key('time_band_afternoon')),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.0,
    );

    // 点段头展开
    await tapBandHeader(tester, 'afternoon');

    // 动画中途（80ms/160ms）取帧：第 6 节顶边贴着段头底边
    // （框顶 + 52dp 段头 + 1dp 分隔线 = +53，卷帘门式从上往下；
    // 若 AnimatedSize alignment 回到 center，这里会移到框顶 +38 附近而变红）
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      hapticCalls,
      ['HapticFeedbackType.selectionClick'],
      reason: '点段头触发一次 select 震动',
    );
    final frameRect = tester.getRect(
      find.ancestor(
        of: find.byKey(const Key('time_band_afternoon')),
        matching: find.byType(SettingsLineFrame),
      ),
    );
    // 量行顶（56dp SizedBox），不是文字顶——文字在行内垂直居中，比行顶低约 19px
    final section6RowTop = tester
        .getTopLeft(
          find.ancestor(
            of: find.text('第 6 节'),
            matching: find.byType(SizedBox),
          ).first,
        )
        .dy;
    expect(
      section6RowTop,
      closeTo(frameRect.top + 53, 2.0),
      reason: '动画中途第 6 节顶边在框内，不许再出现顶部裁切',
    );

    await tester.pumpAndSettle();

    // 落定后：下午四行完整在框内，每行 56dp
    // （框矩形重取：80ms 中途量的框底还是动画中的高度，落定后框更高）
    final settledFrameRect = tester.getRect(
      find.ancestor(
        of: find.byKey(const Key('time_band_afternoon')),
        matching: find.byType(SettingsLineFrame),
      ),
    );
    for (var section = 6; section <= 9; section++) {
      final row = find.ancestor(
        of: find.text('第 $section 节'),
        matching: find.byType(SizedBox),
      ).first;
      final rowRect = tester.getRect(row);
      expect(tester.getSize(row).height, 56);
      expect(rowRect.top, greaterThanOrEqualTo(settledFrameRect.top));
      expect(rowRect.bottom, lessThanOrEqualTo(settledFrameRect.bottom));
    }

    // 展开后：1 条 Divider、箭头 turns 0.5
    expect(
      find.descendant(
        of: find.byKey(const Key('time_band_afternoon')),
        matching: find.byType(Divider),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(const Key('time_band_afternoon')),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.5,
    );

    // 再点收起：箭头回 0.0、分隔线消失、子项出树
    await tapBandHeader(tester, 'afternoon');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedRotation>(
            find.descendant(
              of: find.byKey(const Key('time_band_afternoon')),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0.0,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('time_band_afternoon')),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    expect(find.text('第 6 节'), findsNothing);
  });

  group('T10：早/午/晚三个固定时刻各自默认仅展开对应时段', () {
    final samples = <({String label, DateTime clock, TimeBand band})>[
      (label: '上午 09:00', clock: DateTime(2026, 11, 16, 9, 0), band: TimeBand.morning),
      (label: '下午 14:00', clock: DateTime(2026, 11, 16, 14, 0), band: TimeBand.afternoon),
      (label: '晚上 20:00', clock: DateTime(2026, 11, 16, 20, 0), band: TimeBand.evening),
    ];
    const firstSections = {'morning': 1, 'afternoon': 6, 'evening': 10};

    for (final s in samples) {
      testWidgets('${s.label} → 仅展开 ${s.band.name}', (tester) async {
        timeSettingsNow = () => s.clock;
        await pumpTimePage(tester);
        for (final band in TimeBand.values) {
          expect(
            find.text('第 ${firstSections[band.name]} 节'),
            band == s.band ? findsOneWidget : findsNothing,
            reason: '${s.label} 时应仅展开 ${s.band.name}',
          );
        }
      });
    }
  });

  testWidgets('§6 作息页新文案与 360dp 不溢出', (tester) async {
    await pumpTimePage(tester);

    expect(find.text('节数与快捷设置'), findsOneWidget);
    expect(find.text('每日节数与分段'), findsOneWidget);
    expect(find.text('套用作息模板'), findsOneWidget);
    expect(find.text('上下课时间（点击时间可修改）'), findsOneWidget);
    // 默认 13 节：上 5 下 4 晚 4
    expect(find.text('共 13 节 · 上5 下4 晚4'), findsOneWidget);
    final valueRect = tester.getRect(find.text('共 13 节 · 上5 下4 晚4'));
    expect(valueRect.right, lessThanOrEqualTo(360));
  });
}
