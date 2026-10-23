import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_session.dart';
import '../models/operation_log.dart';
import '../providers/providers.dart';
import '../services/chat_session_service.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/operation_log_service.dart';
import '../services/widget_service.dart';
import '../ui/app_styles.dart';
import '../widgets/app_dialog.dart';
import '../widgets/empty_state.dart';

/// 智能助手历史记录页（2.0.5 第 3 / 4 节）
///
/// 与聊天页配套：两个 Tab——
/// - 「对话」：按更新时间倒序列全部会话，点一条恢复整段对话继续聊（`pop` 回会话），
///   长按或左滑删除单条；空列表给中文空状态。
/// - 「操作记录」：AI / AI 桥每次改数据落下的执行前快照，每条带「撤回」按钮，
///   点了按快照把数据还原成执行前的样子并标记已撤回。
class AiHistoryPage extends ConsumerStatefulWidget {
  const AiHistoryPage({super.key});

  @override
  ConsumerState<AiHistoryPage> createState() => _AiHistoryPageState();
}

class _AiHistoryPageState extends ConsumerState<AiHistoryPage> {
  List<ChatSession> _sessions = const [];
  List<OperationLog> _logs = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final sessions = await ChatSessionService.instance.listSessions();
    final logs = await OperationLogService.instance.list();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _logs = logs;
      _loaded = true;
    });
  }

  Future<void> _openSession(ChatSession session) async {
    Navigator.pop(context, session);
  }

  /// 删除前二次确认（左滑 confirmDismiss 与长按共用）。
  /// 返回 true 才真正删除；false 由 Dismissible 自动弹回。
  Future<bool> _confirmDelete(ChatSession session) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除这段对话？',
      message: '「${session.title}」删除后无法恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    return ok == true;
  }

  /// 长按删除：先确认，再删库刷列表。
  Future<void> _deleteSession(ChatSession session) async {
    if (!await _confirmDelete(session)) return;
    await _deleteSessionData(session);
  }

  /// 确认通过后真正删除并刷新列表（左滑 confirmDismiss 为 true 时也走到这里）。
  Future<void> _deleteSessionData(ChatSession session) async {
    await ChatSessionService.instance.deleteSession(session.id!);
    await _reload();
  }

  Future<void> _undo(OperationLog log) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '撤回这条操作？',
      message: '将把数据恢复成执行「${log.summary}」之前的样子。',
      confirmLabel: '撤回',
      destructive: true,
    );
    if (ok != true) return;
    final error = await OperationLogService.instance.undo(log);
    if (!mounted) return;
    await _reload();
    // 撤回改动了课表/备注数据，与其它数据变更同一份联动
    // （provider 重查 + 提醒重排 + 备注通知 + 常驻通知 + 小部件）
    _applyUndoChanges();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已撤回并恢复数据')),
    );
  }

  /// 撤回改动数据后的联动刷新（与 AiChatPage._applyCommandChanges 同一份口径）
  void _applyUndoChanges() {
    ref.invalidate(coursesProvider);
    ref.invalidate(notesProvider);
    unawaited(NotificationService.instance.rescheduleAll());
    unawaited(NotificationService.instance.refreshNoteNotice());
    unawaited(OngoingNoticeService.instance.refresh());
    unawaited(WidgetService.instance.refreshWidgets());
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('智能助手记录'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: '对话'),
              Tab(text: '操作记录'),
            ],
          ),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildSessionsTab(),
                  _buildLogsTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildSessionsTab() {
    if (_sessions.isEmpty) {
      return const EmptyState(
        icon: Icons.history_outlined,
        title: '还没有历史对话',
        message: '去「智能助手」聊上几句，对话就会自动存到这里，'
            '之后可以随时接着聊或删除。',
      );
    }
    return ListView.separated(
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final s = _sessions[i];
        return Dismissible(
          key: ValueKey('session-${s.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(ctx).colorScheme.error,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.l),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.onError,
            ),
          ),
          confirmDismiss: (_) => _confirmDelete(s),
          onDismissed: (_) => _deleteSessionData(s),
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(
              s.title.isEmpty ? '（无标题）' : s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatTime(s.updatedAt)} · ${s.messages.length} 条消息',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSession(s),
            onLongPress: () => _deleteSession(s),
          ),
        );
      },
    );
  }

  Widget _buildLogsTab() {
    if (_logs.isEmpty) {
      return const EmptyState(
        icon: Icons.undo_outlined,
        title: '还没有操作记录',
        message: 'AI 或 AI 桥真正改了课表数据后，这里会出现可撤回的操作记录。',
      );
    }
    return ListView.separated(
      itemCount: _logs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final log = _logs[i];
        return ListTile(
          leading: Icon(
            log.source == 'ai' ? Icons.smart_toy_outlined : Icons.hub_outlined,
          ),
          title: Text(
            log.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_sourceLabel(log.source)} · ${_formatTime(log.createdAt)}'
            '${log.undone ? ' · 已撤回' : ''}',
          ),
          trailing: log.undone
              ? null
              : TextButton(
                  onPressed: () => _undo(log),
                  child: const Text('撤回'),
                ),
        );
      },
    );
  }

  String _sourceLabel(String source) => source == 'bridge' ? 'AI 桥' : 'AI';

  String _formatTime(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
