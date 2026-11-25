import 'dart:io';

import 'package:flutter/material.dart';

import '../services/apk_download_service.dart';
import 'app_dialog.dart';

enum _DownloadPhase { idle, downloading, needPermission, readyToInstall, failed }

/// 发现新版本弹窗（含 App 内直下进度条、失败重试、取消、未知来源安装引导）
/// （WB_SPEC_252）
class UpdateDownloadDialog extends StatefulWidget {
  final String version;
  final String downloadUrl;
  final String? releaseUrl;
  final String? changelog;
  final VoidCallback? onOpenReleaseNotes;
  final ApkDownloadService? downloadService;

  const UpdateDownloadDialog({
    super.key,
    required this.version,
    required this.downloadUrl,
    this.releaseUrl,
    this.changelog,
    this.onOpenReleaseNotes,
    this.downloadService,
  });

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog>
    with WidgetsBindingObserver {
  late final ApkDownloadService _service;
  ApkDownloadCancelToken? _cancelToken;

  /// 下载代际：每次开始/取消下载都 +1，迟到的旧下载回调凭此失效，
  /// 防「取消后立即重下，旧下载的迟到 setState 把新下载打回 idle」
  /// （DeepSeek 复审 P1-5）。
  int _downloadGeneration = 0;

  _DownloadPhase _phase = _DownloadPhase.idle;
  ApkDownloadProgress _progress = const ApkDownloadProgress(
    receivedBytes: 0,
    totalBytes: -1,
  );
  String? _errorMessage;
  File? _downloadedFile;
  /// 调起安装器重入锁（S3-5）：防「授权回流 + 手动点立即安装」并发重复调起系统安装器
  bool _isTriggeringInstall = false;

  @override
  void initState() {
    super.initState();
    _service = widget.downloadService ?? ApkDownloadService();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken?.cancel();
    super.dispose();
  }

  /// WB_SPEC_252 §2 Neon 补（授权回流）：用户在系统设置开启「安装未知
  /// 应用」后按返回回到 App，自动复检并继续调起安装；仍未授权则停在
  /// needPermission，靠「立即安装」按钮兜底（DeepSeek 复审 P1-3）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _phase == _DownloadPhase.needPermission &&
        _downloadedFile != null) {
      _triggerInstall();
    }
  }

  Future<void> _startDownload() async {
    // DeepSeek 复审 P1-4：同一帧内双击「去下载」不得开两个下载任务。
    if (_phase == _DownloadPhase.downloading) return;
    final generation = ++_downloadGeneration;
    _cancelToken = ApkDownloadCancelToken();
    setState(() {
      _phase = _DownloadPhase.downloading;
      _errorMessage = null;
      _progress = const ApkDownloadProgress(receivedBytes: 0, totalBytes: -1);
    });

    try {
      final file = await _service.downloadApk(
        url: widget.downloadUrl,
        version: widget.version,
        cancelToken: _cancelToken,
        onProgress: (p) {
          if (!mounted || generation != _downloadGeneration) return;
          setState(() => _progress = p);
        },
      );
      if (!mounted || generation != _downloadGeneration) return;
      _downloadedFile = file;
      await _triggerInstall();
    } on ApkDownloadException catch (e) {
      if (!mounted || generation != _downloadGeneration) return;
      if (e.isCancelled) {
        // 取消下载停在原弹窗，可再次点「去下载」
        setState(() {
          _phase = _DownloadPhase.idle;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _phase = _DownloadPhase.failed;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      // DeepSeek 复审 P2-3：downloadApk 之外的异常（如取缓存目录失败）
      // 也要落到 failed 态，不能让弹窗永久转圈。
      if (!mounted || generation != _downloadGeneration) return;
      setState(() {
        _phase = _DownloadPhase.failed;
        _errorMessage = '下载失败：$e';
      });
    }
  }

  void _cancelDownload() {
    // 旧下载的迟到回调凭代际失效，不会再把新下载的 phase 打回 idle。
    _downloadGeneration++;
    _cancelToken?.cancel();
    setState(() {
      _phase = _DownloadPhase.idle;
      _errorMessage = null;
    });
  }

  Future<void> _triggerInstall() async {
    if (_isTriggeringInstall) return;
    final file = _downloadedFile;
    if (file == null) return;
    _isTriggeringInstall = true;
    try {
      final canInstall = await _service.canRequestPackageInstalls();
      if (!mounted) return;

      if (!canInstall) {
        // 首次安装需系统「允许安装未知应用」授权：App 内展示引导文案
        setState(() => _phase = _DownloadPhase.needPermission);
        return;
      }

      setState(() => _phase = _DownloadPhase.readyToInstall);
      try {
        await _service.installApk(file.path);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = _DownloadPhase.failed;
          _errorMessage = '调起系统安装器失败：$e';
        });
      }
    } finally {
      _isTriggeringInstall = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // WB_SPEC_252 §2：下载中拦截返回键，防误触把下载变成孤儿任务；
    // 外层 showDialog 已 barrierDismissible: false，点弹窗外同样关不掉。
    // WB_SPEC_256 §7：外壳改用 AppDialog，底部按钮全部改用 AppDialogAction。
    return PopScope(
      canPop: _phase != _DownloadPhase.downloading,
      child: AppDialog(
        title: '发现新版本 ${widget.version}',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.changelog != null && widget.changelog!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.changelog!.trim(),
                  style: theme.textTheme.bodyMedium,
                ),
              ),

            if (_phase == _DownloadPhase.downloading) ...[
              LinearProgressIndicator(value: _progress.fraction),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress.percentText ?? '正在下载…',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    _progress.sizeText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],

            if (_phase == _DownloadPhase.needPermission)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '安装包已下载完成。首次更新需在系统设置中开启「允许来自此来源的应用」，授权后返回并点击「立即安装」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),

            if (_phase == _DownloadPhase.readyToInstall)
              Text(
                '安装包已就绪，请在系统弹窗中确认安装。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),

            if (_phase == _DownloadPhase.failed && _errorMessage != null)
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
        actions: _buildActions(context),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (_phase) {
      case _DownloadPhase.idle:
        return [
          AppDialogAction(
            label: '稍后再说',
            onPressed: () => Navigator.of(context).pop(),
          ),
          if (widget.releaseUrl != null && widget.onOpenReleaseNotes != null)
            AppDialogAction(
              label: '更新说明',
              onPressed: widget.onOpenReleaseNotes,
            ),
          AppDialogAction(
            label: '去下载',
            primary: true,
            onPressed: _startDownload,
          ),
        ];

      case _DownloadPhase.downloading:
        return [
          AppDialogAction(
            label: '取消下载',
            onPressed: _cancelDownload,
          ),
        ];

      case _DownloadPhase.needPermission:
        return [
          AppDialogAction(
            label: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            label: '去授权',
            onPressed: () async {
              await _service.openUnknownSourcesSettings();
            },
          ),
          AppDialogAction(
            label: '立即安装',
            primary: true,
            onPressed: _triggerInstall,
          ),
        ];

      case _DownloadPhase.readyToInstall:
        return [
          AppDialogAction(
            label: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            label: '重新调起安装',
            primary: true,
            onPressed: _triggerInstall,
          ),
        ];

      case _DownloadPhase.failed:
        return [
          AppDialogAction(
            label: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppDialogAction(
            label: '重试',
            primary: true,
            onPressed: _startDownload,
          ),
        ];
    }
  }
}
