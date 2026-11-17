import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/course_override.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';

/// WB_SPEC_242：编辑模式悬浮胶囊飘窗 + 选区框把手与拖动热区。
///
/// - 240 的常驻 26dp 横栏（EditModeBanner）已删，进编辑模式改挂悬浮
///   胶囊飘窗（EditModeToast），3 秒自动淡出，课表高度不再被顶矮。
/// - 选区框底部加 24×4dp 小把手（首次出现浮动 2 次）+ 28dp 透明拖动
///   热区 + 底部 1/3 全可拖，拇指按底部一带就能拖。
void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.8.0',
      buildNumber: '42',
      buildSignature: '',
    );
    // 锁周一时钟，避免周日跑测试时周日弹窗遮挡（与 home_shell_test 同款）。
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    sundayDialogNow = () => monday;
  });

  tearDown(() {
    sundayDialogNow = DateTime.now;
  });

  List<int> weeks(int from, int to) =>
      List.generate(to - from + 1, (i) => i + from);

  Course course({
    required String name,
    int day = 1,
    int start = 1,
    int end = 2,
  }) => Course(
    semesterId: 1,
    name: name,
    colorValue: 0xFF6B8E7B,
    dayOfWeek: day,
    startSection: start,
    endSection: end,
    weeks: weeks(1, 16),
  );

  Semester semester() => const Semester(
    name: '2026-2027-1',
    startDate: '2026-09-07',
    totalWeeks: 20,
    isCurrent: true,
  );

  /// 14 节标准节次（与 App 默认节次表同口径）。
  List<TimeSlot> slots14() => const [
    TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
    TimeSlot(section: 2, startTime: '08:55', endTime: '09:40'),
    TimeSlot(section: 3, startTime: '10:00', endTime: '10:45'),
    TimeSlot(section: 4, startTime: '10:55', endTime: '11:40'),
    TimeSlot(section: 5, startTime: '14:00', endTime: '14:45'),
    TimeSlot(section: 6, startTime: '14:55', endTime: '15:40'),
    TimeSlot(section: 7, startTime: '16:00', endTime: '16:45'),
    TimeSlot(section: 8, startTime: '16:55', endTime: '17:40'),
    TimeSlot(section: 9, startTime: '19:00', endTime: '19:45'),
    TimeSlot(section: 10, startTime: '19:55', endTime: '20:40'),
    TimeSlot(section: 11, startTime: '20:50', endTime: '21:35'),
    TimeSlot(section: 12, startTime: '21:45', endTime: '22:30'),
    TimeSlot(section: 13, startTime: '22:40', endTime: '23:25'),
    TimeSlot(section: 14, startTime: '23:35', endTime: '00:20'),
  ];

  List<Override> overrides(List<Course> list) => [
    currentSemesterProvider.overrideWith(
      () => _FakeSemesterNotifier(semester()),
    ),
    coursesProvider.overrideWith(() => _FakeCoursesNotifier(list)),
    courseOverridesProvider.overrideWith(() => _FakeOverridesNotifier()),
    timeSlotsProvider.overrideWith(() => _FakeSlotsNotifier(slots14())),
    uiSettingsProvider.overrideWith(
      () => _FakeUiNotifier(const UiSettings(autoFitHeight: false)),
    ),
    displayWeekProvider.overrideWith(() => _FixedWeek(6)),
    showOtherWeeksProvider.overrideWith(() => _FixedShowOther(false)),
    autoCollapseWeekendProvider.overrideWith(
      () => _FixedAutoCollapse(false),
    ),
    segmentSettingsProvider.overrideWith(
      () => _FakeSegmentNotifier(5, 9),
    ),
    bandSettingsProvider.overrideWith(() => _FakeBandNotifier()),
  ];

  Future<void> pumpWeekView(
    WidgetTester tester, {
    required List<Course> list,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: overrides(list),
              child: const MaterialApp(home: WeekViewPage()),
            ),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// 点右上角铅笔进编辑模式。
  Future<void> enterEditMode(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('edit_mode_entry_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('WB_SPEC_242 编辑模式飘窗', () {
    testWidgets('进编辑模式出现悬浮胶囊飘窗，不再出现常驻横栏', (tester) async {
      await pumpWeekView(tester, list: [course(name: '普通课程')]);
      // 未进编辑模式：无飘窗、无横栏。
      expect(find.byKey(const ValueKey<String>('edit_mode_toast')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('edit_mode_persistent_banner')),
        findsNothing,
      );
      // 点铅笔进编辑模式。
      await enterEditMode(tester);
      // 飘窗出现，文案为新版；常驻横栏仍无（已删）。
      expect(find.byKey(const ValueKey<String>('edit_mode_toast')), findsOneWidget);
      expect(find.text('点空格加课 · 长按课程编辑'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('edit_mode_persistent_banner')),
        findsNothing,
      );
      // 顶栏胶囊出现（呼吸动画不影响查找）。
      expect(find.byKey(const ValueKey<String>('appbar_edit_mode_pill')), findsOneWidget);
      // 「完成」按钮出现。
      expect(find.byKey(const ValueKey<String>('edit_mode_done_btn')), findsOneWidget);
      // 收尾：把飘窗的 3 秒定时器跑完再结束，否则 teardown 报 Timer pending。
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('飘窗 3 秒后自动淡出消失', (tester) async {
      await pumpWeekView(tester, list: [course(name: '普通课程')]);
      await enterEditMode(tester);
      expect(find.byKey(const ValueKey<String>('edit_mode_toast')), findsOneWidget);
      // 推 3.5 秒（停留 3 秒 + 淡出 250ms），飘窗应已卸载。
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey<String>('edit_mode_toast')), findsNothing);
      // 编辑模式本身还在（胶囊与完成按钮仍在）。
      expect(find.byKey(const ValueKey<String>('appbar_edit_mode_pill')), findsOneWidget);
    });

    testWidgets('点飘窗右侧 × 手动关闭飘窗', (tester) async {
      await pumpWeekView(tester, list: [course(name: '普通课程')]);
      await enterEditMode(tester);
      expect(find.byKey(const ValueKey<String>('edit_mode_toast')), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey<String>('edit_mode_toast')), findsNothing);
      // 收尾：把飘窗的 3 秒定时器跑完再结束，否则 teardown 报 Timer pending。
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('WB_SPEC_242 选区框把手与拖动热区', () {
    testWidgets('长按空白格出选区框，底部有把手', (tester) async {
      await pumpWeekView(tester, list: [course(name: '普通课程', day: 1, start: 1, end: 2)]);
      await enterEditMode(tester);
      // 先等飘窗自动消失，避免它挡住长按点。
      await tester.pump(const Duration(milliseconds: 3500));
      await tester.pump(const Duration(milliseconds: 300));
      // 长按周二第 3 节空白格起高亮：周二列约在屏幕横向 1/3 处，
      // 第 3 节行约在纵向 1/4 处（表头 + 2 节之后）。
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final gesture = await tester.startGesture(
        Offset(size.width * 0.35, size.height * 0.28),
      );
      // 长按阈值约 500ms，hold 住再松手。
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // 把手应出现。
      expect(
        find.byKey(const ValueKey<String>('selection_drag_handle')),
        findsOneWidget,
      );
    });
  });
}

/// 以下 Fake 与 wb240_cross_band_height_test.dart 同款（Provider 覆盖用）。
class _FakeSemesterNotifier extends CurrentSemesterNotifier {
  _FakeSemesterNotifier(this._semester);
  final Semester _semester;
  @override
  Future<Semester> build() async => _semester;
}

class _FakeCoursesNotifier extends CoursesNotifier {
  _FakeCoursesNotifier(this._list);
  final List<Course> _list;
  @override
  Future<List<Course>> build() async => _list;
}

class _FakeOverridesNotifier extends CourseOverridesNotifier {
  @override
  Future<List<CourseOverride>> build() async => const [];
}

class _FakeSlotsNotifier extends TimeSlotsNotifier {
  _FakeSlotsNotifier(this._slots);
  final List<TimeSlot> _slots;
  @override
  Future<List<TimeSlot>> build() async => _slots;
}

class _FakeUiNotifier extends UiSettingsNotifier {
  _FakeUiNotifier(this._ui);
  final UiSettings _ui;
  @override
  Future<UiSettings> build() async => _ui;
}

class _FixedWeek extends DisplayWeekNotifier {
  _FixedWeek(this._week);
  final int _week;
  @override
  int build() => _week;
}

class _FixedShowOther extends ShowOtherWeeksNotifier {
  _FixedShowOther(this._v);
  final bool _v;
  @override
  bool build() => _v;
}

class _FixedAutoCollapse extends AutoCollapseWeekendNotifier {
  _FixedAutoCollapse(this._v);
  final bool _v;
  @override
  bool build() => _v;
}

class _FakeSegmentNotifier extends SegmentSettingsNotifier {
  _FakeSegmentNotifier(this._lunchAfter, this._dinnerAfter);
  final int _lunchAfter;
  final int _dinnerAfter;
  @override
  Future<SegmentSettings> build() async => SegmentSettings(
    lunchAfterSection: _lunchAfter,
    dinnerAfterSection: _dinnerAfter,
  );
}

class _FakeBandNotifier extends BandSettingsNotifier {
  @override
  Future<BandSettings> build() async => const BandSettings();
}
