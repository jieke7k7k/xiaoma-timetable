import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';

/// 时间轴三行（节次号 12sp + 起 8sp + 止 8sp，行高 1.15）显示阈值。
/// 2.14.2 复审 Bug 8 核实：公式本身没错（阈值 = 文字总高 + 磁贴上下边距 2px），
/// 这里把边界钉死，免得以后改行高/字号时阈值悄悄错位。
void main() {
  group('时间轴三行显示阈值（行高 1.15）', () {
    test('13 节 autoFit 行高约 39.3dp 时起止都显示', () {
      expect(timeAxisShowsStart(39.3), isTrue);
      expect(timeAxisShowsEnd(39.3), isTrue);
    });

    test('三行临界 34.2dp 时刚好显示止时间', () {
      expect(timeAxisShowsEnd(34.2), isTrue);
      expect(timeAxisShowsEnd(34.1), isFalse);
    });

    test('两行临界 25dp 时只显示起时间', () {
      expect(timeAxisShowsStart(25), isTrue);
      expect(timeAxisShowsStart(24.9), isFalse);
      expect(timeAxisShowsEnd(25), isFalse);
    });

    test('行高不足 25dp 时只显示节次号', () {
      expect(timeAxisShowsStart(24), isFalse);
      expect(timeAxisShowsEnd(24), isFalse);
    });
  });
}
