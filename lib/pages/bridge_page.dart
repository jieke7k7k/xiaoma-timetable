import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/bridge_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';
import '../ui/app_styles.dart';
import '../utils/bridge_codec.dart';
import '../widgets/empty_state.dart';

/// AI 桥（设置 → AI 桥）：把一个 GitHub 私有仓当**命令信箱**
///
/// 三块内容：配置（owner/repo/令牌）、状态（上次同步摘要 + 立即同步）、
/// 待确认队列（破坏性指令要在这里点「执行」或「拒绝」）。
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
  String? _lastSync;
  List<BridgePendingItem> _pending = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
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
  }

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
      });
      _snack(_configured ? '配置已保存' : '已保存，但三项还没填全，暂时不会同步');
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
                _SectionHeader(title: '配置'),
                _ConfigCard(
                  owner: _owner,
                  repo: _repo,
                  token: _token,
                  obscureToken: _obscureToken,
                  saving: _saving,
                  configured: _configured,
                  onToggleObscure: () =>
                      setState(() => _obscureToken = !_obscureToken),
                  onSave: _saveConfig,
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
                      message: _configured
                          ? '外部 AI 发来的删除类指令会先放在这里等你点头'
                          : '填好上面的三项配置并同步一次后，指令才会进来',
                      actionLabel: _configured && !_syncing ? '立即同步' : null,
                      onAction: _configured && !_syncing ? _sync : null,
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

class _ConfigCard extends StatelessWidget {
  const _ConfigCard({
    required this.owner,
    required this.repo,
    required this.token,
    required this.obscureToken,
    required this.saving,
    required this.configured,
    required this.onToggleObscure,
    required this.onSave,
  });

  final TextEditingController owner;
  final TextEditingController repo;
  final TextEditingController token;
  final bool obscureToken;
  final bool saving;
  final bool configured;
  final VoidCallback onToggleObscure;
  final Future<void> Function() onSave;

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
                hintText: 'xiaoma-bridge',
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
                    obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                  onPressed: onToggleObscure,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '令牌需要这个私有仓的 Contents 读写权限（read/write）。'
              '配置状态：${configured ? '已配好，可以同步' : '未配好'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: AppSpacing.m),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
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
