import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/services/apk_download_service.dart';
import 'package:xiaoma_timetable/services/channel_service.dart';

/// 轻量假 HttpClient：按预设的响应序列逐个返回，用于验证进度、续传与失败路径。
class _FakeResponseSpec {
  final int statusCode;
  final List<List<int>> chunks;

  /// 覆盖 response.contentLength（206 时为剩余字节数；-1 表示服务器未返回长度）。
  final int? contentLengthOverride;

  /// 覆盖响应体流（中途取消测试用 StreamController 精确控制投递时机）。
  final Stream<List<int>>? stream;

  const _FakeResponseSpec(
    this.statusCode,
    this.chunks, {
    this.contentLengthOverride,
    this.stream,
  });
}

class _FakeHttpClient implements HttpClient {
  final List<_FakeResponseSpec> specs;
  int requestCount = 0;

  /// close() 后为 true：真实 HttpClient close 后 getUrl 抛异常，
  /// Fake 也照此建模（DeepSeek 复审 P1-6），否则 416 测试会假绿。
  bool _closed = false;

  /// 每次 close() 时记录该请求的 Range 头（无则为 null）
  final List<String?> rangeHeaders = [];

  _FakeHttpClient({required this.specs});

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (_closed) {
      // 真实 HttpClient close 后 getUrl 抛 HttpException（无公开的
      // HttpClientException 类，此处按真实行为建模）。
      throw HttpException('HttpClient is closed', uri: url);
    }
    if (requestCount >= specs.length) {
      // DeepSeek 复审 P1-7：请求数超预期时直接报错，别静默复用最后一个 spec。
      throw StateError(
        'unexpected request #$requestCount (only ${specs.length} specs)',
      );
    }
    final spec = specs[requestCount];
    requestCount++;
    return _FakeHttpClientRequest(
      spec: spec,
      onClose: (range) => rangeHeaders.add(range),
    );
  }

  @override
  void close({bool force = false}) {
    _closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final _FakeResponseSpec spec;
  final void Function(String?) onClose;

  _FakeHttpClientRequest({required this.spec, required this.onClose});

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    onClose((headers as _FakeHttpHeaders).valueOf('range'));
    return _FakeHttpClientResponse(
      chunks: spec.chunks,
      statusCode: spec.statusCode,
      contentLengthOverride: spec.contentLengthOverride,
      stream: spec.stream,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, Object> _map = {};

  String? valueOf(String name) {
    final v = _map[name.toLowerCase()];
    return v is String ? v : v?.toString();
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final List<List<int>> chunks;
  final int? contentLengthOverride;
  final Stream<List<int>>? stream;

  @override
  final int statusCode;

  _FakeHttpClientResponse({
    required this.chunks,
    required this.statusCode,
    this.contentLengthOverride,
    this.stream,
  });

  @override
  int get contentLength =>
      contentLengthOverride ??
      chunks.fold<int>(0, (sum, c) => sum + c.length);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return (stream ?? Stream<List<int>>.fromIterable(chunks)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 以 PK 魔数开头的假 APK 内容（1000 字节），过完整性校验。
List<List<int>> _pkChunks() => [
  [0x50, 0x4B, ...List<int>.filled(398, 1)],
  List<int>.filled(600, 2),
];

void main() {
  group('ApkDownloadService 下载进度与文件命名', () {
    test('mock HttpClient：正确回调下载进度并落盘为带版本号的 APK', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_test');
      addTearDown(() => tempDir.delete(recursive: true));

      final progressEvents = <ApkDownloadProgress>[];

      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [_FakeResponseSpec(HttpStatus.ok, _pkChunks())],
        ),
        getCacheDir: () async => tempDir,
      );

      final file = await service.downloadApk(
        url:
            'https://github.com/jieke7k7k/xiaoma-timetable/releases/download/v2.11.0/xiaomakebiao_v2.11.0.apk',
        version: '2.11.0',
        onProgress: progressEvents.add,
      );

      expect(await file.exists(), isTrue);
      expect(file.path.endsWith('apk_updates/xiaomakebiao_v2.11.0.apk'), isTrue);
      expect(await file.length(), 1000);

      expect(progressEvents.length, 3);
      expect(progressEvents[0].receivedBytes, 0);
      expect(progressEvents[1].receivedBytes, 400);
      expect(progressEvents[1].percentText, '40%');
      expect(progressEvents[2].receivedBytes, 1000);
      expect(progressEvents[2].percentText, '100%');
    });

    test('FileProvider URI 格式符合 Android 规范', () {
      final fileName = ApkDownloadService.buildApkFileName('2.11.0');
      final uri = ApkDownloadService.buildExpectedFileProviderUri(fileName);

      expect(uri.scheme, 'content');
      expect(uri.host, 'com.jieke.xiaomakebiao.fileprovider');
      expect(uri.path, '/apk_updates/xiaomakebiao_v2.11.0.apk');
    });

    test('416 续传被拒：删 .part 从头重下，不带 Range', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_416');
      addTearDown(() => tempDir.delete(recursive: true));
      final updateDir = Directory('${tempDir.path}/apk_updates');
      await updateDir.create(recursive: true);
      // 残留的旧 .part（10 字节），第一次请求会带 Range: bytes=10-
      final partFile = File(
        '${updateDir.path}/xiaomakebiao_v2.11.0.apk.part',
      );
      await partFile.writeAsBytes(List<int>.filled(10, 9));

      final client = _FakeHttpClient(specs: [
        const _FakeResponseSpec(HttpStatus.requestedRangeNotSatisfiable, []),
        _FakeResponseSpec(HttpStatus.ok, _pkChunks()),
      ]);
      final service = ApkDownloadService(
        httpClientFactory: () => client,
        getCacheDir: () async => tempDir,
      );

      final file = await service.downloadApk(
        url: 'https://example.com/x.apk',
        version: '2.11.0',
        onProgress: (_) {},
      );

      expect(client.requestCount, 2);
      expect(client.rangeHeaders[0], 'bytes=10-');
      expect(client.rangeHeaders[1], isNull);
      expect(await file.length(), 1000);
      expect(await partFile.exists(), isFalse);
    });

    test('非 200/206 状态码按失败处理', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_404');
      addTearDown(() => tempDir.delete(recursive: true));
      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [const _FakeResponseSpec(HttpStatus.notFound, [])],
        ),
        getCacheDir: () async => tempDir,
      );

      await expectLater(
        service.downloadApk(
          url: 'https://example.com/x.apk',
          version: '2.11.0',
          onProgress: (_) {},
        ),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('下载内容不是 APK（无 PK 魔数）时拒绝落盘', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_bad');
      addTearDown(() => tempDir.delete(recursive: true));
      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [
            _FakeResponseSpec(HttpStatus.ok, [
              List<int>.filled(100, 1),
            ]),
          ],
        ),
        getCacheDir: () async => tempDir,
      );

      await expectLater(
        service.downloadApk(
          url: 'https://example.com/x.apk',
          version: '2.11.0',
          onProgress: (_) {},
        ),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.message,
            'message',
            contains('不是有效的安装包'),
          ),
        ),
      );
    });

    test('取消下载抛 isCancelled 的异常', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_cancel');
      addTearDown(() => tempDir.delete(recursive: true));
      final token = ApkDownloadCancelToken()..cancel();
      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [_FakeResponseSpec(HttpStatus.ok, _pkChunks())],
        ),
        getCacheDir: () async => tempDir,
      );

      await expectLater(
        service.downloadApk(
          url: 'https://example.com/x.apk',
          version: '2.11.0',
          cancelToken: token,
          onProgress: (_) {},
        ),
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.isCancelled,
            'isCancelled',
            isTrue,
          ),
        ),
      );
    });

    test('下载中途取消：立即抛 isCancelled，.part 留下已刷盘的前缀字节可续传', () async {
      // DeepSeek 复审 P1-1/P2-7：旧实现里取消后 completer 永远等不到
      // onDone/onError，下载 Future 会挂起；5 秒超时即判失败。
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_midcancel');
      addTearDown(() => tempDir.delete(recursive: true));
      final controller = StreamController<List<int>>();
      addTearDown(() => controller.close());
      final firstChunkDelivered = Completer<void>();
      final token = ApkDownloadCancelToken();
      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [
            _FakeResponseSpec(
              HttpStatus.ok,
              const [],
              stream: controller.stream,
            ),
          ],
        ),
        getCacheDir: () async => tempDir,
      );

      final future = service.downloadApk(
        url: 'https://example.com/x.apk',
        version: '2.11.0',
        cancelToken: token,
        onProgress: (p) {
          if (p.receivedBytes > 0 && !firstChunkDelivered.isCompleted) {
            firstChunkDelivered.complete();
          }
        },
      );
      controller.add(_pkChunks()[0]);
      await firstChunkDelivered.future;
      token.cancel();

      await expectLater(
        future,
        throwsA(
          isA<ApkDownloadException>().having(
            (e) => e.isCancelled,
            'isCancelled',
            isTrue,
          ),
        ),
      ).timeout(const Duration(seconds: 5));

      // .part 留下已刷盘的 400 字节干净前缀（下次可断点续传）。
      final partFile = File(
        '${tempDir.path}/apk_updates/xiaomakebiao_v2.11.0.apk.part',
      );
      expect(await partFile.exists(), isTrue);
      expect(await partFile.length(), 400);
      final head = await partFile.openRead(0, 2).first;
      expect(head, [0x50, 0x4B]);
    });

    test('206 断点续传：带 Range 请求，追加后文件完整', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_206');
      addTearDown(() => tempDir.delete(recursive: true));
      final updateDir = Directory('${tempDir.path}/apk_updates');
      await updateDir.create(recursive: true);
      final partFile = File(
        '${updateDir.path}/xiaomakebiao_v2.11.0.apk.part',
      );
      await partFile.writeAsBytes(_pkChunks()[0]); // 已有 400 字节前缀

      final client = _FakeHttpClient(specs: [
        _FakeResponseSpec(HttpStatus.partialContent, [_pkChunks()[1]]),
      ]);
      final service = ApkDownloadService(
        httpClientFactory: () => client,
        getCacheDir: () async => tempDir,
      );
      final file = await service.downloadApk(
        url: 'https://example.com/x.apk',
        version: '2.11.0',
        onProgress: (_) {},
      );

      expect(client.requestCount, 1);
      expect(client.rangeHeaders[0], 'bytes=400-');
      expect(await file.length(), 1000);
      final bytes = await file.readAsBytes();
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
      expect(bytes.sublist(400), List<int>.filled(600, 2));
    });

    test('contentLength 为 -1 时不确定进度仍可下完', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_nolen');
      addTearDown(() => tempDir.delete(recursive: true));
      final progressEvents = <ApkDownloadProgress>[];
      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [
            _FakeResponseSpec(
              HttpStatus.ok,
              _pkChunks(),
              contentLengthOverride: -1,
            ),
          ],
        ),
        getCacheDir: () async => tempDir,
      );
      final file = await service.downloadApk(
        url: 'https://example.com/x.apk',
        version: '2.11.0',
        onProgress: progressEvents.add,
      );

      expect(await file.length(), 1000);
      expect(progressEvents.last.totalBytes, -1);
      expect(progressEvents.last.fraction, isNull);
      expect(progressEvents.last.percentText, isNull);
    });

    test('同版本缓存包无 PK 魔数时不复用，重新下载', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_badcache');
      addTearDown(() => tempDir.delete(recursive: true));
      final updateDir = Directory('${tempDir.path}/apk_updates');
      await updateDir.create(recursive: true);
      final staleFile = File('${updateDir.path}/xiaomakebiao_v2.11.0.apk');
      await staleFile.writeAsBytes(List<int>.filled(500, 7)); // 损坏的旧包

      final client = _FakeHttpClient(specs: [
        _FakeResponseSpec(HttpStatus.ok, _pkChunks()),
      ]);
      final service = ApkDownloadService(
        httpClientFactory: () => client,
        getCacheDir: () async => tempDir,
      );
      final file = await service.downloadApk(
        url: 'https://example.com/x.apk',
        version: '2.11.0',
        onProgress: (_) {},
      );

      expect(client.requestCount, 1);
      expect(await file.length(), 1000);
    });

    test('发起新下载前清理其它版本的旧包', () async {
      final tempDir = await Directory.systemTemp.createTemp('apk_dl_clean');
      addTearDown(() => tempDir.delete(recursive: true));
      final updateDir = Directory('${tempDir.path}/apk_updates');
      await updateDir.create(recursive: true);
      final staleApk = File('${updateDir.path}/xiaomakebiao_v9.9.9.apk');
      await staleApk.writeAsBytes([1, 2, 3]);
      final stalePart = File(
        '${updateDir.path}/xiaomakebiao_v9.9.9.apk.part',
      );
      await stalePart.writeAsBytes([1, 2, 3]);

      final service = ApkDownloadService(
        httpClientFactory: () => _FakeHttpClient(
          specs: [_FakeResponseSpec(HttpStatus.ok, _pkChunks())],
        ),
        getCacheDir: () async => tempDir,
      );
      await service.downloadApk(
        url: 'https://example.com/x.apk',
        version: '2.11.0',
        onProgress: (_) {},
      );

      expect(await staleApk.exists(), isFalse);
      expect(await stalePart.exists(), isFalse);
    });
  });

  group('parseChannel 回归', () {
    test('正确解析 GitHub Release 直链作为 downloadUrl', () {
      const sampleChannelJson = '''
      {
        "latest": {
          "versionName": "2.11.0",
          "versionCode": 47,
          "notes": "2.11.0 更新说明",
          "downloadUrl": "https://github.com/jieke7k7k/xiaoma-timetable/releases/download/v2.11.0/xiaomakebiao_v2.11.0.apk",
          "releaseUrl": "https://github.com/jieke7k7k/xiaoma-timetable/releases/tag/v2.11.0"
        }
      }
      ''';

      final parsed = parseChannel(sampleChannelJson);
      expect(parsed, isNotNull);
      expect(parsed!.latest?.versionName, '2.11.0');
      expect(parsed.latest?.versionCode, 47);
      expect(
        parsed.latest?.downloadUrl,
        'https://github.com/jieke7k7k/xiaoma-timetable/releases/download/v2.11.0/xiaomakebiao_v2.11.0.apk',
      );
      expect(
        parsed.latest?.releaseUrl,
        'https://github.com/jieke7k7k/xiaoma-timetable/releases/tag/v2.11.0',
      );
    });
  });
}
