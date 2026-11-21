import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:xiaoma_timetable/pages/web_import_page.dart';

/// 轻量假平台实现：仅记录 loadRequest 是否被调用，避免单测触发原生通道
class _FakeWebViewPlatform extends WebViewPlatform {
  final List<Uri> loadedUris = [];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params, loadedUris);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakePlatformWebViewWidget(params);
  }
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  final List<Uri> loadedUris;

  _FakePlatformWebViewController(super.params, this.loadedUris)
      : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loadedUris.add(params.uri);
  }
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  /// 手动泵法：不调 pumpAndSettle——initialUrl 为 null 时 initState 会自动聚焦
  /// 地址栏，光标闪烁动画会让 pumpAndSettle 永远等不到 settle。
  Future<void> pumpFrames(WidgetTester tester, {int rounds = 5}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('WebImportPage(initialUrl: null) 不自动加载且显示占位引导', (tester) async {
    final fakePlatform = _FakeWebViewPlatform();
    WebViewPlatform.instance = fakePlatform;

    await tester.pumpWidget(
      const MaterialApp(
        home: WebImportPage(semesterId: 1, initialUrl: null),
      ),
    );
    await pumpFrames(tester);

    // 不自动加载任何页面
    expect(fakePlatform.loadedUris, isEmpty);
    // 显示占位引导文案
    expect(find.text('请在上方地址栏输入学校教务系统网址'), findsOneWidget);
    // 「抓取本页课表」未加载页面时禁用
    final fab = tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.onPressed, isNull);
  });

  testWidgets('WebImportPage(initialUrl: 具体网址) 自动加载该网址', (tester) async {
    final fakePlatform = _FakeWebViewPlatform();
    WebViewPlatform.instance = fakePlatform;

    await tester.pumpWidget(
      const MaterialApp(
        home: WebImportPage(
          semesterId: 1,
          initialUrl: 'https://jwxt.zjnu.edu.cn/',
        ),
      ),
    );
    await pumpFrames(tester);

    expect(fakePlatform.loadedUris.length, 1);
    expect(
      fakePlatform.loadedUris.first.toString(),
      'https://jwxt.zjnu.edu.cn/',
    );
    // 已加载页面，占位引导不出现
    expect(find.text('请在上方地址栏输入学校教务系统网址'), findsNothing);
  });
}
