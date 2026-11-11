import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/models/course.dart';
import 'package:xiaoma_timetable/utils/web_import_diagnosis.dart';
import 'package:xiaoma_timetable/utils/web_schedule_parser.dart';

/// WB_SPEC_231 第 5.1 / 5.3 / 5.4 节：教务抓取的 6 类失败诊断 + 汇总横幅的 M 公式。
///
/// 判定顺序即优先级（1 地址 → 2 加载 → 3 登录 → 4 验证码 → 5 选错页 → 6 解析不匹配），
/// 6 类都不命中时返回 null，由页面回落到原来那两句通用文案。
void main() {
  WebImportDiagnosis? classify({
    bool mainFrameError = false,
    int loading = 100,
    bool hasPassword = false,
    bool hasCaptcha = false,
    bool hasWeekday = false,
    int tableCount = 0,
    String readyState = 'complete',
    int courses = 0,
    int tables = 0,
    int cells = 0,
    String url = '',
    String title = '',
  }) {
    return classifyWebImportFailure(
      mainFrameError: mainFrameError,
      loadingProgress: loading,
      facts: WebDomFacts(
        readyState: readyState,
        hasPasswordInput: hasPassword,
        hasCaptchaHint: hasCaptcha,
        hasWeekdayKeyword: hasWeekday,
        tableCount: tableCount,
        url: url,
        title: title,
      ),
      coursesFound: courses,
      tablesFound: tables,
      cellsScanned: cells,
    );
  }

  group('6 类失败原因', () {
    test('1 地址无法访问：主框加载失败优先于一切 DOM 特征', () {
      final d = classify(mainFrameError: true, hasPassword: true);
      expect(d?.failure, WebImportFailure.unreachable);
      expect(d?.message, '网页加载失败，学校教务网可能需要连接校园网或 VPN');
      expect(d?.actions, [WebImportAction.reload, WebImportAction.editUrl]);
    });

    test('2 页面未加载完：进度 < 90 且没看到课表关键词', () {
      final d = classify(loading: 40, readyState: 'loading');
      expect(d?.failure, WebImportFailure.stillLoading);
      expect(d?.message, '页面还在加载中，请等待课表画面完全显示后再点击抓取');
      expect(d?.actions, [WebImportAction.dismiss]);
    });

    test('2 的例外：进度虽低但已看到课表关键词 → 不再算「没加载完」', () {
      final d = classify(loading: 50, hasWeekday: true, tables: 1, cells: 30);
      expect(d?.failure, isNot(WebImportFailure.stillLoading));
    });

    test('3 登录态拦截：页面里有密码框', () {
      final d = classify(hasPassword: true, tables: 1, cells: 5);
      expect(d?.failure, WebImportFailure.loginRequired);
      expect(d?.message, '检测到当前处于登录界面（或登录已过期），请先在页面中完成登录');
    });

    test('3 的辅助信号：无密码框但 URL 含 login → 仍判登录页', () {
      // Kimi 复审补充 Bug 2：url/title 是规格第 5.1 节的辅助信号，不能只采不用
      final d = classify(
        url: 'https://jwxt.zjnu.edu.cn/cas/login',
        tables: 1,
        cells: 5,
      );
      expect(d?.failure, WebImportFailure.loginRequired);
    });

    test('3 的辅助信号：无密码框且 URL/标题都不是登录页 → 不判登录页', () {
      final d = classify(
        url: 'https://jwxt.zjnu.edu.cn/kb',
        title: '学生课表',
        tables: 1,
        cells: 5,
      );
      expect(d?.failure, WebImportFailure.wrongPage);
    });

    test('4 验证码拦截：有验证码特征且表格极少', () {
      final d = classify(hasCaptcha: true, tableCount: 1, cells: 3);
      expect(d?.failure, WebImportFailure.captcha);
      expect(d?.message, '请先完成页面上的验证码校验，进入个人课表页后再点击抓取');
    });

    test('5 选错页面：无课表关键词、单元格也少', () {
      final d = classify(tableCount: 3, tables: 1, cells: 8);
      expect(d?.failure, WebImportFailure.wrongPage);
      expect(d?.actions, [WebImportAction.dismiss]);
    });

    test('6 解析不匹配：有课表关键词却一门课都没认出', () {
      final d = classify(hasWeekday: true, tables: 2, cells: 90);
      expect(d?.failure, WebImportFailure.layoutUnsupported);
      expect(d?.message, '已找到课表表格，但暂未适配贵校的网页排版格式');
      expect(d?.actions, [
        WebImportAction.openImport,
        WebImportAction.feedback,
      ]);
    });

    test('6 类都不命中 → null（页面回落原有两句兜底文案）', () {
      // 有表格、扫到的单元格够多，但既没有星期关键词也不是验证码页——
      // 这种情况 6 类都不成立，走原来的「找到表格但没认出课程」兜底
      expect(classify(tableCount: 5, tables: 2, cells: 40), isNull);
    });

    test('已认出课程时不做失败判定', () {
      expect(classify(courses: 3, mainFrameError: true), isNull);
    });
  });

  group('抓取异常兜底映射（规格第 5.3 节）', () {
    test('异常兜底固定为第 6 类，原始异常文本不进界面', () {
      // Kimi 复审补充 Bug 3：二选一的实现选择必须钉住测试，
      // 今后改回显示原始异常文本时这里会红
      final d = diagnosisForExtractionError(
        StateError('WebView channel error'),
      );
      expect(d.failure, WebImportFailure.layoutUnsupported);
      expect(d.message, '已找到课表表格，但暂未适配贵校的网页排版格式');
      expect(d.message.contains('WebView'), isFalse);
      expect(d.message.contains('StateError'), isFalse);
    });
  });

  group('汇总横幅的 M：Σ(endSection - startSection + 1)', () {
    Course course(int start, int end) => Course(
          semesterId: 1,
          name: '课',
          colorValue: 0,
          dayOfWeek: 1,
          startSection: start,
          endSection: end,
          weeks: const [1, 2, 3],
        );

    test('单节 → 1', () {
      expect(WebScheduleParser.countWeeklySections([course(3, 3)]), 1);
    });

    test('多节：1-2 与 3-4 → 4', () {
      expect(
        WebScheduleParser.countWeeklySections([course(1, 2), course(3, 4)]),
        4,
      );
    });

    test('多门课：14 门每门 2 节 → 28', () {
      final list = [for (var i = 0; i < 14; i++) course(1, 2)];
      expect(WebScheduleParser.countWeeklySections(list), 28);
    });

    test('空列表 → 0', () {
      expect(WebScheduleParser.countWeeklySections(const []), 0);
    });
  });
}
