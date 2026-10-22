import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/semester.dart';
import 'package:xiaoma_timetable/widgets/semester_form_dialog.dart';

/// 学期表单测试
///
/// ① 校验抽成纯函数 `validateSemesterForm`（新建与编辑共用同一套），这里直接断言；
/// ② 编辑模式的回填与返回用 widget 测（不碰数据库，只验证 id / isCurrent 保留、
///    标题与按钮是编辑文案、日期没改时不弹确认框）。
void main() {
  group('validateSemesterForm', () {
    test('名称为空 / 纯空格都报错', () {
      expect(
        validateSemesterForm(name: '', weeks: '20'),
        '请填写学期名称',
      );
      expect(
        validateSemesterForm(name: '   ', weeks: '20'),
        '请填写学期名称',
      );
    });

    test('周数非数字 / 小于 1 / 大于 30 都报错', () {
      for (final w in ['', 'abc', '0', '-3', '31', '20周']) {
        expect(
          validateSemesterForm(name: '大三上', weeks: w),
          '请输入 1~30 之间的周数',
          reason: '周数 $w 应被拦下',
        );
      }
    });

    test('合法输入通过（含首尾空格）', () {
      expect(validateSemesterForm(name: '大三上', weeks: '1'), isNull);
      expect(validateSemesterForm(name: ' 大三上 ', weeks: ' 30 '), isNull);
    });
  });

  group('编辑模式', () {
    // 2026-09-07 是周一，回填后再归一化还是同一天 → 不应弹开学日期确认框
    final semester = const Semester(
      id: 7,
      name: '大三上学期',
      startDate: '2026-09-07',
      totalWeeks: 20,
      isCurrent: true,
    );

    testWidgets('回填名称 / 开学日期 / 总周数，标题与按钮为编辑文案', (tester) async {
      Semester? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _Harness(initial: semester, onResult: (r) => result = r),
          ),
        ),
      );

      await tester.tap(find.text('打开表单'));
      await tester.pumpAndSettle();

      expect(find.text('编辑学期'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.text('大三上学期'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('2026-09-07（周一）'), findsOneWidget);

      // 原样保存：返回带 id 与 isCurrent 的学期（落库时按 id 更新同一行），
      // 日期没改所以不弹开学日期确认框
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.id, 7);
      expect(result!.isCurrent, isTrue);
      expect(result!.name, '大三上学期');
      expect(result!.startDate, '2026-09-07');
      expect(result!.totalWeeks, 20);
    });

    testWidgets('改了名称与周数后保存，返回的是同一学期的更新值', (tester) async {
      Semester? result;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _Harness(initial: semester, onResult: (r) => result = r),
          ),
        ),
      );

      await tester.tap(find.text('打开表单'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '大三下学期');
      await tester.enterText(find.byType(TextField).last, '16');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(result!.id, 7);
      expect(result!.name, '大三下学期');
      expect(result!.totalWeeks, 16);
      // 日期没动，仍是原值
      expect(result!.startDate, '2026-09-07');
    });
  });
}

/// 只负责把对话框弹出来并把结果交回测试的壳
class _Harness extends StatelessWidget {
  const _Harness({required this.onResult, this.initial});

  final void Function(Semester?) onResult;
  final Semester? initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            onResult(await showSemesterFormDialog(context, initial: initial));
          },
          child: const Text('打开表单'),
        ),
      ),
    );
  }
}
