import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/providers/providers.dart';
import 'package:xiaoma_timetable/utils/slot_layout.dart';

/// 默认显示全部 7 天：周末无课也不收起周六日（2026-11-24 他定）。
void main() {
  test('周末自动收起开关默认关闭', () {
    expect(AutoCollapseWeekendNotifier().build(), isFalse);
  });

  test('默认（不收起）时周末没课也显示 7 天', () {
    const weekdayOnly = [
      Course(
        semesterId: 1,
        name: '水文学',
        colorValue: 0xFF000000,
        dayOfWeek: 1,
        startSection: 3,
        endSection: 4,
        weeks: [12],
      ),
    ];
    expect(computeDisplayDays(weekdayOnly, 12, false, false), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
  });

  test('手动打开收起后，周末没课才收成 5 天', () {
    const weekdayOnly = [
      Course(
        semesterId: 1,
        name: '水文学',
        colorValue: 0xFF000000,
        dayOfWeek: 1,
        startSection: 3,
        endSection: 4,
        weeks: [12],
      ),
    ];
    expect(computeDisplayDays(weekdayOnly, 12, false, true), [1, 2, 3, 4, 5]);
  });
}
