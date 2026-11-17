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
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';
import 'package:xiaoma_timetable/utils/sunday_dialog.dart';
import 'package:xiaoma_timetable/widgets/course_card.dart';

/// P1-3 同类 bug：周视图与本周导出图里跨带课程卡高漏算分隔带。
///
/// - 周视图 `_PositionedCourseCard`：`height: slot.span * rowHeight`
/// - 本周导出图 `_slotWidget`：`height: slot.span * rowH - 3`
///
/// 午间带在第 5 节后、晚间带在第 9 节后（默认分段点 5 / 9），带高 24dp：
/// 5–6 节或 9–10 节的课跨过一条带子，旧公式算出的卡片短 24dp，
/// 卡底留空、与下一节错位。修法与 P1-3 同款：
/// `topOf(endSection + 1) - topOf(startSection) - 间隙`。
void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '小马课表',
      packageName: 'com.example.simple_timetable',
      version: '2.6.0',
      buildNumber: '40',
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

  /// 三门 2 节课：不跨带（1–2）作对照、跨午间带（5–6）、跨晚间带（9–10）。
  List<Course> courses() => [
    course(name: '普通课程', day: 1, start: 1, end: 2),
    course(name: '跨带课程', day: 1, start: 5, end: 6),
    course(name: '晚间跨带课程', day: 2, start: 9, end: 10),
  ];

  List<Override> overrides(List<Course> list) => [
    currentSemesterProvider.overrideWith(
      () => _FakeSemesterNotifier(semester()),
    ),
    coursesProvider.overrideWith(() => _FakeCoursesNotifier(list)),
    courseOverridesProvider.overrideWith(() => _FakeOverridesNotifier()),
    timeSlotsProvider.overrideWith(() => _FakeSlotsNotifier(slots14())),
    uiSettingsProvider.overrideWith(
      // 行高定死 46（autoFitHeight 关掉，不随视口高均分），
      // 否则期望高度要跟着视口算，断言不稳定。
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

  /// 某门课在树里所有卡片的渲染高度（周视图 PageView 邻页也会建卡，
  /// 有几份就断言几份，全部都要对）。
  List<double> cardHeights(String courseName) {
    final elements = find
        .byWidgetPredicate(
          (w) => w is CourseCard && w.course.name == courseName,
        )
        .evaluate()
        .toList();
    return [
      for (final el in elements) (el.renderObject as RenderBox).size.height,
    ];
  }

  /// 2 节卡期望高：行高 46、带高 24、上下留白各 1.5（共 3）。
  /// - 不跨带：2×46 − 3 = 89
  /// - 跨一条带：2×46 + 24 − 3 = 113
  const double plainCardHeight = 2 * 46 - 3;
  const double crossBandCardHeight = 2 * 46 + kBandHeight - 3;

  Future<void> pumpUntilCards(
    WidgetTester tester, {
    required Widget home,
    required List<Course> list,
    required Size physicalSize,
    required double pixelRatio,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await HttpOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: overrides(list),
              child: MaterialApp(home: home),
            ),
          );
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        },
        createHttpClient: (_) => throw const SocketException('测试环境阻断网络'),
      );
    });
    // 先推几帧，让 async notifier 的首值落定：首帧 provider 还在 loading，
    // `uiSettingsProvider.value ?? const UiSettings()` 会回退到默认
    // UiSettings（autoFitHeight=true），行高按视口均分——落定重建后才按
    // 测试给的 autoFitHeight:false / cellHeight:46 走。直接在首帧量
    // 会量到均分后的行高（实测 43.71），不是 bug。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 25; i++) {
      if (find.byType(CourseCard).evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// 周视图收尾：先把树换掉触发 dispose（30 秒状态条周期表在 dispose 里
  /// 取消），再把延时任务推完，避免 teardown 报「A Timer is still pending」
  ///（与 wb237 的 finish 同款）。
  Future<void> finishWeekView(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 11));
  }

  group('周视图跨带课程卡高', () {
    testWidgets('5–6 节跨午间带：卡高含 24dp 带高；1–2 节对照不变', (
      tester,
    ) async {
      await pumpUntilCards(
        tester,
        home: const WeekViewPage(),
        list: courses(),
        physicalSize: const Size(1170, 2532),
        pixelRatio: 3.0,
      );
      final cross = cardHeights('跨带课程');
      expect(cross, isNotEmpty);
      for (final h in cross) {
        expect(h, crossBandCardHeight);
      }
      final plain = cardHeights('普通课程');
      expect(plain, isNotEmpty);
      for (final h in plain) {
        expect(h, plainCardHeight);
      }
      // 跨带卡正好比同跨度不跨带卡高一条带子
      expect(
        cross.first - plain.first,
        kBandHeight,
      );
      await finishWeekView(tester);
    });

    testWidgets('9–10 节跨晚间带：卡高同样含 24dp 带高', (tester) async {
      await pumpUntilCards(
        tester,
        home: const WeekViewPage(),
        list: courses(),
        physicalSize: const Size(1170, 2532),
        pixelRatio: 3.0,
      );
      final evening = cardHeights('晚间跨带课程');
      expect(evening, isNotEmpty);
      for (final h in evening) {
        expect(h, crossBandCardHeight);
      }
      await finishWeekView(tester);
    });
  });

  group('本周导出图跨带课程卡高', () {
    testWidgets('5–6 节跨午间带：卡高含 24dp 带高；1–2 节对照不变', (
      tester,
    ) async {
      await pumpUntilCards(
        tester,
        home: const ShareImagePage(),
        list: courses(),
        physicalSize: const Size(1200, 6000),
        pixelRatio: 1.0,
      );
      final cross = cardHeights('跨带课程');
      expect(cross, [crossBandCardHeight]);
      final plain = cardHeights('普通课程');
      expect(plain, [plainCardHeight]);
      expect(cross.first - plain.first, kBandHeight);
    });

    testWidgets('9–10 节跨晚间带：卡高同样含 24dp 带高', (tester) async {
      await pumpUntilCards(
        tester,
        home: const ShareImagePage(),
        list: courses(),
        physicalSize: const Size(1200, 6000),
        pixelRatio: 1.0,
      );
      expect(cardHeights('晚间跨带课程'), [crossBandCardHeight]);
    });
  });
}

