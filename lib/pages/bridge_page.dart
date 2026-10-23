import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
import '../services/bridge_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../ui/app_styles.dart';
import '../utils/bridge_codec.dart';
import '../widgets/app_dialog.dart';
import '../widgets/empty_state.dart';
import 'bridge_web_login_page.dart';

/// AI 桥（设置 → 智能助手设置 → AI 桥）：把一个 GitHub 私有仓当**命令信箱**
///
/// 2.0.1 起普通用户走 GitHub 官方设备码流程（Device Flow）一步登录，不再手填令牌；
/// 细粒度令牌仍可在底部「高级设置」折叠区手动配置。
/// 2.0.4 起授权页改为在 App 内嵌 WebView 打开并自动填码（见
/// [BridgeWebLoginPage]），外部浏览器降为「手动输码」兜底路径。
/// 2.0.5 起兜底路径改用 Chrome Custom Tab 打开（与用户默认浏览器共享登录态），
/// 按钮改名「在浏览器打开（共享登录，手动输码）」。
///
/// 本页持有 ref，因此承担 [BridgeService] 明确不肯做的那半件事——**执行完之后的
/// 联动刷新**（provider 重查 / 提醒重排 / 备注通知 / 小部件）。服务层只回一个
/// `changed` 标记，见 lib/services/bridge_service.dart 的类注释。
class BridgePage extends ConsumerStatefulWidget {
  const BridgePage({super.key});

  @override
  ConsumerState<BridgePage> createState() => _BridgePageState();
}

class _BridgePageState extends ConsumerState<BridgePage> {
  final TextEditingController _owner = TextEditingController();
  final TextEditingController _repo = TextEditingController();
  final TextEditingController _token = TextEditingController();

  bool _obscureToken = true;
  bool _configured = false;
  bool _saving = false;
  bool _syncing = false;
  bool _testing = false;
  String? _lastSync;
  List<BridgePendingItem> _pending = const [];
  bool _loaded = false;

  // 设备码登录流程状态
  bool _deviceActive = false; // 正在申请或轮询
  String? _deviceUserCode;
  String? _deviceVerificationUri;
  String? _deviceError; // 流程结束时的人话提示（过期/拒绝/网络等）
  Timer? _pollTimer;
  String _deviceCode = '';
  int _pollIntervalSeconds = 5;

  // 已自动写入剪贴板的设备码值：守卫「只在新码到达时复制一次」，
  // 轮询/重绘/状态刷新都不得重复覆盖剪贴板
  String _copiedUserCode = '';

