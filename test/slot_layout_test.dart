import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/utils/slot_layout.dart';

Course _course({
  int? id,
  String name = '课程',
  int dayOfWeek = 1,
  int startSection = 1,
  int endSection = 2,
  List<int> weeks = const [1, 2, 3, 4, 5],
}) =>
    Course(
      id: id,
      semesterId: 1,
      name: name,
      colorValue: 0xFF000000,
      dayOfWeek: dayOfWeek,
      startSection: startSection,
      endSection: endSection,
      weeks: weeks,
    );

/// 取某节次所在的非空段（测试用）
DisplaySlot slotAt(List<DisplaySlot> slots, int section) =>
    slots.firstWhere((s) => section >= s.startSection && section <= s.endSection);

void main() {
  group('SlotLayout.layoutDay 三态解析', () {
    test('空：无课程时全段为 empty', () {
      final slots = SlotLayout.layoutDay(
          dayCourses: [], week: 1, showDimmed: true, maxSection: 4);
      expect(slots.length, 1);
      expect(slots.first.kind, SlotKind.empty);
      expect(slots.first.startSection, 1);
      expect(slots.first.endSection, 4);
    });

    test('本周优先：同节有本周课时非本周课被隐藏', () {
      final active = _course(name: '本周课', weeks: [1, 2]);
      final dimmed = _course(name: '非本周课', weeks: [3, 4]);
      final slots = SlotLayout.layoutDay(
        dayCourses: [active, dimmed],
        week: 1,
        showDimmed: true,
        maxSection: 4,
      );
      final s1 = slotAt(slots, 1);
      expect(s1.kind, SlotKind.single);
      expect(s1.dimmed, isFalse);
      expect(s1.courses.map((c) => c.name), ['本周课']);
    });

    test('非本周淡化：无本周课且开关开时显示置灰段', () {
      final dimmed = _course(name: '非本周课', weeks: [3, 4]);
      final slots = SlotLayout.layoutDay(
        dayCourses: [dimmed],
        week: 1,
        showDimmed: true,
        maxSection: 4,
      );
      final s1 = slotAt(slots, 1);
      expect(s1.kind, SlotKind.single);
      expect(s1.dimmed, isTrue);
      expect(s1.courses.first.name, '非本周课');
    });

    test('开关关闭时非本周课不显示', () {
      final dimmed = _course(name: '非本周课', weeks: [3, 4]);
      final slots = SlotLayout.layoutDay(
        dayCourses: [dimmed],
        week: 1,
        showDimmed: false,
        maxSection: 4,
      );
      expect(slots.every((s) => s.kind == SlotKind.empty), isTrue);
    });

    test('多课冲突：同节多门本周课为 multi', () {
      final a = _course(id: 1, name: 'A');
      final b = _course(id: 2, name: 'B');
      final slots = SlotLayout.layoutDay(
        dayCourses: [a, b],
        week: 1,
        showDimmed: false,
        maxSection: 4,
      );
      final s1 = slotAt(slots, 1);
      expect(s1.kind, SlotKind.multi);
      expect(s1.courses.length, 2);
      expect(s1.extraCount, 1);
    });

    test('连续合并：同一门课跨节合成一段', () {
      final a = _course(id: 1, name: 'A', startSection: 1, endSection: 3);
      final slots = SlotLayout.layoutDay(
        dayCourses: [a],
        week: 1,
        showDimmed: false,
        maxSection: 4,
      );
      final nonEmpty = slots.where((s) => !s.isEmpty).toList();
      expect(nonEmpty.length, 1);
      expect(nonEmpty.first.startSection, 1);
      expect(nonEmpty.first.endSection, 3);
      expect(nonEmpty.first.span, 3);
    });

    test('不合并：相邻节次是不同课程时分为两段', () {
      final a = _course(id: 1, name: 'A', startSection: 1, endSection: 1);
      final b = _course(id: 2, name: 'B', startSection: 2, endSection: 2);
      final slots = SlotLayout.layoutDay(
        dayCourses: [a, b],
        week: 1,
        showDimmed: false,
        maxSection: 4,
      );
      final nonEmpty = slots.where((s) => !s.isEmpty).toList();
      expect(nonEmpty.length, 2);
    });

    test('部分遮挡：长置灰课被本周课挡住一半，剩余部分仍显示', () {
      // 置灰课占 1-4 节，本周课占 1-2 节 → 置灰课只在 3-4 节显示
      final dimmed =
          _course(id: 9, name: '长课', startSection: 1, endSection: 4, weeks: [9]);
      final active =
          _course(id: 1, name: '本周课', startSection: 1, endSection: 2);
      final slots = SlotLayout.layoutDay(
        dayCourses: [dimmed, active],
        week: 1,
        showDimmed: true,
        maxSection: 4,
      );
      final s1 = slotAt(slots, 1);
      expect(s1.dimmed, isFalse);
      expect(s1.courses.first.name, '本周课');
      final s3 = slotAt(slots, 3);
      expect(s3.dimmed, isTrue);
      expect(s3.courses.first.name, '长课');
      expect(s3.startSection, 3);
      expect(s3.endSection, 4);
    });

    test('非法节次被钳制到范围内', () {
      final a = _course(name: 'A', startSection: 0, endSection: 99);
      final slots = SlotLayout.layoutDay(
        dayCourses: [a],
        week: 1,
        showDimmed: false,
        maxSection: 4,
      );
      final nonEmpty = slots.where((s) => !s.isEmpty).toList();
      expect(nonEmpty.length, 1);
      expect(nonEmpty.first.startSection, 1);
      expect(nonEmpty.first.endSection, 4);
    });
  });
}
