import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/web_schedule_parser.dart';

Map<String, dynamic> cell(String t, {int rs = 1, int cs = 1}) => {
  't': t,
  'rs': rs,
  'cs': cs,
};

void main() {
  group('WebScheduleParser 浙师大式网格', () {
    final payload = <String, dynamic>{
      'tables': [
        {
          'rows': [
            [
              cell('时间'),
              cell('星期一'),
              cell('星期二'),
              cell('星期三'),
              cell('星期四'),
              cell('星期五'),
              cell('星期六'),
              cell('星期日'),
            ],
            [
              cell('1'),
              cell('药理学☆\n(1-2节)1-16周\n生化楼3-305\n张三', rs: 2),
              cell(''),
              cell(''),
              cell(''),
              cell(
                '有机化学\n(1-2节)1-8周\n实验楼101\n王五\n'
                '分析化学\n(1-2节)9-16周\n实验楼102\n赵六',
              ),
              cell(''),
              cell(''),
            ],
            [
              cell('2'),
              cell(''),
              cell(''),
              cell(''),
              cell(''),
              cell(''),
              cell(''),
            ],
            [
              cell('3'),
              cell(''),
              cell(''),
              cell('药物化学 (3-4节)5-12周(双) 化工楼2-201 李四(副教授)'),
              cell(''),
              cell(''),
              cell(''),
              cell(''),
            ],
          ],
        },
      ],
    };

    final result = WebScheduleParser.parse(payload, semesterId: 7);

    test('认出 4 门课（含一格两课与跨行合并）', () {
      expect(result.courses.length, 4);
    });

    test('多行单元格：课名/节次/周次/地点/教师', () {
      final c = result.courses.firstWhere((e) => e.name == '药理学');
      expect(c.dayOfWeek, 1);
      expect(c.startSection, 1);
      expect(c.endSection, 2);
      expect(c.weeks.length, 16);
      expect(c.classroom, '生化楼3-305');
      expect(c.teacher, '张三');
      expect(c.semesterId, 7);
    });

    test('单行单元格 + 双周', () {
      final c = result.courses.firstWhere((e) => e.name == '药物化学');
      expect(c.dayOfWeek, 3);
      expect(c.startSection, 3);
      expect(c.endSection, 4);
      expect(c.weeks, [6, 8, 10, 12]);
      expect(c.classroom, '化工楼2-201');
      expect(c.teacher, '李四');
    });

    test('一格两课都认出', () {
      final names = result.courses.map((e) => e.name).toSet();
      expect(names, containsAll(['有机化学', '分析化学']));
      final a = result.courses.firstWhere((e) => e.name == '分析化学');
      expect(a.weeks.first, 9);
      expect(a.weeks.last, 16);
      expect(a.teacher, '赵六');
    });
  });

  test('没有星期表头时认不出（计数正确）', () {
    final result = WebScheduleParser.parse({
      'tables': [
        {
          'rows': [
            [cell('a'), cell('b')],
            [cell('c'), cell('d')],
            [cell('e'), cell('f')],
          ],
        },
      ],
    }, semesterId: 1);
    expect(result.courses, isEmpty);
    expect(result.tablesFound, 1);
  });
}