  // 已连接但信箱仓是否缺失（仅设备码流程成功后检查）
  bool? _repoMissing;
  bool _creatingRepo = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _owner.dispose();
    _repo.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await BridgeService.instance.loadSettings();
    final last = await BridgeService.instance.lastSyncSummary();
    final pending = await BridgeService.instance.pendingItems();
    if (!mounted) return;
    setState(() {
      _owner.text = cfg.owner;
      _repo.text = cfg.repo;
      _configured = cfg.configured;
      _lastSync = last;
      _pending = pending;
      _loaded = true;
    });
    if (cfg.configured) unawaited(_checkRepo());
  }

  Future<void> _checkRepo() async {
    final cfg = await BridgeService.instance.loadSettings();
    if (!cfg.configured) return;
    final exists = await BridgeService.instance.checkMailboxRepo(
      owner: cfg.owner,
      repo: cfg.repo,
      token: cfg.token,
    );
    if (!mounted) return;
    setState(() => _repoMissing = exists == null ? null : !exists);
  }

  // ---------- 设备码登录 ----------

  Future<void> _connectGithub() async {
    setState(() {
      _deviceActive = true;
      _deviceError = null;
      _deviceUserCode = null;
      _deviceVerificationUri = null;
    });
    final resp = await BridgeService.instance.requestDeviceCode();
    if (!mounted) return;
    if (!resp.ok) {
      setState(() {
        _deviceActive = false;
        _deviceError = resp.error ?? '申请设备码失败，请稍后重试';
      });
      return;
    }
    setState(() {
      _deviceCode = resp.deviceCode;
      _deviceUserCode = resp.userCode;
      _deviceVerificationUri = resp.verificationUri;
      _pollIntervalSeconds = resp.intervalSeconds;
    });
    // 新码到达自动写剪贴板一次（原样含连字符）；失败静默，按钮兜底
    unawaited(_autoCopyNewCode(resp.userCode));
    _startPolling();
  }

  /// 新设备码自动复制：只在码值变化时触发一次，失败不报错不崩溃
  Future<void> _autoCopyNewCode(String code) async {
    if (code.isEmpty || code == _copiedUserCode) return;
    _copiedUserCode = code;
    try {
      await Clipboard.setData(ClipboardData(text: code));
    } catch (_) {
      // 自动复制失败静默处理，靠「复制代码」按钮兜底
    }
  }

  /// 手动「复制代码」：再次复制并 SnackBar 提示（2.0.4 起自动填码是主路径，
  /// 复制只作「在浏览器打开（手动输码）」兜底时的备用）
  Future<void> _copyUserCode() async {
    final code = _deviceUserCode;
    if (code == null || code.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      _snack('已复制，可作为手动输码备用');
    } catch (_) {
      if (!mounted) return;
      _snack('复制失败，请手动选中代码复制');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => unawaited(_pollOnce()),
    );
  }

  Future<void> _pollOnce() async {
    if (!_deviceActive) return;
    final resp = await BridgeService.instance.pollDeviceToken(_deviceCode);
    if (!mounted) return;
    switch (resp.status) {
      case DeviceTokenStatus.pending:
        break; // 继续等
      case DeviceTokenStatus.slowDown:
        // 用户还没输码，服务器让放慢：加长间隔后重启计时器
        _pollIntervalSeconds += 5;
        _startPolling();
        break;
      case DeviceTokenStatus.success:
        await _finishLogin(resp.accessToken!);
        break;
      case DeviceTokenStatus.expired:
      case DeviceTokenStatus.denied:
      case DeviceTokenStatus.error:
        _pollTimer?.cancel();
        setState(() {
          _deviceActive = false;
          _deviceError = resp.error ?? '授权失败，请重新申请';
        });
        break;
    }
  }

  Future<void> _finishLogin(String token) async {
    _pollTimer?.cancel();
    // 取当前登录用户 login，自动填 bridge_owner（用户不再手填归属名）
    final login = await BridgeService.instance.fetchGithubLogin(token);
    if (!mounted) return;
    if (login == null) {
      setState(() {
        _deviceActive = false;
        _deviceError = '拿到令牌但取不到 GitHub 账号信息，请重试';
      });
      return;
    }
    const repo = 'xiaoma-app-bridge';
    await BridgeService.instance.saveDeviceLogin(
      token: token,
      owner: login,
      repo: repo,
    );
    if (!mounted) return;
    setState(() {
      _deviceActive = false;
      _configured = true;
      _owner.text = login;
      _repo.text = repo;
      _repoMissing = null;
    });
    await _checkRepo();
  }

  void _cancelDevice() {
    _pollTimer?.cancel();
    setState(() {
      _deviceActive = false;
      _deviceError = null;
      _deviceUserCode = null;
      _deviceVerificationUri = null;
    });
  }

  /// 主路径（2.0.4）：在 App 内嵌 WebView 里打开 GitHub 授权页并自动填码。
  /// 页面不返回结果——轮询换令牌仍由本页定时器负责，用户在 WebView 里授权后
  /// 下一次轮询就会拿到令牌并自动完成连接。
  Future<void> _openInApp() async {
    final code = _deviceUserCode;
    if (code == null || code.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BridgeWebLoginPage(
          userCode: code,
          verificationUri:
              _deviceVerificationUri ?? 'https://github.com/login/device',
        ),
      ),
    );
  }

  /// 兜底路径：用 Chrome Custom Tab 打开授权页（与用户默认浏览器共享登录态，
  /// 2.0.5，WB_SPEC_205 第 7 节）——页面以卡片形式滑出、关闭即回 App，手输 8 位码。
  Future<void> _openInBrowser() async {
    final uri = Uri.parse(
      _deviceVerificationUri ?? 'https://github.com/login/device',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      if (!mounted) return;
      _snack('打不开浏览器，请手动访问 $uri');
    }
  }

  Future<void> _createRepo() async {
    setState(() => _creatingRepo = true);
    final cfg = await BridgeService.instance.loadSettings();
    final err = await BridgeService.instance.createMailboxRepo(
      owner: cfg.owner,
      repo: cfg.repo,
      token: cfg.token,
    );
    if (!mounted) return;
    setState(() {
      _creatingRepo = false;
      if (err == null) _repoMissing = false;
    });
    _snack(err == null ? '信箱仓已创建，可以同步了' : '创建失败：$err');
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    await BridgeService.instance.disconnect();
    if (!mounted) return;
    setState(() {
      _configured = false;
      _owner.text = '';
      _repoMissing = null;
      _pending = const [];
    });
    _snack('已断开连接');
  }

  // ---------- 高级手动方式 ----------

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      await BridgeService.instance.saveSettings(
        owner: _owner.text,
        repo: _repo.text,
        token: _token.text,
      );
      final cfg = await BridgeService.instance.loadSettings();
      if (!mounted) return;
      setState(() {
        _configured = cfg.configured;
        _token.clear();
        _repoMissing = null;
      });
      _snack(_configured ? '配置已保存' : '已保存，但三项还没填全，暂时不会同步');
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    try {
      // 令牌留空时沿用已保存的令牌（与保存同一口径），方便只测连接不重填
      final saved = await BridgeService.instance.loadSettings();
      final token = _token.text.trim().isEmpty ? saved.token : _token.text.trim();
      final names = await BridgeService.instance.testConnection(
        owner: _owner.text,
        repo: _repo.text,
        token: token,
      );
      if (!mounted) return;
      _snack(
        names.isEmpty
            ? '连接成功，commands 目录还是空的'
            : '连接成功，commands 目录有 ${names.length} 个文件',
      );
    } catch (e) {
      if (!mounted) return;
      _snack('测试连接失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    BridgeSyncOutcome outcome;
    try {
      outcome = await BridgeService.instance.syncNow();
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _snack('同步失败：$e');
      return;
    }
    if (!mounted) return;
    final pending = await BridgeService.instance.pendingItems();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _pending = pending;
      _lastSync = '${_format(outcome.time)} · ${outcome.summary}';
    });
    if (outcome.changed) _applyBridgeChanges();
    _snack(outcome.summary);
  }

  Future<void> _resolve(BridgePendingItem item, {required bool approve}) async {
    BridgeResolveOutcome outcome;
    try {
      outcome = await BridgeService.instance.resolvePending(
        item,
        approve: approve,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('处理失败：$e');
      return;
    }
    if (!mounted) return;
    final pending = await BridgeService.instance.pendingItems();
    if (!mounted) return;
    setState(() => _pending = pending);
    if (outcome.changed) _applyBridgeChanges();
    _snack(outcome.message);
  }

  /// 桥改动数据后的联动刷新：一批指令在设置页/启动任务里只刷这一遍
  /// （`HomeShell._applyBridgeChanges` 是同一份口径，改这里记得同步另一处）
  void _applyBridgeChanges() {
    ref.invalidate(coursesProvider);
    ref.invalidate(notesProvider);
    unawaited(NotificationService.instance.rescheduleAll());
    unawaited(WidgetService.instance.refreshWidgets());
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 桥'), centerTitle: true),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // 未连接：一句话 + 大按钮；设备码流程进行中 / 出错时切到对应卡片
                if (_deviceActive) ...[
                  _SectionHeader(title: '连接'),
                  _DeviceCard(
                    userCode: _deviceUserCode ?? '',
                    verificationUri:
                        _deviceVerificationUri ?? 'https://github.com/login/device',
                    onOpenInApp: _openInApp,
                    onOpenExternal: _openInBrowser,
                    onCopy: _copyUserCode,
                    onCancel: _cancelDevice,
                  ),
                ] else if (!_configured && _deviceError != null) ...[
                  _SectionHeader(title: '连接'),
                  _DeviceErrorCard(
                    error: _deviceError!,
                    onRetry: _connectGithub,
                  ),
                ] else if (!_configured) ...[
                  _SectionHeader(title: '连接'),
                  _ConnectCard(onConnect: _connectGithub),
                ],
                if (_configured) ...[
                  _SectionHeader(title: '已连接'),
                  _ConnectedCard(
                    login: _owner.text,
                    repo: _repo.text,
                    repoMissing: _repoMissing,
                    creatingRepo: _creatingRepo,
                    onCreateRepo: _createRepo,
                    onDisconnect: _disconnect,
                  ),
                  _SectionHeader(title: '同步'),
                  _StatusCard(
                    lastSync: _lastSync,
                    configured: _configured,
                    syncing: _syncing,
                    onSync: _sync,
                  ),
                  _SectionHeader(title: '待确认'),
                  if (_pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: '没有待确认的指令',
                        message: '外部 AI 发来的删除类指令会先放在这里等你点头',
                        actionLabel: !_syncing ? '立即同步' : null,
                        onAction: !_syncing ? _sync : null,
                      ),
                    )
                  else
                    for (final item in _pending)
                      _PendingCard(
                        item: item,
                        busy: _syncing,
                        onApprove: () => _resolve(item, approve: true),
                        onReject: () => _resolve(item, approve: false),
                      ),
                ],
                _SectionHeader(title: '高级'),
                ExpansionTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('手动令牌（细粒度令牌）'),
                  subtitle: const Text('给想用细粒度令牌的人，普通用户不用管'),
                  initiallyExpanded: false,
                  children: [
                    _ManualCard(
                      owner: _owner,
                      repo: _repo,
                      token: _token,
                      obscureToken: _obscureToken,
                      saving: _saving,
                      testing: _testing,
                      onToggleObscure: () =>
                          setState(() => _obscureToken = !_obscureToken),
                      onSave: _saveConfig,
                      onTest: _testConnection,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  child: Text(
                    '令牌只保存在本机、只用于 GitHub 请求头，不会写进日志、'
                    '结果文件、课表快照或备份文件；恢复备份时以本机令牌为准。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 分区标题（与设置页同款）
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.l,
        AppSpacing.l,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// 未连接时的一句话说明 + 「连接 GitHub」大按钮
///
/// 2.0.2（WB-202 第 4 项）：原来整段平铺的说明文字移入标题旁的 ⓘ 信息弹窗
/// （正文一字未改），卡片只留标题与主按钮，不再占半屏。
class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.onConnect});

  final VoidCallback onConnect;

  /// AI 桥顶部说明全文（原卡片平铺文案，一字未改，移入 ⓘ 弹窗）
  static const String _guide =
      '用 GitHub 账号一步登录，App 会把一个私有仓库当命令信箱，'
      '让外部 AI 帮你改课表（删除类指令会先等你确认）。';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '用 GitHub 账号一步登录',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                AppInfoIconButton(
                  tooltip: 'AI 桥是什么',
                  onPressed: () => showAppInfoDialog(
                    context,
                    title: 'AI 桥是什么',
                    message: _guide,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onConnect,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.login),
                label: const Text('连接 GitHub'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设备码展示卡：大字 user_code + 三步说明 + 「在 App 内打开并自动填码」主按钮
/// + 「在浏览器打开（共享登录，手动输码）」次要按钮 + 「复制代码」+ 取消
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.userCode,
    required this.verificationUri,
    required this.onOpenInApp,
    required this.onOpenExternal,
    required this.onCopy,
    required this.onCancel,
  });

  final String userCode;
  final String verificationUri;

  /// 主路径：App 内嵌 WebView 打开并自动填码（2.0.4）
  final VoidCallback onOpenInApp;

  /// 兜底路径：外部浏览器打开，用户自己手动输码
  final VoidCallback onOpenExternal;

  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '按下面三步完成 GitHub 登录',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.m),
            Center(
              child: Text(
                userCode,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Center(
              child: Text(
                verificationUri,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            const _StepLine(
              number: 1,
              text: '点「在 App 内打开并自动填码」',
            ),
            const _StepLine(
              number: 2,
              text: '在打开的页面里登录/确认账号，码已自动填好，点 Continue 并授权',
            ),
            const _StepLine(
              number: 3,
              text: '关闭页面返回，App 自动完成连接',
            ),
            // 2.0.5：浏览器方式（共享登录）的要点补充——已登录状态手输 8 位码即可，
            // 粘贴只能填一格（GitHub 页面的限制），不想手输就用 App 内自动填码
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                '补充：浏览器方式打开后已是登录状态，手输 8 位码即可；'
                '粘贴只能填一格（GitHub 页面的限制），不想手输就用 App 内自动填码。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.outline),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenInApp,
                icon: const Icon(Icons.open_in_new),
                label: const Text('在 App 内打开并自动填码'),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onOpenExternal,
                icon: const Icon(Icons.public),
                label: const Text('在浏览器打开（共享登录，手动输码）'),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制代码'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                onPressed: onCancel,
                child: const Text('取消登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 设备码卡片里的一步说明行：序号 + 一行文案
class _StepLine extends StatelessWidget {
  const _StepLine({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$number. ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// 设备码流程失败（过期/拒绝/网络）的提示 + 重新申请
class _DeviceErrorCard extends StatelessWidget {
  const _DeviceErrorCard({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.error),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新申请'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 已连接状态卡：@login · 仓库 + （缺仓时）一键建仓 + 断开连接
class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({
    required this.login,
    required this.repo,
    required this.repoMissing,
    required this.creatingRepo,
    required this.onCreateRepo,
    required this.onDisconnect,
  });

  final String login;
  final String repo;
  final bool? repoMissing;
  final bool creatingRepo;
  final VoidCallback onCreateRepo;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, size: 20, color: scheme.primary),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    '已连接为 @$login · 仓库 $login/$repo',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            // 设备码流程成功后检查：信箱仓不存在（404）时给一键创建入口
            if (repoMissing == true) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                '还没找到信箱仓 $login/$repo，需要先创建。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
              const SizedBox(height: AppSpacing.s),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: creatingRepo ? null : onCreateRepo,
                  icon: creatingRepo
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.create_new_folder_outlined),
                  label: Text(creatingRepo ? '创建中…' : '一键创建信箱仓'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('断开连接'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 高级折叠区里的手动配置卡：归属名 / 仓库名 / 令牌 + 保存 + 测试连接
class _ManualCard extends StatelessWidget {
  const _ManualCard({
    required this.owner,
    required this.repo,
    required this.token,
    required this.obscureToken,
    required this.saving,
    required this.testing,
    required this.onToggleObscure,
    required this.onSave,
    required this.onTest,
  });

  final TextEditingController owner;
  final TextEditingController repo;
  final TextEditingController token;
  final bool obscureToken;
  final bool saving;
  final bool testing;
  final VoidCallback onToggleObscure;
  final Future<void> Function() onSave;
  final Future<void> Function() onTest;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '把哪个私有仓当信箱',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: owner,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'owner（仓库归属）',
                hintText: 'jieke7k7k',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: repo,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'repo（仓库名）',
                hintText: 'xiaoma-app-bridge',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            TextField(
              controller: token,
              obscureText: obscureToken,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'token（细粒度令牌，留空不改）',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    obscureToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '令牌需要这个私有仓的 Contents 读写权限（read/write）。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: testing ? null : onTest,
                  icon: testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连接'),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.lastSync,
    required this.configured,
    required this.syncing,
    required this.onSync,
  });

  final String? lastSync;
  final bool configured;
  final bool syncing;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.sync_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    lastSync == null ? '还没同步过' : lastSync!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: syncing ? null : onSync,
                icon: syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync_outlined),
                label: Text(syncing ? '同步中…' : '立即同步'),
              ),
            ),
            if (!configured) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                '还没填全 owner / repo / 令牌，同步不会开始。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一条待确认的破坏性指令：人话描述 + 执行/拒绝
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.item,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final BridgePendingItem item;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.s,
        AppSpacing.l,
        AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              describePendingCommand(item),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '来自指令批 ${item.batchId} 的第 ${item.index + 1} 条 · '
              '${_formatTime(item.arrivedAt)} 到达',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.outline),
            ),
            const SizedBox(height: AppSpacing.s),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : onReject,
                  child: const Text('拒绝'),
                ),
                const SizedBox(width: AppSpacing.s),
                FilledButton(
                  onPressed: busy ? null : onApprove,
                  child: const Text('执行'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
}

String _format(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
