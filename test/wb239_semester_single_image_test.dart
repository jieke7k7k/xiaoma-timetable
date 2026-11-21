import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/models/ui_settings.dart';
import 'package:xiaoma_timetable/pages/share_image_page.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';
import 'package:xiaoma_timetable/utils/semester_export_helper.dart';
import 'package:xiaoma_timetable/widgets/conflict_block.dart';

void main() {
  group('WB_SPEC_239 导出整学期改单图（方案 C 一图合集版）测试', () {
    test('1. 方案 C 布局：独占课、半学期冲突课、单双周交错课正确区分', () {
      final courses = [
        // 周一 1-2 节：1-8周 与 9-16周 前后交接 -> conflict
        Course(
          semesterId: 1,
          name: '药物化学',
          classroom: '16-102',
          colorValue: 0xFF6B8E7B,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          weeks: List.generate(8, (i) => i + 1),
        ),
        Course(
          semesterId: 1,
          name: '药理学',
          classroom: '16-639',
          colorValue: 0xFF7E9BB5,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          weeks: List.generate(8, (i) => i + 9),
        ),
        // 周一 3-4 节：单双周交错 -> parityPair（不画焦糖冲突块）
        Course(
          semesterId: 1,
          name: '生物药剂学',
          classroom: '16-201',
          colorValue: 0xFFD8EAD3,
          dayOfWeek: 1,
          startSection: 3,
          endSection: 4,
          weeks: List.generate(16, (i) => i + 1),
          weekType: 1,
        ),
        Course(
          semesterId: 1,
          name: '医学统计学',
          classroom: '机房3',
          colorValue: 0xFFD4E4F7,
          dayOfWeek: 1,
          startSection: 3,
          endSection: 4,
          weeks: List.generate(16, (i) => i + 1),
          weekType: 2,
        ),
      ];

      final slots = SemesterExportHelper.layoutSemesterMasterDay(
        dayCourses: courses,
        dayOfWeek: 1,
        maxSection: 14,
      );

      expect(slots.length, 2);
      expect(slots[0].kind, SemesterMasterSlotKind.conflict);
      expect(slots[1].kind, SemesterMasterSlotKind.parityPair);
    });

    test('2. renderWithinLimit：超过 2MB 时自动降级 pixelRatio 直到满足上限', () async {
      final usedRatios = <double>[];
      // 复用 share_image_page 已有的 renderWithinLimit（render 回调 + 初始像素比）：
      // 3.0 档超限 → 2.25 档仍超限 → 1.6875 档满足上限。
      final result = await renderWithinLimit((ratio) async {
        usedRatios.add(ratio);
        // 模拟高分辨率超 2MB，降级后低于 2MB
        if (ratio > 2.2) {
          return Uint8List(3 * 1024 * 1024);
        }
        return Uint8List(400 * 1024);
      }, 3.0);

      expect(result, isNotNull);
      expect(result!.lengthInBytes, lessThanOrEqualTo(kMaxPngBytes));
      expect(usedRatios.length, greaterThan(1));
    });

    testWidgets('3. SemesterSingleImageSheet 渲染：仅冲突处画 ConflictBlock，单双周不画', (
      tester,
    ) async {
      // 真机视口（390×844）：ConflictBlock 按视口宽判小屏字号（<=600），
      // 默认 800×600 测试窗口会走宽屏字号，标签变宽、半块溢出——与真机不一致。
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semester = Semester(
        id: 1,
        name: '大三下学期',
        startDate: '2026-09-07',
        isCurrent: true,
      );
      final courses = [
        Course(
          semesterId: 1,
          name: '药物化学',
          classroom: '16-102',
          colorValue: 0xFF6B8E7B,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          weeks: List.generate(8, (i) => i + 1),
        ),
        Course(
          semesterId: 1,
          name: '药理学',
          classroom: '16-639',
          colorValue: 0xFF7E9BB5,
          dayOfWeek: 1,
          startSection: 1,
          endSection: 2,
          weeks: List.generate(8, (i) => i + 9),
        ),
        Course(
          semesterId: 1,
          name: '药剂学',
          classroom: '16-204',
          colorValue: 0xFFD8EAD3,
          dayOfWeek: 2,
          startSection: 3,
          endSection: 4,
          weeks: List.generate(18, (i) => i + 1),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemesterSingleImageSheet(
                semester: semester,
                courses: courses,
                slots: defaultTimeSlots,
                bands: computeActiveBands(
                  lunchAfter: 5,
                  dinnerAfter: 9,
                  sectionCount: 14,
                  settings: const BandSettings(),
                ),
                ui: const UiSettings(),
                displayDays: const [1, 2, 3, 4, 5, 6, 7],
              ),
            ),
          ),
        ),
      );

      // WB_SPEC_247：整学期导出图标题只留学期名，不要「课表」二字、
      // 不要日期范围和（共 N 周）；本周导出图标题不动。
      expect(find.text('大三下学期'), findsOneWidget);
      // 负向断言：旧标题里的日期范围与（共 N 周）不得出现在图里。
      expect(find.textContaining('2026.09.07'), findsNothing);
      expect(find.textContaining('共 18 周'), findsNothing);
      // DeepSeek 复审 P2-2：负向断言，旧字样不得出现在图里。
      expect(find.textContaining('全学期'), findsNothing);
      expect(find.textContaining('按课表自动检测'), findsNothing);
      expect(find.byType(ConflictBlock), findsOneWidget);
      expect(find.text('1-18周'), findsOneWidget);
    });
  });
}
