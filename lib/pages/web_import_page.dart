import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ui/app_styles.dart';
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
  const WebImportPage({super.key, required this.semesterId});

  final int semesterId;

  @override
  State<WebImportPage> createState() => _WebImportPageState();
}

class _WebImportPageState extends State<WebImportPage> {
  /// 默认入口：浙师大教务系统（可在地址栏改成自己学校的）
  static const _defaultUrl = 'https://jwxt.zjnu.edu.cn/';

  late final WebViewController _controller;
  final _urlCtrl = TextEditingController(text: _defaultUrl);
  final _urlFocus = FocusNode();
  var _loading = 0; // 0-100，100 或 0 表示不在加载
  var _extracting = false;

  /// 失败判定结果（null = 当前没有提示）；6 类之外的兜底走 [_fallbackHint]
  WebImportDiagnosis? _diagnosis;

  /// 兜底提示（6 类都不命中时用，沿用原有两句文案）
  String? _fallbackHint;

  /// 主框加载失败置位（WB_SPEC_231 第 5.2 节）：只在 onWebResourceError 里
  /// 且 isForMainFrame 为真时置位，下一次 onPageStarted 清零
  var _mainFrameError = false;

  /// 抓取脚本：遍历主文档与同源 iframe 里的所有表格，
  /// 逐行回传单元格文本与跨行/跨列，回传 JSON 字符串
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
    diag: {
      readyState: document.readyState,
      url: location.href,
      title: document.title,
      hasPassword: document.querySelectorAll('input[type="password"]').length > 0,
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      )
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
      )
      ..loadRequest(Uri.parse(_defaultUrl));
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
    _controller.loadRequest(Uri.parse(url));
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
              ? '当前页面没找到课表表格。请先登录教务系统、打开「学生课表」页面，再点抓取。'
              : '找到了 ${result.tablesFound} 个表格、${result.cellsScanned} 个单元格，'
                    '但没认出课程。请确认打开的是课表页面；若已是课表页，'
                    '可能是该校格式暂未适配——把课表页截图发我，我来适配。';
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
        _diagnosis = const WebImportDiagnosis(WebImportFailure.layoutUnsupported);
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
          message: '把课表页截图发我（微信或邮件都行），我来适配贵校的排版格式。',
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
                    onPressed: () => _runAction(action),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 32),
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
            onPressed: () async {
              if (await _controller.canGoBack()) _controller.goBack();
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 18),
            tooltip: '前进',
            onPressed: () async {
              if (await _controller.canGoForward()) _controller.goForward();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
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
                FilledButton(onPressed: _go, child: const Text('打开')),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '① 在学校页面里登录（账号密码只填在学校网页，App 不保存）'
                ' → ② 打开「学生课表」页 → ③ 点右下角「抓取本页课表」',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_loading > 0 && _loading < 100)
            LinearProgressIndicator(value: _loading / 100),
          if (_diagnosis != null || _fallbackHint != null) _hintBox(context),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _extracting ? null : _extract,
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
}
