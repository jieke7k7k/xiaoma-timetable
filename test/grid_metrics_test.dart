import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/ui/grid_metrics.dart';

/// 网格尺寸常量与网格线跳带纯函数测试（WB_SPEC_210 第 1 / 2 节）
///
/// 覆盖：
/// 1. 底栏高度常量 [kBottomBarHeight] 由 72 压到 56；
/// 2. 竖线分段纯函数 [verticalLineSegments]：无带子连续分段、单带/双带跳过
///    带子高度、带子 after 越界不参与分段、分段纵向跨度与整表高度守恒。
void main() {
  group('底栏高度常量', () {
    test('kBottomBarHeight 由 72 压到 56（WB_SPEC_210 第 1 节）', () {
      expect(kBottomBarHeight, 56);
    });
  });

  group('verticalLineSegments 竖线分段', () {
    test('无休息带：每节一段、首尾相接，覆盖整表高度', () {
      final segs = verticalLineSegments(
        rowHeight: 60,
        sectionCount: 4,
        activeBands: const [],
      );
      expect(segs.length, 4);
      expect(segs[0], (start: 0.0, end: 60.0));
      expect(segs[1], (start: 60.0, end: 120.0));
      expect(segs[2], (start: 120.0, end: 180.0));
      expect(segs[3], (start: 180.0, end: 240.0));
    });

    test('单条休息带（第 2 节后）：带子高度被跳过，前后分段断开', () {
      const band = (after: 2, label: '午休', interval: '12:00–14:00');
      final segs = verticalLineSegments(
        rowHeight: 60,
        sectionCount: 4,
        activeBands: [band],
      );
      // 第 2 段末 = 120（带子顶边），第 3 段从 120 + kBandHeight（带子底边）起
      expect(segs.length, 4);
      expect(segs[1].end, 120.0);
      expect(segs[2].start, 120.0 + kBandHeight);
      // 带子区间内没有任何分段覆盖（跳过的宽度正好等于带子高度）
      expect(segs[2].start - segs[1].end, kBandHeight);
    });

    test('两条休息带（午休第 2 节后、晚间第 3 节后）：两处都跳过', () {
      const lunch = (after: 2, label: '午休', interval: '12:00–14:00');
      const dinner = (after: 3, label: '晚间', interval: '17:10–18:00');
      final segs = verticalLineSegments(
        rowHeight: 50,
        sectionCount: 5,
        activeBands: [lunch, dinner],
      );
      expect(segs.length, 5);
      // 午休：第 2 节末 = 100，第 3 节从 100 + kBandHeight 起
      expect(segs[1].end, 100.0);
      expect(segs[2].start, 100.0 + kBandHeight);
      expect(segs[2].end, 150.0 + kBandHeight);
      // 晚间：第 3 节末 = 150 + kBandHeight，第 4 节从 150 + 2*kBandHeight 起
      expect(segs[3].start, 150.0 + 2 * kBandHeight);
    });

    test('带子 after 越界（不落在任何节之后）时不参与分段', () {
      // computeActiveBands 已把 after >= sectionCount 的带子过滤掉，此处兜底：
      // 即便越界带子传入，也不影响分段（等价于无带子）
      const band = (after: 99, label: '晚间', interval: '17:10–18:00');
      final segs = verticalLineSegments(
        rowHeight: 60,
        sectionCount: 3,
        activeBands: [band],
      );
      expect(segs.length, 3);
      expect(segs[1].end, 120.0);
      expect(segs[2].end, 180.0);
    });

    test('分段纵向跨度守恒：节次总高 + 带子总高 = 最后一段结束处', () {
      const lunch = (after: 5, label: '午休', interval: '12:00–14:00');
      const dinner = (after: 9, label: '晚间', interval: '17:10–18:00');
      final segs = verticalLineSegments(
        rowHeight: 40,
        sectionCount: 13,
        activeBands: [lunch, dinner],
      );
      // 所有分段只覆盖节次（不含带子）
      final segmentedHeight = segs.fold<double>(
        0,
        (sum, s) => sum + (s.end - s.start),
      );
      expect(segmentedHeight, 13 * 40.0);
      // 整表高度 = 节次总高 + 带子总高，最后一段结束处应等于它
      expect(segs.last.end, 13 * 40.0 + 2 * kBandHeight);
    });
  });
}
