import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/utils/week_infer.dart';

Course _course(List<int> weeks, {int weekType = 0}) => Course(
      semesterId: 1,
      name: '课程',
      colorValue: 0xFF000000,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: weeks,
      weekType: weekType,
    );

void main() {
  group('WeekInfer.maxWeek', () {
    test('无草稿 / 周次全为空时返回 0（无从推断）', () {
      expect(WeekInfer.maxWeek(const []), 0);
      expect(WeekInfer.maxWeek([_course([])]), 0);
    });

    test('取所有草稿里最晚的周次', () {
      final drafts = [
        _course([1, 2, 3]),
        _course([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
        _course([2, 4, 6]),
      ];
      expect(WeekInfer.maxWeek(drafts), 10);
    });

    test('单双周只过滤不改变最晚周次', () {
      // weekType=1（单周）时实际只在奇数周上课，但最晚周次仍是 weeks 里的最大值
      expect(WeekInfer.maxWeek([_course([1, 3, 5, 21], weekType: 1)]), 21);
    });
  });

  group('WeekInfer.inferredTotalWeeks', () {
    test('最晚周次不超过学期总周数时返回 null（不提示、不调整）', () {
      final drafts = [_course([1, 2, 3, 16])];
      expect(WeekInfer.inferredTotalWeeks(drafts, 16), isNull);
      expect(WeekInfer.inferredTotalWeeks(drafts, 20), isNull);
    });

    test('最晚周次超过学期总周数时返回该周次', () {
      final drafts = [_course([1, 2, 3, 16]), _course([1, 21])];
      expect(WeekInfer.inferredTotalWeeks(drafts, 20), 21);
    });
  });
}
