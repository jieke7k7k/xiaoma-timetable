import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaoma_timetable/services/apk_download_service.dart';
import 'package:xiaoma_timetable/widgets/update_download_dialog.dart';

/// 假下载服务：downloadApk 由测试手动放行/报错，授权与安装行为可控。
class _FakeDownloadService extends ApkDownloadService {
  int downloadCalls = 0;
  final List<Completer<File>> downloadCompleters = [];
  bool canInstall = true;
  int installCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<File> downloadApk({
    required String url,
    required String version,
    required void Function(ApkDownloadProgress progress) onProgress,
    ApkDownloadCancelToken? cancelToken,
    Duration connectionTimeout = const Duration(seconds: 20),
    Duration idleTimeout = const Duration(seconds: 30),
  }) {
    downloadCalls++;
    final completer = Completer<File>();
    downloadCompleters.add(completer);
    return completer.future;
  }

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<void> openUnknownSourcesSettings() async {
    openSettingsCalls++;
  }

  @override
  Future<String?> installApk(String filePath) async {
    installCalls++;
    return 'content://com.jieke.xiaomakebiao.fileprovider/apk_updates/x.apk';
  }
}

void main() {
  group('UpdateDownloadDialog（WB_SPEC_252 §2，DeepSeek 复审 P1-3/4/5）', () {
    // testWidgets 里真实 IO 直接 await 会永远卡死（假时钟不驱动真实事件
    // 循环），建临时目录/写文件一律走 tester.runAsync；清理用同步删除。
    Future<Directory> makeTempDir(WidgetTester tester, String prefix) async {
      final dir =
          await tester.runAsync(() => Directory.systemTemp.createTemp(prefix));
      return dir!;
    }

    Future<File> fakeApk(WidgetTester tester, Directory dir) async {
      final file = await tester.runAsync(() async {
        final f = File('${dir.path}/x.apk');
        await f.writeAsBytes([0x50, 0x4B]);
        return f;
      });
      return file!;
    }

    Future<void> pumpDialog(
      WidgetTester tester, {
      required _FakeDownloadService service,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateDownloadDialog(
              version: '2.11.0',
              downloadUrl: 'https://example.com/x.apk',
              downloadService: service,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('双击「去下载」只发起一次下载', (tester) async {
      final tempDir = await makeTempDir(tester, 'dlg_double');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final service = _FakeDownloadService();
      await pumpDialog(tester, service: service);

      // 同一帧内连点两次（中间不 pump，按钮还没切走）
      await tester.tap(find.text('去下载'));
      await tester.tap(find.text('去下载'));
      await tester.pump();

      expect(service.downloadCalls, 1);
      expect(find.text('取消下载'), findsOneWidget);
      // 收尾：放行下载，避免挂起的 Future 影响后续测试
      service.downloadCompleters[0].complete(await fakeApk(tester, tempDir));
      await tester.pump();
    });

    testWidgets('授权回流：去授权后回 App 自动复检并调起安装', (tester) async {
      final tempDir = await makeTempDir(tester, 'dlg_resume');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final service = _FakeDownloadService()..canInstall = false;
      await pumpDialog(tester, service: service);

      await tester.tap(find.text('去下载'));
      await tester.pump();
      service.downloadCompleters[0].complete(await fakeApk(tester, tempDir));
      await tester.pump();
      // 未授权 → needPermission 态
      expect(find.text('立即安装'), findsOneWidget);

      await tester.tap(find.text('去授权'));
      await tester.pump();
      expect(service.openSettingsCalls, 1);

      // 用户在系统设置开启后按返回回到 App
      service.canInstall = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(service.installCalls, 1);
      expect(find.text('安装包已就绪，请在系统弹窗中确认安装。'), findsOneWidget);
    });

    testWidgets('取消后立即重下：旧下载的迟到回调不把新下载打回 idle', (tester) async {
      final tempDir = await makeTempDir(tester, 'dlg_gen');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final service = _FakeDownloadService();
      await pumpDialog(tester, service: service);

      await tester.tap(find.text('去下载'));
      await tester.pump();
      expect(service.downloadCalls, 1);

      await tester.tap(find.text('取消下载'));
      await tester.pump();
      expect(find.text('去下载'), findsOneWidget);

      // 立即重下（第二个下载挂起）
      await tester.tap(find.text('去下载'));
      await tester.pump();
      expect(service.downloadCalls, 2);
      expect(find.text('取消下载'), findsOneWidget);

      // 第一个下载此时才以「已取消」收尾，迟到回调不得改 phase
      service.downloadCompleters[0].completeError(
        const ApkDownloadException('已取消下载', isCancelled: true),
      );
      await tester.pump();

      expect(find.text('取消下载'), findsOneWidget);
      expect(service.downloadCalls, 2);
      // 收尾：放行第二个下载
      service.downloadCompleters[1].complete(await fakeApk(tester, tempDir));
      await tester.pump();
    });
  });
}
