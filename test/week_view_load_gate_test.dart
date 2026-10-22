import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/pages/week_view_page.dart';

/// WB-202 第 3 项：周视图加载门闩（weekDataNotReady）单元测试
///
/// 回归冷启动 bug：课程数据未就绪（AsyncLoading 且无值）时周视图必须走加载态，
/// 不允许渲染「本周没有课程」空状态；数据一到（哪怕是空列表）门闩放开——
/// 空状态只在「数据就绪、且本周真没课」时才有资格出现。
void main() {
  group('weekDataNotReady', () {
    test('AsyncLoading 且无值 → 未就绪（转圈，不渲染空状态）', () {
      expect(weekDataNotReady(const AsyncLoading<List<int>>()), isTrue);
    });

    test('AsyncData 有数据 → 已就绪', () {
      expect(weekDataNotReady(const AsyncData(<int>[1, 2, 3])), isFalse);
    });

    test('AsyncData 空列表 → 已就绪（真空状态，不是加载中）', () {
      expect(weekDataNotReady(const AsyncData(<int>[])), isFalse);
    });

    test('AsyncError 无值 → 不算未就绪（不谎报加载中，走既有错误兜底）', () {
      expect(
        weekDataNotReady(
          AsyncError<List<int>>(StateError('读库失败'), StackTrace.current),
        ),
        isFalse,
      );
    });
  });
}
