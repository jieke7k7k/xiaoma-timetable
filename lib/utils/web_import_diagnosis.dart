/// 教务抓取失败的 6 类原因（WB_SPEC_231 第 5.1 节）
///
/// 顺序即判定优先级：先命中的优先。判定输入来自三处——
/// ① WebView 的 onWebResourceError（主框加载失败）；
/// ② 注入脚本一次性回传的 DOM 特征（[WebDomFacts]）；
/// ③ 现有解析器的扫描结果（tablesFound / cellsScanned / 认出几门课）。
enum WebImportFailure {
  /// 1 地址无法访问：DNS 失败、连接超时、内网未挂 VPN
  unreachable,

  /// 2 页面未加载完
  stillLoading,

  /// 3 登录态拦截：页面里还有密码框
  loginRequired,

  /// 4 验证码拦截
  captcha,

  /// 5 选错页面：已登录但当前页不是课表
  wrongPage,

  /// 6 解析不匹配：有课表表格但认不出课程
  layoutUnsupported,
}

/// 失败提示下的操作按钮
enum WebImportAction {
  /// 重新加载当前页
  reload,

  /// 聚焦地址栏改网址
  editUrl,

  /// 仅关闭提示
  dismiss,

  /// 改用截图/PDF 导入（跳导入页）
  openImport,

  /// 反馈给开发者（复制截图说明）
  feedback,
}

/// 注入脚本一次性回传的页面 DOM 特征（诊断用，与表格扫描同一段 JS）
class WebDomFacts {
  const WebDomFacts({
    this.readyState = '',
    this.hasPasswordInput = false,
    this.hasCaptchaHint = false,
    this.hasWeekdayKeyword = false,
    this.tableCount = 0,
    this.url = '',
    this.title = '',
  });

  /// document.readyState（'complete' / 'interactive' / 'loading'）
  final String readyState;

  /// 页面里存在密码输入框（登录页 / 登录已过期）
  final bool hasPasswordInput;

  /// 页面里有滑块/验证码特征文本
  final bool hasCaptchaHint;

  /// 页面（含同源 iframe）里出现「星期一 / 周一 / 节次」等课表关键词
  final bool hasWeekdayKeyword;

  /// 主文档 + 同源 iframe 里的 table 元素总数（粗筛，不做解析）
  final int tableCount;

  final String url;
  final String title;

  factory WebDomFacts.fromPayload(Map<String, dynamic> payload) {
    final diag = payload['diag'];
    final map = diag is Map ? diag : const {};
    int asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    return WebDomFacts(
      readyState: (map['readyState'] as String?) ?? '',
      hasPasswordInput: map['hasPassword'] == true,
      hasCaptchaHint: map['hasCaptcha'] == true,
      hasWeekdayKeyword: map['hasWeekday'] == true,
      tableCount: asInt(map['tableCount']),
      url: (map['url'] as String?) ?? '',
      title: (map['title'] as String?) ?? ((payload['title'] as String?) ?? ''),
    );
  }
}

/// 一次抓取失败的判定结果：原因 + 中文文案 + 操作按钮
class WebImportDiagnosis {
  const WebImportDiagnosis(this.failure);

  final WebImportFailure failure;

  /// 用户可见的中文原因（文案照规格第 5.1 节的表，不改写核心意思）
  String get message {
    switch (failure) {
      case WebImportFailure.unreachable:
        return '网页加载失败，学校教务网可能需要连接校园网或 VPN';
      case WebImportFailure.stillLoading:
        return '页面还在加载中，请等待课表画面完全显示后再点击抓取';
      case WebImportFailure.loginRequired:
        return '检测到当前处于登录界面（或登录已过期），请先在页面中完成登录';
      case WebImportFailure.captcha:
        return '请先完成页面上的验证码校验，进入个人课表页后再点击抓取';
      case WebImportFailure.wrongPage:
        return '当前页面未找到课表，请先在网页菜单中点开『个人课表 / 学期理论课表』页面';
      case WebImportFailure.layoutUnsupported:
        return '已找到课表表格，但暂未适配贵校的网页排版格式';
    }
  }

