import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/time_slot.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/utils/course_display_formatter.dart';

void main() {
  group('§1 课名尾部符号清理正则校验', () {
    final trailingSymbols = RegExp(r'[▲△☆★⊙◎○●◆■□※\s]+$');

    test('去除 ⊙ 及原有 ▲△☆★ 尾部符号', () {
      expect(
        '流体力学基础与水力学A⊙'.replaceAll(trailingSymbols, ''),
        '流体力学基础与水力学A',
      );
      expect('高等数学▲★ '.replaceAll(trailingSymbols, ''), '高等数学');
      expect('大学物理※◎'.replaceAll(trailingSymbols, ''), '大学物理');
    });
  });

  group('§2 UiSettings 新字段编解码往返与缺键回默认', () {
    test('缺键时回退到规格默认值', () {
      final s = UiSettings.fromEncoded('{}');
      expect(s.hideNameMarks, isTrue);
      expect(s.hideCampus, isTrue);
      expect(s.showCellTime, isFalse);
      expect(s.showLocationAt, isFalse);
    });

    test('自定义值编解码往返一致', () {
      final origin = const UiSettings().copyWith(
        hideNameMarks: false,
        hideCampus: false,
        showCellTime: true,
        showLocationAt: true,
      );
      final restored = UiSettings.fromEncoded(origin.encode());
      expect(restored.hideNameMarks, isFalse);
      expect(restored.hideCampus, isFalse);
      expect(restored.showCellTime, isTrue);
      expect(restored.showLocationAt, isTrue);
    });
  });

  group('§3 CourseDisplayFormatter 四个开关正反用例', () {
    const slots = [
      TimeSlot(section: 1, startTime: '08:00', endTime: '08:45'),
      TimeSlot(section: 2, startTime: '08:50', endTime: '09:35'),
      TimeSlot(section: 3, startTime: '09:50', endTime: '10:35'),
    ];

    test('hideNameMarks 开/关', () {
      expect(
        CourseDisplayFormatter.formatCourseName(
          '[通识]渔业简史16周',
          hideNameMarks: true,
        ),
        '渔业简史',
      );
      expect(
        CourseDisplayFormatter.formatCourseName(
          '[通识]渔业简史16周',
          hideNameMarks: false,
        ),
        '[通识]渔业简史16周',
      );
    });

    test('hideNameMarks：尾部 N周 的各种写法都清', () {
      const cases = {
        '渔业简史1-16周': '渔业简史',
        '渔业简史（16周）': '渔业简史',
        '渔业简史[1-16周]': '渔业简史',
        '渔业简史第16周': '渔业简史',
        '实验 8周': '实验',
        // 全角方括号写法：\u3010 = 【、\u3011 = 】（文件里不直接写全角
        // 括号，写入链路会吞掉，见 AGENTS.md 2026-11-22 条）。
        '渔业简史\u301016周\u3011': '渔业简史',
        '渔业简史(16周)': '渔业简史',
      };
      for (final e in cases.entries) {
        expect(
          CourseDisplayFormatter.formatCourseName(
            e.key,
            hideNameMarks: true,
          ),
          e.value,
        );
      }
    });

    test('hideNameMarks：老数据尾部 ⊙ 类符号在显示层清掉', () {
      expect(
        CourseDisplayFormatter.formatCourseName(
          '流体力学基础与水力学A⊙',
          hideNameMarks: true,
        ),
        '流体力学基础与水力学A',
      );
      // 圆括号前缀不动
      expect(
        CourseDisplayFormatter.formatCourseName(
          '（实验）有机化学',
          hideNameMarks: true,
        ),
        '（实验）有机化学',
      );
      // 符号与 N周 叠加时顺序不能错：先清符号再清周（「16周⊙」也得清干净）
      expect(
        CourseDisplayFormatter.formatCourseName(
          '[通识]渔业简史16周⊙',
          hideNameMarks: true,
        ),
        '渔业简史',
      );
      expect(
        CourseDisplayFormatter.formatCourseName(
          '课名⊙16周',
          hideNameMarks: true,
        ),
        '课名',
      );
      // 另一种叠加顺序：周在符号前面（「16周⊙」）同样清干净
      expect(
        CourseDisplayFormatter.formatCourseName(
          '渔业简史16周⊙',
          hideNameMarks: true,
        ),
        '渔业简史',
      );
      // 去掉后为空保留原课名
      expect(
        CourseDisplayFormatter.formatCourseName(
          '[测试]',
          hideNameMarks: true,
        ),
        '[测试]',
      );
    });

    test('hideCampus 开/关（去掉后为空时保留原地点）', () {
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区獐314',
          hideCampus: true,
          showLocationAt: false,
        ),
        '獐314',
      );
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区獐314',
          hideCampus: false,
          showLocationAt: false,
        ),
        '黑石礁校区獐314',
      );
      // 去掉后为空时保留原地点
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区',
          hideCampus: true,
          showLocationAt: false,
        ),
        '黑石礁校区',
      );
      // 分隔符顺手清掉，不留「-獐314」
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区-獐314',
          hideCampus: true,
          showLocationAt: false,
        ),
        '獐314',
      );
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区、獐314',
          hideCampus: true,
          showLocationAt: false,
        ),
        '獐314',
      );
      // en dash（U+2013）分隔符：规格 §2 列了，代码一度漏掉（复审 P1-5）
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区–獐314',
          hideCampus: true,
          showLocationAt: false,
        ),
        '獐314',
      );
      // 校区在末尾（「獐314校区」）：整串被匹配，去空兜底保留原地点
      expect(
        CourseDisplayFormatter.formatClassroom(
          '獐314校区',
          hideCampus: true,
          showLocationAt: false,
        ),
        '獐314校区',
      );
    });

    test('showLocationAt 开/关', () {
      expect(
        CourseDisplayFormatter.formatClassroom(
          '黑石礁校区獐314',
          hideCampus: true,
          showLocationAt: true,
        ),
        '@獐314',
      );
      expect(
        CourseDisplayFormatter.formatClassroom(
          '@獐314',
          hideCampus: false,
          showLocationAt: true,
        ),
        '@獐314',
      );
    });

    test('showCellTime 节次起止格式化', () {
      expect(
        CourseDisplayFormatter.formatCellTime(
          startSection: 1,
          endSection: 2,
          timeSlots: slots,
        ),
        '08:00–09:35',
      );
      expect(
        CourseDisplayFormatter.formatCellTime(
          startSection: 3,
          endSection: 3,
          timeSlots: slots,
        ),
        '09:50–10:35',
      );
    });

    test('showCellTime：作息缺失或节次越界时静默不显示', () {
      expect(
        CourseDisplayFormatter.formatCellTime(
          startSection: 1,
          endSection: 2,
          timeSlots: const [],
        ),
        '',
      );
      // 末节超出作息范围（只有 1–3 节，课排到第 12 节）
      expect(
        CourseDisplayFormatter.formatCellTime(
          startSection: 1,
          endSection: 12,
          timeSlots: slots,
        ),
        '',
      );
      // 首节超出作息范围
      expect(
        CourseDisplayFormatter.formatCellTime(
          startSection: 12,
          endSection: 12,
          timeSlots: slots,
        ),
        '',
      );
    });
  });
}
