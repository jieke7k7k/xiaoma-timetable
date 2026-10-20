import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/widgets/course_card.dart';

Course _course({int start = 1, int end = 3}) => Course(
      semesterId: 1,
      name: '药物化学',
      teacher: '邓卫平',
      classroom: '16-102',
      colorValue: 0xFFC5D3DB,
      dayOfWeek: 4,
      startSection: start,
      endSection: end,
      weeks: const [1, 2, 3],
    );

Future<void> _pump(WidgetTester tester, Course course,
    {double height = 160}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 120,
          height: height,
          child: CourseCard(
            course: course,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('卡片显示名称、教室、老师三项', (tester) async {
    await _pump(tester, _course());
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    final plain = rich.text.toPlainText();
    expect(plain, contains('药物化学'));
    expect(plain, contains('16-102'));
    expect(plain, contains('邓卫平'));
  });

  testWidgets('单节卡片在矮高度下不溢出且三项齐全', (tester) async {
    await _pump(tester, _course(start: 5, end: 5), height: 46);
    expect(tester.takeException(), isNull);
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    final plain = rich.text.toPlainText();
    expect(plain, contains('药物化学'));
    expect(plain, contains('16-102'));
    expect(plain, contains('邓卫平'));
  });

  testWidgets('无老师时只显示名称与教室，不报错', (tester) async {
    await _pump(
      tester,
      const Course(
        semesterId: 1,
        name: '实验室',
        classroom: null,
        colorValue: 0xFFD8CFC0,
        dayOfWeek: 3,
        startSection: 6,
        endSection: 9,
        weeks: [1, 2],
      ),
    );
    expect(tester.takeException(), isNull);
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    expect(rich.text.toPlainText(), contains('实验室'));
  });
}
