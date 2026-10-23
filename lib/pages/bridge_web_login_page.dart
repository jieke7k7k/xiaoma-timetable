import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// AI 桥设备码的 App 内嵌授权页（2.0.4，WB_SPEC_204）
///
/// 背景（真机实测）：GitHub 输码页是「每格 maxlength=1」的 8 个单字符输入框，
/// 在手机浏览器里粘贴整串设备码只会进第一个格（剪贴板逐字提交被每格截断），
/// 一键粘贴不成立。解法：把输码页搬进 App 的 WebView，页面加载完后用 JS
/// 把 8 位码逐格自动填好，用户只需要点 Continue 和授权。
///
/// 职责边界：本页只负责「打开授权页 + 自动填码」。登录、选账号、输码、授权
/// 全流程都在这个 WebView 里走完（cookie 在 WebView 内保持）；轮询换令牌
/// 仍由桥页 [BridgePage] 的定时器负责，本页不碰令牌。
class BridgeWebLoginPage extends StatefulWidget {
  const BridgeWebLoginPage({
    super.key,
    required this.userCode,
    required this.verificationUri,
  });

  /// 设备码 user_code（含连字符，如 ABCD-1234；填码时再去掉连字符）
  final String userCode;

  /// GitHub 设备码验证页地址（为空时回退官方地址）
  final String verificationUri;

  @override
  State<BridgeWebLoginPage> createState() => _BridgeWebLoginPageState();
}

class _BridgeWebLoginPageState extends State<BridgeWebLoginPage> {
  /// 官方设备码验证页（入参地址为空时的兜底）
  static const _fallbackUri = 'https://github.com/login/device';

  /// 主流 Chrome Android 的 UA：GitHub 会按 UA 给 WebView 推降级页，
  /// 伪装成手机 Chrome 才能拿到完整的设备码流程页面
  static const _chromeAndroidUa =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  late final WebViewController _controller;

  /// 加载进度 0-100（0 或 100 表示不在加载，只画细进度条）
  var _progress = 0;

  /// 已成功填过码的「页面 URL + 设备码」组合（本页实例内只填一次）
  ///
  /// 防重复填：只有 JS 真的把 8 格都填上（回传 `filled`）才记 key；
  /// 没填上（登录页/选账号页/格数不对）不记，下一次页面加载完还会再试。
  /// 用户手改某格后页面局部刷新（同一 URL 再次 onPageFinished）时，
  /// key 已存在直接跳过，不会把用户的手改覆盖掉。
  final Set<String> _filledKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_chromeAndroidUa)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageFinished: _onPageFinished,
        ),
      )
      ..loadRequest(Uri.parse(_initialUri));
  }

  /// 打开地址：入参为准，为空回退官方设备码页
  String get _initialUri =>
      widget.verificationUri.isEmpty ? _fallbackUri : widget.verificationUri;

  /// 每次页面加载完成：试一次自动填码（守卫见 [_filledKeys]）
  void _onPageFinished(String url) {
    final key = '$url|${widget.userCode}';
    if (_filledKeys.contains(key)) return;
    unawaited(_autoFill(key));
  }

  /// 注入填码 JS 并按回传结果记守卫；任何异常都静默吞掉，不影响用户手动输入
  /// （WebView 里正常打字有 GitHub 自带的自动跳格）
  Future<void> _autoFill(String key) async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _buildFillJs(widget.userCode),
      );
      var text = raw.toString();
      // Android 端回传的是 JSON 编码过的字符串，需要先解一层
      try {
        final once = jsonDecode(text);
        if (once is String) text = once;
      } catch (_) {
        // 本身就是普通文本则直接用
      }
      if (text == 'filled' && mounted) {
        _filledKeys.add(key);
      }
    } catch (_) {
      // JS 注入失败/页面已销毁等情况一律静默，靠用户手动输入兜底
    }
  }

  /// 生成自动填码 JS（设备码以字面量形式带入脚本）
  ///
  /// 规则（WB_SPEC_204）：
  /// - 只找「可见的、单字符文本输入框」：type 为 text/tel 或无 type，
  ///   且 maxlength<=2；数量恰好为 8 才填，否则什么都不做
  ///   （比如还在登录页/选账号页，等下一次页面加载完再触发）。
  /// - 填法：去掉连字符得到 8 个字符，逐格用原生 value setter 赋值
  ///   （绕过前端框架包装过的 value 属性），并依次派发 input（bubbles）
  ///   与 change 事件，保证 GitHub 的前端脚本能感知。
  /// - 回传 `filled` 表示填好，`skip` 表示格数不对，其它值表示异常。
  static String _buildFillJs(String userCode) {
    // 只留字母数字：连字符与任何意外字符都剔除，正好拿 8 位逐格填
    final code = userCode.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return '''
(function () {
  try {
    var boxes = [];
    var inputs = document.querySelectorAll('input');
    for (var i = 0; i < inputs.length; i++) {
      var el = inputs[i];
      var type = (el.getAttribute('type') || 'text').toLowerCase();
      if (type !== 'text' && type !== 'tel') continue;
      var maxAttr = el.getAttribute('maxlength');
      if (maxAttr === null) continue;
      var maxLen = parseInt(maxAttr, 10);
      if (isNaN(maxLen) || maxLen > 2) continue;
      // 可见性：有实际尺寸且未被隐藏
      var rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) continue;
      var style = window.getComputedStyle(el);
      if (style.visibility === 'hidden' || style.display === 'none') continue;
      boxes.push(el);
    }
    if (boxes.length !== 8) return 'skip';
    var chars = '$code'.split('');
    if (chars.length !== 8) return 'badcode';
    var setter = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      'value'
    ).set;
    for (var j = 0; j < boxes.length; j++) {
      setter.call(boxes[j], chars[j]);
      boxes[j].dispatchEvent(new Event('input', { bubbles: true }));
      boxes[j].dispatchEvent(new Event('change', { bubbles: true }));
    }
    return 'filled';
  } catch (e) {
    return 'error';
  }
})()
''';
  }

  /// 在外部浏览器打开同一地址（兜底路径，与桥页次要按钮同款）
  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_initialUri);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打不开浏览器，请手动访问 $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 授权'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '关闭',
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '在浏览器打开',
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress > 0 && _progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          Expanded(child: WebViewWidget(controller: _controller)),
          // 底部小字提示：授权完成后怎么回到 App
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '授权完成后关闭本页返回，App 会自动完成连接。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
