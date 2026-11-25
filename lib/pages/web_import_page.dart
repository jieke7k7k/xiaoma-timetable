import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../ui/app_styles.dart';
import '../utils/app_haptics.dart';
import '../utils/web_import_diagnosis.dart';
import '../utils/web_schedule_parser.dart';
import '../widgets/app_dialog.dart';

/// 教务网页导入页（1.3.0）
///
/// 原理与 WakeUp 等主流课表软件一致：内置浏览器打开学校教务系统，
/// 用户在学校页面里亲自登录并打开课表页，点悬浮的「抓取本页课表」后，
/// 注入脚本读取页面上的课表表格结构回传，本地解析成课程草稿。
/// 账号密码只输入在学校网页里，App 不读取、不保存。
class WebImportPage extends StatefulWidget {
  /// 选校器传入的该校教务登录页网址；为 null 时进入手动输入模式（不自动加载）
  final String? initialUrl;

  /// 可选的 WebViewController 工厂（仅用于 widget 测试注入，生产环境走默认创建）
  final WebViewController Function()? controllerFactory;

  const WebImportPage({
    super.key,
    required this.semesterId,
    this.initialUrl,
    this.controllerFactory,
  });

  final int semesterId;

  @override
  State<WebImportPage> createState() => _WebImportPageState();
}

class _WebImportPageState extends State<WebImportPage> {
  /// 标准桌面端 Chrome UA（去掉 Android ... Mobile，避免老教务系统重定向到残缺 H5 登录页）
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Safari/537.36';

  late final WebViewController _controller;
  final _urlCtrl = TextEditingController();
  final _urlFocus = FocusNode();
  var _loading = 0; // 0-100，100 或 0 表示不在加载
  var _extracting = false;

  /// 是否已发起过页面加载；为 false 时显示引导占位并禁用「抓取本页课表」
  bool _hasLoadedPage = false;

  /// 失败判定结果（null = 当前没有提示）；6 类之外的兜底走 [_fallbackHint]
  WebImportDiagnosis? _diagnosis;

  /// 兜底提示（6 类都不命中时用，沿用原有两句文案）
  String? _fallbackHint;

  /// 主框加载失败置位（WB_SPEC_231 第 5.2 节）：只在 onWebResourceError 里
  /// 且 isForMainFrame 为真时置位，下一次 onPageStarted 清零
  var _mainFrameError = false;

  /// 抓取脚本：遍历主文档与同源 iframe 里的所有表格，
  /// 逐行回传单元格文本与跨行/跨列，同时回传页面全文供节次时间兜底扫描，
  /// 回传 JSON 字符串
  static const _extractJs = r'''
(function () {
  function cellText(el) {
    return (el.innerText || '').replace(/ /g, ' ').trim();
  }
  function scan(doc, out) {
    var tables = doc.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      var rows = [];
      var trs = tables[i].querySelectorAll('tr');
      for (var r = 0; r < trs.length; r++) {
        var cells = [];
        var tds = trs[r].querySelectorAll('td,th');
        for (var c = 0; c < tds.length; c++) {
          cells.push({
            t: cellText(tds[c]),
            rs: tds[c].rowSpan || 1,
            cs: tds[c].colSpan || 1
          });
        }
        if (cells.length) rows.push(cells);
      }
      if (rows.length >= 3) out.push({ rows: rows });
    }
    var frames = doc.querySelectorAll('iframe,frame');
    for (var f = 0; f < frames.length; f++) {
      try {
        var d = frames[f].contentDocument;
        if (d) scan(d, out);
      } catch (e) { /* 跨域框架跳过 */ }
    }
  }
  var out = [];
  scan(document, out);
  // 诊断字段（WB_SPEC_231 第 5.1 节）：与表格扫描同一段脚本、同一次注入回传，
  // 不额外跑第二次 runJavaScriptReturningResult。
  var bodyText = document.body ? (document.body.innerText || '') : '';
  var frameText = '';
  var frames = document.querySelectorAll('iframe,frame');
  for (var k = 0; k < frames.length; k++) {
    try {
      var fd = frames[k].contentDocument;
      if (fd && fd.body) frameText += ' ' + (fd.body.innerText || '');
    } catch (e) { /* 跨域框架跳过 */ }
  }
  var allText = bodyText + ' ' + frameText;
  return JSON.stringify({
    title: document.title,
    tables: out,
    // §10：页面全文（主文档 + 同源 iframe）供节次时间兜底扫描；
    // 解析器只认行首是节次标记或整行只有一个时间段的行，其余含时间的
    // 文本一律不要。
    allText: allText,
    diag: {
      readyState: document.readyState,
      url: location.href,
      title: document.title,
      hasPassword: Array.from(document.querySelectorAll('input[type="password"]')).some(function (el) { var r = el.getClientRects(); if (!r || r.length === 0) return false; var cs = getComputedStyle(el); return cs.display !== 'none' && cs.visibility !== 'hidden'; }),
      hasCaptcha: /(captcha|geetest|验证码|安全验证)/i.test(allText),
      hasWeekday: /(星期[一二三四五六日天]|周[一二三四五六日天]|节次)/.test(allText),
      tableCount: document.querySelectorAll('table').length
    }
  });
})()
''';

