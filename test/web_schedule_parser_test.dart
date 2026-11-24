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

  group('节次时间兜底（§10）', () {
    test('主表行首只有节次号时，独立节次时间表补上时间', () {
      final result = WebScheduleParser.parse({
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
              ],
              [
                cell('1'),
                cell('水文学\n(1-2节)1-16周\n教学楼101\n张三'),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
              ],
              [cell('2'), cell(''), cell(''), cell(''), cell(''), cell('')],
              [cell('3'), cell(''), cell(''), cell(''), cell(''), cell('')],
            ],
          },
          {
            'rows': [
              [cell('第1节'), cell('08:00-08:45')],
              [cell('第2节'), cell('08:50-09:35')],
              [cell('第3节'), cell('09:50-10:35')],
            ],
          },
        ],
      }, semesterId: 1);
      expect(result.courses.length, 1);
      expect(result.extractedTimeSlots.length, 3);
      expect(result.extractedTimeSlots[0].section, 1);
      expect(result.extractedTimeSlots[0].startTime, '08:00');
      expect(result.extractedTimeSlots[0].endTime, '08:45');
      expect(result.extractedTimeSlots[2].section, 3);
      expect(result.extractedTimeSlots[2].startTime, '09:50');
    });

    test('主表没时间时，页面全文里的节次时间行补上，无关时间不要', () {
      final result = WebScheduleParser.parse({
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
              ],
              [
                cell('1'),
                cell('水文学\n(1-2节)1-16周\n教学楼101\n张三'),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
              ],
              [cell('2'), cell(''), cell(''), cell(''), cell(''), cell('')],
              [cell('3'), cell(''), cell(''), cell(''), cell(''), cell('')],
            ],
          },
        ],
        'allText': '学生课表\n第1节 08:00-08:45\n第2节 08:50-09:35\n办公时间 08:00-12:00',
      }, semesterId: 1);
      expect(result.extractedTimeSlots.length, 2);
      expect(result.extractedTimeSlots[0].section, 1);
      expect(result.extractedTimeSlots[1].section, 2);
      expect(result.extractedTimeSlots[1].endTime, '09:35');
    });

    test('主表已有时间时松散来源不覆盖', () {
      final result = WebScheduleParser.parse({
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
              ],
              [
                cell('第1节 08:00-08:40'),
                cell('水文学\n(1-2节)1-16周\n教学楼101\n张三'),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
              ],
              [
                cell('第2节 08:50-09:30'),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
              ],
              [cell('3'), cell(''), cell(''), cell(''), cell(''), cell('')],
            ],
          },
          {
            'rows': [
              [cell('第1节'), cell('08:00-08:45')],
              [cell('第2节'), cell('08:50-09:35')],
              [cell('第3节'), cell('09:50-10:35')],
            ],
          },
        ],
      }, semesterId: 1);
      expect(result.extractedTimeSlots.length, 3);
      expect(result.extractedTimeSlots[0].endTime, '08:40');
      expect(result.extractedTimeSlots[1].endTime, '09:30');
      expect(result.extractedTimeSlots[2].startTime, '09:50');
    });

    test('独立表里只有无关时间时读不到', () {
      final result = WebScheduleParser.parse({
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
              ],
              [
                cell('1'),
                cell('水文学\n(1-2节)1-16周\n教学楼101\n张三'),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
              ],
              [cell('2'), cell(''), cell(''), cell(''), cell(''), cell('')],
              [cell('3'), cell(''), cell(''), cell(''), cell(''), cell('')],
            ],
          },
          {
            'rows': [
              [cell('办公时间'), cell('08:00-12:00')],
              [cell('考试安排'), cell('09:00-11:00')],
              [cell('注意事项'), cell('请按时上课')],
            ],
          },
        ],
      }, semesterId: 1);
      expect(result.courses.length, 1);
      expect(result.extractedTimeSlots, isEmpty);
    });

    test('无表头表里只有一行「编号 时间」时不收（2.14.2 复审 Bug 5）', () {
      // 单行「1 08:00-08:45」可能是通知表里的编号+时间，不是作息；
      // 只有整表能读出 ≥2 节作息时，无表头表才进松散来源。
      final result = WebScheduleParser.parse({
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
              ],
              [
                cell('1'),
                cell('水文学\n(1-2节)1-16周\n教学楼101\n张三'),
                cell(''),
                cell(''),
                cell(''),
                cell(''),
              ],
              [cell('2'), cell(''), cell(''), cell(''), cell(''), cell('')],
              [cell('3'), cell(''), cell(''), cell(''), cell(''), cell('')],
            ],
          },
          {
            'rows': [
              [cell('通知'), cell('内容')],
              [cell('1'), cell('08:00-08:45')],
              [cell('备注'), cell('请按时上课')],
            ],
          },
        ],
      }, semesterId: 1);
      expect(result.courses.length, 1);
      expect(result.extractedTimeSlots, isEmpty);
    });
  });
}
