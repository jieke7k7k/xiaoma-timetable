import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xiaoma_timetable/database/db_helper.dart';
import 'package:xiaoma_timetable/pages/bridge_page.dart';

/// 桥页设备码卡的按钮存在性/文案测试（2.0.4，WB_SPEC_204；2.0.5 更新文案）
///
/// 覆盖规格第 4 条「桥页按钮存在性测试要跟上」：主按钮
/// 「在 App 内打开并自动填码」、浏览器兜底按钮（2.0.5 起改 Custom Tab 共享登录，
/// 文案「在浏览器打开（共享登录，手动输码）」）、三步文案换新流程、
/// 2.0.3 的「复制代码」保留、2.0.5 的「共享登录要点补充」句存在。
///
/// WebView 内嵌页本身不测（平台限制，规格亦不强求）；这里用假 GitHub
/// （HttpOverrides）把设备码申请与轮询都接到本地内存响应上，让设备码卡
/// 能在 widget 测试里真实渲染出来。
void main() {
  HttpOverrides? savedOverrides;
  late Database db;

  setUpAll(() {
    // 与 note_dao_test 同款：内存库 + 共享 schema，桥页首屏读设置直接用
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = _FakeGithub();
  });

  tearDownAll(() {
    HttpOverrides.global = savedOverrides;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (d, v) => DbHelper.instance.createSchema(d),
      ),
    );
    DbHelper.instance.useDatabaseForTest(db);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('设备码卡：新主按钮/次要按钮/复制按钮与三步文案', (tester) async {
    // 桥页首屏有持续动画/轮询，pumpAndSettle 永远等不到静止，改用定步泵帧
    Future<void> pumpFrames() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // 首屏 _load 读 FFI 内存库（真实异步）：整段放进 runAsync 里启动，
    // 否则页面在假异步区里发起的查库永远等不到结果（一直转圈）
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: BridgePage()),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await pumpFrames();

    // 未连接态：点「连接 GitHub」→ 申请设备码（假 GitHub 立即返回）
    await tester.runAsync(() async {
      await tester.tap(find.text('连接 GitHub'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await pumpFrames();

    // 2.0.4 主按钮：App 内嵌打开并自动填码
    expect(find.text('在 App 内打开并自动填码'), findsOneWidget);
    // 浏览器兜底按钮 2.0.5 改 Custom Tab 共享登录并改名
    expect(find.text('在浏览器打开（共享登录，手动输码）'), findsOneWidget);
    // 2.0.3 的自动复制与「复制代码」按钮保留
    expect(find.text('复制代码'), findsOneWidget);
    // 大字设备码（假 GitHub 返回的 ABCD-1234，含连字符原样展示）
    expect(find.text('ABCD-1234'), findsOneWidget);

    // 三步说明换成新流程
    expect(find.text('点「在 App 内打开并自动填码」'), findsOneWidget);
    expect(
      find.text('在打开的页面里登录/确认账号，码已自动填好，点 Continue 并授权'),
      findsOneWidget,
    );
    expect(find.text('关闭页面返回，App 自动完成连接'), findsOneWidget);
    // 2.0.5 补充：浏览器方式（共享登录）要点说明存在
    expect(
      find.text('补充：浏览器方式打开后已是登录状态，手输 8 位码即可；'
          '粘贴只能填一格（GitHub 页面的限制），不想手输就用 App 内自动填码。'),
      findsOneWidget,
    );

    // 旧流程文案不再出现
    expect(find.text('去 GitHub 粘贴'), findsNothing);
    expect(find.text('在浏览器打开（手动输码）'), findsNothing);

    // 收尾：点「取消登录」停掉轮询定时器，避免测试挂起
    await tester.tap(find.text('取消登录'));
    await pumpFrames();
    expect(find.text('连接 GitHub'), findsOneWidget);
  });
}

/// 假的 GitHub：只回答设备码申请与轮询两个端点，不碰真网络。
///
/// 轮询恒返回 authorization_pending，定时器空转，不会真的换到令牌；
/// 测试末尾点「取消登录」取消定时器即可干净收场。
class _FakeGithub extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  void set connectionTimeout(Duration? duration) {}

  @override
  void close({bool force = false}) {}

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _FakeHttpRequest(_bodyFor(url));

  /// 设备码流程只走 postUrl；openUrl 留同款兜底，本测试用不到
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpRequest(_bodyFor(url));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  static ({int status, String body}) _bodyFor(Uri url) {
    if (url.path.contains('/login/device/code')) {
      return (
        status: 200,
        body: jsonEncode({
          'device_code': 'test-device-code',
          'user_code': 'ABCD-1234',
          'verification_uri': 'https://github.com/login/device',
          'interval': 5,
        }),
      );
    }
    // 轮询（/oauth/access_token）：一直 pending
    return (status: 200, body: jsonEncode({'error': 'authorization_pending'}));
  }
}

class _FakeHttpRequest implements HttpClientRequest {
  _FakeHttpRequest(this._response);

  final ({int status, String body}) _response;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void write(Object? object) {}

  @override
  Future<HttpClientResponse> close() async =>
      _FakeHttpResponse(_response.status, utf8.encode(_response.body));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 假的请求头：只接住 BridgeService 会用的 set 与 contentType 赋值
class _FakeHeaders implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpResponse(this.statusCode, this._bytes);

  @override
  final int statusCode;
  final List<int> _bytes;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.fromIterable([_bytes]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