// ---------------------------------------------------------------------------
// 假 notifier（沿用 wb237 的模式：build 直接返回固定值）
// ---------------------------------------------------------------------------

class _FakeUiNotifier extends UiSettingsNotifier {
  _FakeUiNotifier(this.value);

  UiSettings value;

  @override
  Future<UiSettings> build() async => value;
}

class _FakeCoursesNotifier extends CoursesNotifier {
  _FakeCoursesNotifier(this.courses);

  final List<Course> courses;

  @override
  Future<List<Course>> build() async => courses;
}

class _FakeSemesterNotifier extends CurrentSemesterNotifier {
  _FakeSemesterNotifier(this.semester);

  final Semester semester;

  @override
  Future<Semester> build() async => semester;
}

class _FakeOverridesNotifier extends CourseOverridesNotifier {
  @override
  Future<List<CourseOverride>> build() async => const [];
}

class _FakeSlotsNotifier extends TimeSlotsNotifier {
  _FakeSlotsNotifier(this.slots);

  final List<TimeSlot> slots;

  @override
  Future<List<TimeSlot>> build() async => slots;
}

class _FakeSegmentNotifier extends SegmentSettingsNotifier {
  _FakeSegmentNotifier(this.lunch, this.dinner);

  final int lunch;
  final int dinner;

  @override
  Future<SegmentSettings> build() async =>
      SegmentSettings(lunchAfterSection: lunch, dinnerAfterSection: dinner);
}

class _FakeBandNotifier extends BandSettingsNotifier {
  @override
  Future<BandSettings> build() async => const BandSettings();
}

class _FixedWeek extends DisplayWeekNotifier {
  _FixedWeek(this.week);

  final int week;

  @override
  int build() => week;
}

class _FixedShowOther extends ShowOtherWeeksNotifier {
  _FixedShowOther(this.value);

  final bool value;

  @override
  bool build() => value;
}

class _FixedAutoCollapse extends AutoCollapseWeekendNotifier {
  _FixedAutoCollapse(this.value);

  final bool value;

  @override
  bool build() => value;
}
