import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/utils/week_parser.dart';

/// WeekParser 单元测试：覆盖验收标准里的文本解析能力
void main() {
  group('WeekParser.parse 基础', () {
    test('1-16 全部周', () {
      final r = WeekParser.parse('1-16');
      expect(r.weeks, List.generate(16, (i) => i + 1));
      expect(r.weekType, WeekParser.allWeeks);
    });

    test('单个周次 3', () {
      final r = WeekParser.parse('3');
      expect(r.weeks, [3]);
    });

    test('逗号列表 1,3,5,7', () {
      final r = WeekParser.parse('1,3,5,7');
      expect(r.weeks, [1, 3, 5, 7]);
    });

    test('区间加空格 1-8, 10-16', () {
      final r = WeekParser.parse('1-8, 10-16');
      expect(r.weeks, [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16]);
      expect(r.weeks.contains(9), isFalse);
    });

    test('文档示例 1-8, 10-16单周', () {
      final r = WeekParser.parse('1-8, 10-16单周');
      // 单双周语义落到 weeks：1-8 全部 + 10-16 的单周（11/13/15）
      expect(r.weeks, [1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 15]);
      expect(r.weekType, WeekParser.allWeeks);
    });

    test('区间单独带后缀 1-8单周 只取奇数周', () {
      final r = WeekParser.parse('1-8单周');
      expect(r.weeks, [1, 3, 5, 7]);
      expect(r.weekType, WeekParser.allWeeks);
    });

    test('双周后缀 2-14双周', () {
      final r = WeekParser.parse('2-14双周');
      expect(r.weeks, [2, 4, 6, 8, 10, 12, 14]);
      expect(r.weekType, WeekParser.allWeeks);
    });

    test('中文逗号 1，3，5', () {
      final r = WeekParser.parse('1，3，5');
      expect(r.weeks, [1, 3, 5]);
    });

    test('重复与乱序自动去重排序', () {
      final r = WeekParser.parse('5, 3, 5, 1');
      expect(r.weeks, [1, 3, 5]);
    });
  });

  group('WeekParser.parse 异常', () {
    test('空输入', () {
      expect(() => WeekParser.parse(''), throwsA(isA<WeekParseException>()));
    });

    test('起始比分周大', () {
      expect(() => WeekParser.parse('8-3'), throwsA(isA<WeekParseException>()));
    });

    test('超出范围', () {
      expect(() => WeekParser.parse('1-99'),
          throwsA(isA<WeekParseException>()));
    });

    test('含非数字', () {
      expect(() => WeekParser.parse('abc'),
          throwsA(isA<WeekParseException>()));
    });
  });

  group('WeekParser.toText 反向序列化', () {
    test('连续区间合并', () {
      final text = WeekParser.toText(List.generate(16, (i) => i + 1), 0);
      expect(text, '1-16');
    });

    test('单周课程追加后缀', () {
      final text = WeekParser.toText([1, 3, 5, 7], WeekParser.oddWeek);
      expect(text, '1, 3, 5, 7 单周');
    });

    test('双周课程追加后缀', () {
      final text = WeekParser.toText([2, 4], WeekParser.evenWeek);
      expect(text, '2, 4 双周');
    });

    test('断档区间分开显示', () {
      final text = WeekParser.toText([1, 2, 3, 5, 6], 0);
      expect(text, '1-3, 5-6');
    });

    test('空列表返回空串', () {
      expect(WeekParser.toText([], 0), '');
    });
  });

  group('Course.isActiveInWeek 单双周过滤', () {
    test('全部周每周末课', () {
      final c = _course(weeks: [1, 2, 3], weekType: 0);
      expect(c.isActiveInWeek(1), isTrue);
      expect(c.isActiveInWeek(2), isTrue);
      expect(c.isActiveInWeek(3), isTrue);
      expect(c.isActiveInWeek(4), isFalse); // 不在 weeks 里
    });

    test('单周课双周隐藏（药理学验收场景）', () {
      final c = _course(weeks: [1, 2, 3, 4, 5], weekType: 1);
      expect(c.isActiveInWeek(1), isTrue); // 单周显示
      expect(c.isActiveInWeek(2), isFalse); // 双周隐藏
      expect(c.isActiveInWeek(3), isTrue);
    });

    test('双周课单周隐藏', () {
      final c = _course(weeks: [1, 2, 3, 4, 5], weekType: 2);
      expect(c.isActiveInWeek(1), isFalse);
      expect(c.isActiveInWeek(2), isTrue);
      expect(c.isActiveInWeek(4), isTrue);
    });
  });
}

/// 构造测试用课程（直接使用真实 Course 模型）
Course _course({required List<int> weeks, required int weekType}) => Course(
      semesterId: 1,
      name: '测试课程',
      colorValue: 0xFF000000,
      dayOfWeek: 1,
      startSection: 1,
      endSection: 2,
      weeks: weeks,
      weekType: weekType,
    );
