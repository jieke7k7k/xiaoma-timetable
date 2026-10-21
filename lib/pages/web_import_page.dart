import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/web_schedule_parser.dart';

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
  var _loading = 0; // 0-100，100 或 0 表示不在加载
  var _extracting = false;
  String? _hint;

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
  return JSON.stringify({ title: document.title, tables: out });
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
            if (mounted) setState(() => _loading = 0);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = 100);
          },
        ),
      )
      ..loadRequest(Uri.parse(_defaultUrl));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
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
    setState(() {
      _extracting = true;
      _hint = null;
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
      if (!mounted) return;
      if (result.courses.isEmpty) {
        setState(() {
          _hint = result.tablesFound == 0
              ? '当前页面没找到课表表格。请先登录教务系统、打开「学生课表」页面，再点抓取。'
              : '找到了 ${result.tablesFound} 个表格、${result.cellsScanned} 个单元格，'
                    '但没认出课程。请确认打开的是课表页面；若已是课表页，'
                    '可能是该校格式暂未适配——把课表页截图发我，我来适配。';
        });
        return;
      }
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() => _hint = '抓取失败：$e。请确认页面加载完成后再试一次。');
      }
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
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
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
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
          if (_hint != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_hint!, style: const TextStyle(fontSize: 13)),
            ),
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
