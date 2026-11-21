import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 下载进度快照
class ApkDownloadProgress {
  final int receivedBytes;

  /// 总字节数；服务器未返回 Content-Length 时为 -1
  final int totalBytes;

  const ApkDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// 0.0 ~ 1.0；未知总量时返回 null（UI 显示不确定进度条）
  double? get fraction {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// 百分比文本（如 "42%"），未知总量时返回 null
  String? get percentText {
    final f = fraction;
    if (f == null) return null;
    return '${(f * 100).floor()}%';
  }

  /// 已下 / 总量格式化文案（如 "12.4 MB / 28.6 MB"）
  String get sizeText {
    final rec = _formatBytes(receivedBytes);
    if (totalBytes <= 0) return rec;
    return '$rec / ${_formatBytes(totalBytes)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 下载取消令牌
class ApkDownloadCancelToken {
  bool _isCancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _onCancel?.call();
  }

  void _attach(void Function() onCancel) {
    _onCancel = onCancel;
    if (_isCancelled) {
      onCancel();
    }
  }
}

/// 下载异常（区分用户主动取消与网络/IO 失败）
class ApkDownloadException implements Exception {
  final String message;
  final bool isCancelled;

  const ApkDownloadException(this.message, {this.isCancelled = false});

  @override
  String toString() => message;
}

/// App 内安装包下载与调起系统安装服务（WB_SPEC_252）
class ApkDownloadService {
  static const String installerChannelName =
      'com.jieke.xiaomakebiao/apk_installer';
  static const String fileProviderAuthority =
      'com.jieke.xiaomakebiao.fileprovider';
  static const String cacheSubDirName = 'apk_updates';

  static const MethodChannel _defaultChannel =
      MethodChannel(installerChannelName);

  final HttpClient Function() _httpClientFactory;
  final Future<Directory> Function() _getCacheDir;
  final MethodChannel _installerChannel;

  ApkDownloadService({
    HttpClient Function()? httpClientFactory,
    Future<Directory> Function()? getCacheDir,
    MethodChannel? installerChannel,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _getCacheDir = getCacheDir ?? getTemporaryDirectory,
       _installerChannel = installerChannel ?? _defaultChannel;

  /// 构造带版本号的安装包文件名，避免与旧包混淆
  static String buildApkFileName(String version) {
    final safeVersion = version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return 'xiaomakebiao_v$safeVersion.apk';
  }

  /// 构造与 Android FileProvider 一致的 content:// URI（供单测与校验使用）。
  /// 注意：FileProvider 生成的 URI 第一段是 file_paths.xml 里 <cache-path>
  /// 的 name（apk_updates），必须与 cacheSubDirName 保持一致，否则
  /// getUriForFile 会抛 IllegalArgumentException。
  static Uri buildExpectedFileProviderUri(String fileName) {
    return Uri(
      scheme: 'content',
      host: fileProviderAuthority,
      path: '/$cacheSubDirName/$fileName',
    );
  }

  /// 下载安装包到缓存目录，支持 302 重定向、进度回调、取消与断点续传
  Future<File> downloadApk({
    required String url,
    required String version,
    required void Function(ApkDownloadProgress progress) onProgress,
    ApkDownloadCancelToken? cancelToken,
    Duration connectionTimeout = const Duration(seconds: 20),
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const ApkDownloadException('下载地址无效');
    }

    HttpClient? client;
    IOSink? sink;
    StreamSubscription<List<int>>? subscription;
    // DeepSeek 复审 P1-5 相关（2026-11-22 我自查补出）：中途取消时
    // subscription.cancel() 会 detach 监听器，流的 onDone/onError 不会再
    // 触发，若不手动补完 completer，await completer.future 会永远挂起。
    Completer<void>? activeCompleter;
    // 供 on FileSystemException 清理残余 .part 用（partFile 本体在 try 内
    // 声明，catch 里不可见，故另留一个外层引用）。
    File? partFileForCleanup;

    try {
      final cacheRoot = await _getCacheDir();
      final updateDir = Directory('${cacheRoot.path}/$cacheSubDirName');
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }

      final fileName = buildApkFileName(version);
      final finalFile = File('${updateDir.path}/$fileName');
      final partFile = File('${updateDir.path}/$fileName.part');
      partFileForCleanup = partFile;

      // 若同版本完整包已在缓存中，直接复用——先校验 PK 魔数，防上次落盘
      // 损坏的包被直接复用（DeepSeek 复审「已核查」一节指出该缺口）。
      if (await finalFile.exists()) {
        final len = await finalFile.length();
        if (len > 0 && await _startsWithPkMagic(finalFile)) {
          onProgress(ApkDownloadProgress(receivedBytes: len, totalBytes: len));
          return finalFile;
        }
        try {
          await finalFile.delete();
        } catch (_) {
          // 删不掉就继续走下载流程覆盖
        }
      }

      // WB_SPEC_252 §3：发起新下载前清理其它版本的旧包/残片，只留本版本。
      await for (final e in updateDir.list()) {
        if (e is File &&
            e.path != finalFile.path &&
            e.path != partFile.path) {
          try {
            await e.delete();
          } catch (_) {
            // 删不掉的旧文件不影响本次下载
          }
        }
      }

      var resumeFrom = await partFile.exists() ? await partFile.length() : 0;
      client = _httpClientFactory()
        ..connectionTimeout = connectionTimeout
        ..idleTimeout = idleTimeout;

      cancelToken?._attach(() {
        subscription?.cancel();
        client?.close(force: true);
        final c = activeCompleter;
        if (c != null && !c.isCompleted) {
          c.completeError(
            const ApkDownloadException('已取消下载', isCancelled: true),
          );
        }
      });

      // 最多尝试两次：第一次 416（断点续传被拒）时删 .part 从头重下。
      for (var attempt = 0; ; attempt++) {
        final request = await client.getUrl(uri);
        // 显式开启重定向跟随（GitHub Release 直链会 302 到对象存储域名）
        request.followRedirects = true;
        request.maxRedirects = 8;

        if (resumeFrom > 0) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=$resumeFrom-',
          );
        }

        final response = await request.close();

        if (cancelToken?.isCancelled == true) {
          throw const ApkDownloadException('已取消下载', isCancelled: true);
        }

        // WB_SPEC_252 §3：416 表示本地 .part 已损坏或比新包还大——
        // 删掉从头重下，只认 200/206 会永久卡死。
        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
            resumeFrom > 0) {
          await response.drain<void>();
          if (attempt == 0) {
            try {
              await partFile.delete();
            } catch (_) {
              // 删不掉就按从头写覆盖
            }
            resumeFrom = 0;
            continue;
          }
          throw const ApkDownloadException('断点续传被服务器拒绝，请重试');
        }

        final isPartial = response.statusCode == HttpStatus.partialContent;
        final isOk = response.statusCode == HttpStatus.ok;
        if (!isOk && !isPartial) {
          throw ApkDownloadException(
            '服务器返回异常状态码（${response.statusCode}）',
          );
        }

        // 服务器支持 206 续传时追加写入；否则从头覆盖写入
        var received = isPartial ? resumeFrom : 0;
        final contentLength = response.contentLength;
        final totalBytes = contentLength > 0
            ? (isPartial ? resumeFrom + contentLength : contentLength)
            : -1;

        sink = partFile.openWrite(
          mode: isPartial ? FileMode.append : FileMode.write,
        );
        onProgress(
          ApkDownloadProgress(receivedBytes: received, totalBytes: totalBytes),
        );

        final completer = Completer<void>();
        activeCompleter = completer;
        subscription = response.listen(
          (chunk) {
            if (cancelToken?.isCancelled == true) {
              subscription?.cancel();
              if (!completer.isCompleted) {
                completer.completeError(
                  const ApkDownloadException('已取消下载', isCancelled: true),
                );
              }
              return;
            }
            sink!.add(chunk);
            received += chunk.length;
            onProgress(
              ApkDownloadProgress(receivedBytes: received, totalBytes: totalBytes),
            );
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object err) {
            if (!completer.isCompleted) completer.completeError(err);
          },
          cancelOnError: true,
        );

        await completer.future;
        activeCompleter = null;
        await sink.flush();
        await sink.close();
        sink = null;

        if (cancelToken?.isCancelled == true) {
          throw const ApkDownloadException('已取消下载', isCancelled: true);
        }

        // WB_SPEC_252 §3：落盘前完整性校验——总量已知时字节数必须对上，
        // 且文件头必须是 APK 的 ZIP 魔数 PK，否则不调安装器。
        // 内存里的 received 与磁盘长度双重核对（DeepSeek 复审 P1-2）。
        final downloadedLen = await partFile.length();
        if (totalBytes > 0 &&
            (downloadedLen != totalBytes || received != totalBytes)) {
          throw const ApkDownloadException('下载不完整，请重试');
        }
        final raf = await partFile.open();
        final header = await raf.read(2);
        await raf.close();
        if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
          throw const ApkDownloadException('下载的文件不是有效的安装包，请重试');
        }

        // 原子重命名为最终 APK
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        return await partFile.rename(finalFile.path);
      }
    } on ApkDownloadException {
      rethrow;
    } on SocketException {
      // 取消时 _attach 回调会 close client，正在连接的 getUrl 会以
      // SocketException/HttpClientException 收尾——先判取消再报网络错
      // （否则预取消/连接中取消会误报「网络连接失败」）。
      if (cancelToken?.isCancelled == true) {
        throw const ApkDownloadException('已取消下载', isCancelled: true);
      }
      throw const ApkDownloadException('网络连接失败，请检查网络后重试');
    } on TimeoutException {
      if (cancelToken?.isCancelled == true) {
        throw const ApkDownloadException('已取消下载', isCancelled: true);
      }
      throw const ApkDownloadException('下载超时，请稍后重试');
    } on HttpException catch (e) {
      if (cancelToken?.isCancelled == true) {
        throw const ApkDownloadException('已取消下载', isCancelled: true);
      }
      throw ApkDownloadException('下载连接异常：${e.message}');
    } on FileSystemException {
      // WB_SPEC_252 §3：写满时提示存储空间不足，并清理残余 .part。
      try {
        await partFileForCleanup?.delete();
      } catch (_) {
        // 删不掉不影响提示
      }
      throw const ApkDownloadException('存储空间不足，请清理后重试');
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        throw const ApkDownloadException('已取消下载', isCancelled: true);
      }
      throw ApkDownloadException('下载中断：$e');
    } finally {
      await subscription?.cancel();
      await sink?.close();
      client?.close(force: false);
    }
  }

  /// 文件头是否为 APK 的 ZIP 魔数 PK（缓存复用与落盘前校验共用）。
  static Future<bool> _startsWithPkMagic(File file) async {
    try {
      final raf = await file.open();
      final header = await raf.read(2);
      await raf.close();
      return header.length == 2 && header[0] == 0x50 && header[1] == 0x4B;
    } catch (_) {
      return false;
    }
  }

  /// 检查是否已授权「安装未知应用」
  Future<bool> canRequestPackageInstalls() async {
    final granted = await _installerChannel.invokeMethod<bool>(
      'canRequestPackageInstalls',
    );
    return granted ?? true;
  }

  /// 打开系统「安装未知应用」授权设置页
  Future<void> openUnknownSourcesSettings() async {
    await _installerChannel.invokeMethod<void>('openUnknownSourcesSettings');
  }

  /// 调起系统安装器安装指定路径的 APK，返回 FileProvider content URI 字符串
  Future<String?> installApk(String filePath) async {
    return _installerChannel.invokeMethod<String>(
      'installApk',
      {'filePath': filePath},
    );
  }
}