  @override
  void initState() {
    super.initState();

    final initial = widget.initialUrl?.trim();
    final hasInitialUrl = initial != null && initial.isNotEmpty;
    if (hasInitialUrl) _urlCtrl.text = initial;

    _controller = widget.controllerFactory?.call() ?? WebViewController();
    _configureWebViewController(_controller);

    if (hasInitialUrl) {
      _hasLoadedPage = true;
      _loadUrl(initial);
    } else {
      // 手动输入模式：不自动加载任何页面，首帧后自动聚焦地址栏并弹出键盘
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _urlFocus.requestFocus();
      });
    }
  }

  /// 配置 WebViewController：桌面 UA + Android 第三方 Cookie + Android Mixed Content
  /// 必须在创建 controller 之后、调用 loadRequest 之前执行
  void _configureWebViewController(WebViewController controller) {
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _loading = p);
          },
          onPageStarted: (url) {
            _urlCtrl.text = url;
            // 新导航开始：清掉上一次的主框失败置位与提示
            _mainFrameError = false;
            if (mounted) {
              setState(() {
                _loading = 0;
                _diagnosis = null;
                _fallbackHint = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = 100);
          },
          // WB_SPEC_231 第 5.2 节：地址打不开（DNS/超时/内网未挂 VPN）时
          // 之前没有任何反馈；这里只认主框错误，子资源 404、广告加载失败不算
          onWebResourceError: (error) {
            // isForMainFrame 在该版本是可空 bool，null 视为非主框
            if (error.isForMainFrame != true) return;
            if (!mounted) return;
            setState(() => _mainFrameError = true);
          },
        ),
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // 允许第三方 Cookie（解决 CAS iframe / 跨子域验证码与加密盐值带不上 JSESSIONID 的问题）
      final cookieManager = WebViewCookieManager().platform;
      if (cookieManager is AndroidWebViewCookieManager) {
        cookieManager.setAcceptThirdPartyCookies(platform, true);
      }
      // 允许 HTTPS 页面加载 HTTP 子资源（解决老教务页 rsa.js / des.js / 验证码走 http 被静默拦截）
      platform.setMixedContentMode(MixedContentMode.alwaysAllow);
    }
  }

  void _loadUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _controller.loadRequest(uri);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _go() {
    var url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (!_hasLoadedPage) {
      setState(() => _hasLoadedPage = true);
    }
    _loadUrl(url);
    FocusScope.of(context).unfocus();
  }

  Future<void> _extract() async {
    // 主框根本没打开（第 1 类）：直接给原因，不跑注入脚本、不抛异常
    if (_mainFrameError) {
      setState(() {
        _diagnosis = const WebImportDiagnosis(WebImportFailure.unreachable);
        _fallbackHint = null;
      });
      return;
    }
    setState(() {
      _extracting = true;
      _diagnosis = null;
      _fallbackHint = null;
    });
    try {
      final raw = await _controller.runJavaScriptReturningResult(_extractJs);
      var text = raw.toString();
      // Android 端回传的是 JSON 编码过的字符串，需要先解一层
      try {
        final once = jsonDecode(text);
        if (once is String) text = once;
      } catch (_) {
        // 本身就是 JSON 文本则直接用
      }
      final payload = jsonDecode(text) as Map<String, dynamic>;
      final result = WebScheduleParser.parse(
        payload,
        semesterId: widget.semesterId,
      );
      // 诊断字段与表格扫描同一次注入回传（规格第 5.1 节）
      final facts = WebDomFacts.fromPayload(payload);
      if (!mounted) return;
      if (result.courses.isEmpty) {
        final diag = classifyWebImportFailure(
          mainFrameError: _mainFrameError,
          loadingProgress: _loading,
          facts: facts,
          coursesFound: result.courses.length,
          tablesFound: result.tablesFound,
          cellsScanned: result.cellsScanned,
        );
        setState(() {
          _diagnosis = diag;
          // 6 类都不命中时才用兜底文案（沿用原有两句，一字不改）
          _fallbackHint = diag != null
              ? null
              : result.tablesFound == 0
              ? '当前页面未找到课表表格。请先登录教务系统并打开「学生课表」页面，再点击抓取。'
              : '已找到 ${result.tablesFound} 个表格、${result.cellsScanned} 个单元格，'
                    '但未识别出课程。请确认已打开课表页面；若已打开，'
                    '可能是该校格式暂未适配——请将课表页截图发送给开发者适配。';
        });
        return;
      }
      Navigator.pop(context, result);
    } catch (e) {
      // 规格第 5.3 节：原始异常文本（JS 错误串 / 类型名）绝不展示给用户，只进日志；
      // 界面按第 6 类兜底（「已找到课表表格，但暂未适配贵校的网页排版格式」）
      debugPrint('抓取课表失败：$e');
      if (!mounted) return;
      setState(() {
        _diagnosis = diagnosisForExtractionError(e);
        _fallbackHint = null;
      });
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  /// 执行提示条上的操作按钮
  void _runAction(WebImportAction action) {
    switch (action) {
      case WebImportAction.reload:
        setState(() {
          _diagnosis = null;
          _fallbackHint = null;
          _mainFrameError = false;
        });
        _controller.reload();
      case WebImportAction.editUrl:
        setState(() {
          _diagnosis = null;
          _fallbackHint = null;
        });
        _urlFocus.requestFocus();
      case WebImportAction.dismiss:
        setState(() {
          _diagnosis = null;
          _fallbackHint = null;
        });
      case WebImportAction.openImport:
        Navigator.pushNamed(context, '/import');
      case WebImportAction.feedback:
        // 沿用原来「把课表页截图发我，我来适配」的意思
        showAppInfoDialog(
          context,
          title: '反馈给开发者',
          message: '请将课表页截图发送给开发者（微信或邮件均可），以便适配贵校的排版格式。',
        );
    }
  }

  /// 操作按钮文案（「选错页面」那类的关闭按钮要写「继续操作网页」）
  String _actionLabel(WebImportDiagnosis diag, WebImportAction action) {
    switch (action) {
      case WebImportAction.reload:
        return '重新加载';
      case WebImportAction.editUrl:
        return '修改网址';
      case WebImportAction.dismiss:
        switch (diag.failure) {
          case WebImportFailure.stillLoading:
            return '等待并重试';
          case WebImportFailure.wrongPage:
            return '继续操作网页';
          default:
            return '我知道了';
        }
      case WebImportAction.openImport:
        return '改用截图/PDF导入';
      case WebImportAction.feedback:
        return '反馈给开发者';
    }
  }

  /// 失败提示条：原因 + 操作按钮（沿用原红色容器样式，只把纯文本升级成两段）
  Widget _hintBox(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diag = _diagnosis;
    final text = diag?.message ?? _fallbackHint;
    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontSize: 13)),
          if (diag != null)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              children: [
                for (final action in diag.actions)
                  TextButton(
                    // WB_SPEC_235 跟进 §1-4：诊断建议按钮 = 轻点档
                    onPressed: () {
                      AppHaptics.tap();
                      _runAction(action);
                    },
                    style: TextButton.styleFrom(
                      // WB_SPEC_256 §6.5 / §7：移除 visualDensity.compact，视觉高由 32dp 升至 36dp
                      enableFeedback: false,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      _actionLabel(diag, action),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('从教务官网导入'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            tooltip: '后退',
            // WB_SPEC_235 §7：网页导航三个按钮 = 轻点档
            onPressed: () async {
              if (await _controller.canGoBack()) {
                AppHaptics.tap();
                _controller.goBack();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            tooltip: '前进',
            onPressed: () async {
              if (await _controller.canGoForward()) {
                AppHaptics.tap();
                _controller.goForward();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () {
              AppHaptics.tap();
              _controller.reload();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    focusNode: _urlFocus,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '教务系统网址（可改成自己学校的）',
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _go(),
                  ),
                ),
                const SizedBox(width: 8),
                // WB_SPEC_235 跟进 §1-4：「打开」网址 = 轻点档
                FilledButton(
                  style: FilledButton.styleFrom(enableFeedback: false),
                  onPressed: () {
                    AppHaptics.tap();
                    _go();
                  },
                  child: const Text('打开'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '① 在学校页面登录（账号密码仅填写于学校网页，应用不保存）'
                '→ ② 打开「学生课表」页 → ③ 点击右下角「抓取本页课表」',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_loading > 0 && _loading < 100)
            LinearProgressIndicator(value: _loading / 100),
          if (_diagnosis != null || _fallbackHint != null) _hintBox(context),
          Expanded(
            child: _hasLoadedPage
                ? WebViewWidget(controller: _controller)
                : _buildEmptyGuide(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // WB_SPEC_235 跟进 §1-4：主按钮「抓取本页课表」= 轻点档
        // 复审 O1：补 enableFeedback: false 防双写
        enableFeedback: false,
        onPressed: (!_hasLoadedPage || _extracting)
            ? null
            : () {
                AppHaptics.tap();
                _extract();
              },
        icon: _extracting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download_for_offline_outlined),
        label: Text(_extracting ? '正在抓取…' : '抓取本页课表'),
      ),
    );
  }

  /// 未加载页面时的占位引导视图（initialUrl: null 手动输入模式）
  Widget _buildEmptyGuide(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '请在上方地址栏输入学校教务系统网址',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '直接输入域名即可（例如 jwxt.xxx.edu.cn），登录并打开课表页后点击「抓取本页课表」',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
