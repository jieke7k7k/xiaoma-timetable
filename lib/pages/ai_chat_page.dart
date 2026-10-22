import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/ai_service.dart';
import '../services/command_executor.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/widget_service.dart';
import '../ui/app_styles.dart';
import '../utils/ai_context.dart';
import '../utils/override_effect.dart';
import '../widgets/empty_state.dart';

/// 内置智能助手聊天页（底栏左「智能助手」，2.0.1 由「AI」改名）
///
/// 三件事：
/// 1. 发送时**现取**课表上下文（学期/本周课表/临近考试/今明备注）塞进 system 提示，
///    所以它能直接答「我明天有什么课」；
/// 2. 模型回复里若带 fenced json 指令块，**解析出来先渲染成确认卡片**，用户点
///    「执行」才交给 [CommandExecutor]（与 AI 桥同一套执行器与描述函数）；
/// 3. 执行完把结果回填到聊天里，并触发与其它数据变更完全一致的联动。
///
/// 代码块本身不给用户看：解析阶段已从正文里摘掉（见 [parseAiReply]）。
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_ChatItem> _items = [];
  bool _sending = false;
  bool _configured = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await AiService.instance.loadSettings();
    if (!mounted) return;
    setState(() {
      _configured = s.configured;
      _loaded = true;
    });
  }

  /// 当前课表上下文（发送时现取，改过课表立刻生效）
  String _contextNow() {
    final semester = ref.read(currentSemesterProvider).value;
    final courses = ref.read(coursesProvider).value ?? const [];
    final overrides = ref.read(courseOverridesProvider).value ?? const [];
    final notes = ref.read(notesProvider).value ?? const [];
    final week = ref.read(todayWeekProvider);
    // 未开学时按第 1 周取（week=0 会让所有课程都不生效，上下文里什么都没有）
    final weekCourses = effectiveCoursesForWeek(
      courses: courses,
      overrides: overrides,
      week: week > 0 ? week : 1,
    );
    return buildTimetableContext(
      semester: semester,
      courses: weekCourses,
      notes: notes,
      now: DateTime.now(),
    );
  }

  Future<void> _send({String? retryText}) async {
    final text = (retryText ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (retryText == null) _input.clear();
    setState(() {
      if (retryText != null && _items.isNotEmpty) {
        // 重试：把上一条失败提示删掉，避免错误提示越堆越多
        _items.removeLast();
      }
      _items.add(_ChatItem(fromUser: true, text: text));
      _sending = true;
    });
    _scrollToEnd();

    final history = <AiMessage>[
      AiMessage(role: 'system', content: buildSystemPrompt(_contextNow())),
      for (final item in _items)
        if (item.commands.isEmpty)
          AiMessage(
            role: item.fromUser ? 'user' : 'assistant',
            content: item.text,
          ),
    ];
    final result = await AiService.instance.chat(history);
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _configured = !result.unconfigured;
        _items.add(
          _ChatItem(
            fromUser: false,
            text: result.error ?? '请求失败',
            failed: true,
            retryText: text,
          ),
        );
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    final reply = parseAiReply(result.text);
    setState(() {
      _items.add(
        _ChatItem(
          fromUser: false,
          text: reply.text.isEmpty ? '（这次只有指令，没有文字回复）' : reply.text,
          commands: reply.commands,
          parseError: reply.commandParseError,
        ),
      );
      _sending = false;
    });
    _scrollToEnd();
  }

  /// 执行一批指令（确认卡片里点「执行」）
  Future<void> _runCommands(_ChatItem item, List<int> indices) async {
    if (indices.isEmpty || item.busy) return;
    setState(() => item.busy = true);
    final executor = CommandExecutor();
    final results = await executor.executeAll([
      for (final i in indices) item.commands[i],
    ]);
    if (!mounted) return;
    setState(() {
      for (var k = 0; k < indices.length; k++) {
        final r = results[k];
        item.resolved[indices[k]] = r.success;
        item.results.add('${r.success ? '已执行' : '失败'}：${r.message}');
      }
      item.busy = false;
    });
    // 与其它数据变更同一份联动（provider 重查 + 提醒重排 + 备注通知 + 小部件）
    _applyCommandChanges();
    _scrollToEnd();
  }

  void _ignore(_ChatItem item, int index) {
    setState(() => item.resolved[index] = false);
  }

  /// 指令改动数据后的联动刷新（与 BridgePage / HomeShell 同一份口径）
  void _applyCommandChanges() {
    ref.invalidate(coursesProvider);
    ref.invalidate(notesProvider);
    unawaited(NotificationService.instance.rescheduleAll());
    unawaited(NotificationService.instance.refreshNoteNotice());
    unawaited(OngoingNoticeService.instance.refresh());
    unawaited(WidgetService.instance.refreshWidgets());
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能助手'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.pushNamed(context, '/ai-settings');
              if (!mounted) return;
              final s = await AiService.instance.loadSettings();
              if (!mounted) return;
              setState(() => _configured = s.configured);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _items.isEmpty
                ? null
                : () => setState(() => _items.clear()),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _configured && _items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.l),
                          child: EmptyState(
                            icon: Icons.smart_toy_outlined,
                            title: '问点什么吧',
                            message: '我带着你这一周的课表、临近考试和今明两天的备注，'
                                '可以直接回答「我明天有什么课」「周三下午有空吗」；'
                                '要我改课表也会先给你确认，不会偷偷改。',
                            actionLabel: '试试问「我明天有什么课」',
                            onAction: () {
                              _input.text = '我明天有什么课？';
                              _send();
                            },
                          ),
                        )
                      : !_configured && _items.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(AppSpacing.l),
                              child: EmptyState(
                                icon: Icons.smart_toy_outlined,
                                title: '还没配置智能助手',
                                message: '填好接口地址、模型名和 API Key 就能用。'
                                    '默认填的是智谱（open.bigmodel.cn），'
                                    '注册后在「API Keys」里免费领一个 Key。',
                                actionLabel: '去智能助手设置',
                                onAction: () async {
                                  await Navigator.pushNamed(
                                    context,
                                    '/ai-settings',
                                  );
                                  if (!mounted) return;
                                  await _load();
                                },
                              ),
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.all(AppSpacing.m),
                              itemCount: _items.length,
                              itemBuilder: (ctx, i) =>
                                  _buildItem(ctx, _items[i]),
                            ),
                ),
                if (_sending)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.m,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        Text(
                          '正在回复…',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.outline),
                        ),
                      ],
                    ),
                  ),
                _InputBar(
                  controller: _input,
                  enabled: !_sending,
                  onSend: () => _send(),
                ),
              ],
            ),
    );
  }

  Widget _buildItem(BuildContext context, _ChatItem item) {
    final scheme = Theme.of(context).colorScheme;
    if (item.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.s, left: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.s,
          ),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Text(
            item.text,
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s, right: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              decoration: BoxDecoration(
                color: item.failed
                    ? scheme.errorContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Text(
                item.text,
                style: TextStyle(
                  color: item.failed
                      ? scheme.onErrorContainer
                      : scheme.onSurface,
                ),
              ),
            ),
            if (item.failed && item.retryText != null) ...[
              const SizedBox(height: AppSpacing.xs),
              TextButton.icon(
                onPressed: () => _send(retryText: item.retryText),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
            if (item.parseError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.parseError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ],
            if (item.commands.isNotEmpty)
              _CommandCard(
                item: item,
                busy: item.busy || _sending,
                onRun: (indices) => _runCommands(item, indices),
                onIgnore: (index) => _ignore(item, index),
              ),
            if (item.results.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              for (final r in item.results)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    r,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.outline),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 发送栏
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          AppSpacing.xs,
          AppSpacing.m,
          AppSpacing.m,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: '问课表，或让我帮你改课表…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            IconButton.filled(
              onPressed: enabled ? onSend : null,
              icon: const Icon(Icons.send_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

/// 指令确认卡片：非破坏指令「一键执行」，破坏指令单独标红逐条确认
class _CommandCard extends StatelessWidget {
  const _CommandCard({
    required this.item,
    required this.busy,
    required this.onRun,
    required this.onIgnore,
  });

  final _ChatItem item;
  final bool busy;
  final void Function(List<int> indices) onRun;
  final void Function(int index) onIgnore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final safe = <int>[];
    final destructive = <int>[];
    for (var i = 0; i < item.commands.length; i++) {
      if (item.resolved.containsKey(i)) continue;
      if (isDestructiveCommand(item.commands[i])) {
        destructive.add(i);
      } else {
        safe.add(i);
      }
    }
    if (safe.isEmpty && destructive.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.construction_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '要我执行这些操作吗',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          for (final i in [...safe, ...destructive])
            _CommandRow(
              index: i,
              command: item.commands[i],
              destructive: isDestructiveCommand(item.commands[i]),
              busy: busy,
              onRun: () => onRun([i]),
              onIgnore: () => onIgnore(i),
            ),
          if (safe.length > 1) ...[
            const SizedBox(height: AppSpacing.s),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: busy ? null : () => onRun(safe),
                child: Text('一键执行这 ${safe.length} 条'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.index,
    required this.command,
    required this.destructive,
    required this.busy,
    required this.onRun,
    required this.onIgnore,
  });

  final int index;
  final Map<String, dynamic> command;
  final bool destructive;
  final bool busy;
  final VoidCallback onRun;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            destructive ? Icons.warning_amber_outlined : Icons.chevron_right,
            size: 18,
            color: destructive ? scheme.error : scheme.outline,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              describeAiCommand(command),
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
          if (destructive)
            TextButton(
              onPressed: busy ? null : onIgnore,
              child: const Text('忽略'),
            ),
          FilledButton(
            onPressed: busy ? null : onRun,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(destructive ? '仍要执行' : '执行'),
          ),
        ],
      ),
    );
  }
}

/// 一条聊天消息（含它可能携带的指令块）
class _ChatItem {
  _ChatItem({
    required this.fromUser,
    required this.text,
    List<Map<String, dynamic>>? commands,
    this.failed = false,
    this.retryText,
    this.parseError,
  }) : commands = commands ?? const [];

  final bool fromUser;
  final String text;

  /// 解析出的指令原文（空表示普通聊天消息）
  final List<Map<String, dynamic>> commands;

  /// 这条是失败提示（带重试按钮）
  final bool failed;

  /// 失败时用于重试的原文（用户那句提问）
  final String? retryText;

  /// 指令块 JSON 坏掉的提示
  final String? parseError;

  /// 下标 → 是否已执行成功（false 表示用户忽略）
  final Map<int, bool> resolved = {};

  /// 执行结果的中文摘要（回填展示）
  final List<String> results = [];

  bool busy = false;
}