  /// 对应的操作按钮（按规格表的顺序）
  List<WebImportAction> get actions {
    switch (failure) {
      case WebImportFailure.unreachable:
        return const [WebImportAction.reload, WebImportAction.editUrl];
      case WebImportFailure.stillLoading:
        return const [WebImportAction.dismiss];
      case WebImportFailure.loginRequired:
      case WebImportFailure.captcha:
      case WebImportFailure.wrongPage:
        return const [WebImportAction.dismiss];
      case WebImportFailure.layoutUnsupported:
        return const [WebImportAction.openImport, WebImportAction.feedback];
    }
  }
}

/// 按 1→6 的优先级判定失败原因；6 类都不命中时返回 null，
/// 由页面回落到原来那两句通用兜底文案（没找到表格 / 找到表格但没认出课程）。
///
/// 纯函数，不碰 UI、不碰 WebView，便于逐类单测（规格第 8 节）。
WebImportDiagnosis? classifyWebImportFailure({
  required bool mainFrameError,
  required int loadingProgress,
  required WebDomFacts facts,
  required int coursesFound,
  required int tablesFound,
  required int cellsScanned,
}) {
  if (coursesFound > 0) return null;
  // 1 地址无法访问：主框加载失败的置位优先于一切 DOM 特征
  if (mainFrameError) {
    return const WebImportDiagnosis(WebImportFailure.unreachable);
  }
  // 2 页面未加载完：进度没到 90、或 readyState 未 complete，且没看到课表关键词
  final notFinished =
      loadingProgress < 90 || (facts.readyState.isNotEmpty && facts.readyState != 'complete');
  if (notFinished && !facts.hasWeekdayKeyword) {
    return const WebImportDiagnosis(WebImportFailure.stillLoading);
  }
  // 3 登录态拦截：页面里还有密码框就按登录页处理（比 URL/标题更可靠）；
  // URL/标题含 login/cas/auth/「登录」/「统一身份认证」时同样按登录页处理
  // （规格第 5.1 节：密码框为主，URL/Title 为辅；Kimi 复审补充 Bug 2）。
  if (facts.hasPasswordInput ||
      _looksLikeLoginPage(facts.url) ||
      _looksLikeLoginPage(facts.title)) {
    return const WebImportDiagnosis(WebImportFailure.loginRequired);
  }
  // 4 验证码拦截：有验证码特征且表格极少（课表页不会是这种页面）
  if (facts.hasCaptchaHint && facts.hasWeekdayKeyword == false && facts.tableCount <= 2) {
    return const WebImportDiagnosis(WebImportFailure.captcha);
  }
  // 5 选错页面：没有课表关键词、扫到的单元格也少
  if (!facts.hasWeekdayKeyword && cellsScanned < 15) {
    return const WebImportDiagnosis(WebImportFailure.wrongPage);
  }
  // 6 解析不匹配：有课表关键词却一门课都没认出来
  if (facts.hasWeekdayKeyword && coursesFound == 0) {
    return const WebImportDiagnosis(WebImportFailure.layoutUnsupported);
  }
  return null;
}

/// URL/标题是否像登录页（规格第 5.1 节第 3 类的辅助信号）。
bool _looksLikeLoginPage(String s) {
  final lower = s.toLowerCase();
  return lower.contains('login') ||
      lower.contains('cas') ||
      lower.contains('auth') ||
      s.contains('登录') ||
      s.contains('统一身份认证');
}

/// 抓取抛异常时的兜底映射（规格第 5.3 节二选一，实现选第 6 类）：
/// 原始异常只进日志，界面给「已找到课表表格，但暂未适配贵校的网页排版格式」。
/// 钉住这个选择，今后改回显示原始异常文本时测试会红（Kimi 复审补充 Bug 3）。
///
/// [error] 故意不用——任何异常都走同一个兜底，不按异常类型分流。
WebImportDiagnosis diagnosisForExtractionError(Object error) =>
    const WebImportDiagnosis(WebImportFailure.layoutUnsupported);
