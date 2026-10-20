import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/utils/exam_countdown.dart';

/// ExamCountdown 单元测试
/// 覆盖：当天、前后若干天、跨月/跨年、忽略时分秒、毫秒时间戳路径、三种文案
void main() {
  group('daysUntil 天数差（忽略时分秒）', () {
    test('同一天不同时刻返回 0（考试在今晚，现在是早上也算今天）', () {
      final now = DateTime(2026, 10, 15, 8, 30);
      expect(ExamCountdown.daysUntil(DateTime(2026, 10, 15, 23, 0), now), 0);
    });

    test('7 天后返回 7（验收标准：显示「还有 7 天」）', () {
      final now = DateTime(2026, 10, 15, 12, 0);
      expect(ExamCountdown.daysUntil(DateTime(2026, 10, 22, 9, 0), now), 7);
    });

    test('明天返回 1', () {
      final now = DateTime(2026, 10, 15, 22, 0);
      expect(ExamCountdown.daysUntil(DateTime(2026, 10, 16, 8, 0), now), 1);
    });

    test('昨天返回 -1（已结束）', () {
      final now = DateTime(2026, 10, 15, 0, 0);
      expect(ExamCountdown.daysUntil(DateTime(2026, 10, 14, 20, 0), now), -1);
    });

    test('跨月边界：10-31 到 11-2 差 2 天', () {
      final now = DateTime(2026, 10, 31, 10, 0);
      expect(ExamCountdown.daysUntil(DateTime(2026, 11, 2, 10, 0), now), 2);
    });

    test('跨年边界：12-31 到次年 1-1 差 1 天', () {
      final now = DateTime(2026, 12, 31, 23, 59);
      expect(ExamCountdown.daysUntil(DateTime(2027, 1, 1, 0, 0), now), 1);
    });

    test('毫秒时间戳路径（与 Course.examDate 存储方式一致）', () {
      // 模拟真实数据流：日期选择器选出本地日期 → 存毫秒 → 读回 → 算天数
      final examDay = DateTime(2026, 10, 22);
      final examMillis = examDay.millisecondsSinceEpoch;
      final exam = DateTime.fromMillisecondsSinceEpoch(examMillis);
      final now = DateTime(2026, 10, 15, 12, 0);
      expect(ExamCountdown.daysUntil(exam, now), 7);
    });
  });

  group('countdownText 文案', () {
    test('大于 0 显示「还有 X 天」', () {
      expect(ExamCountdown.countdownText(7), '还有 7 天');
      expect(ExamCountdown.countdownText(1), '还有 1 天');
    });

    test('等于 0 显示「今天考试」', () {
      expect(ExamCountdown.countdownText(0), '今天考试');
    });

    test('小于 0 显示「已结束」', () {
      expect(ExamCountdown.countdownText(-1), '已结束');
      expect(ExamCountdown.countdownText(-30), '已结束');
    });
  });
}
