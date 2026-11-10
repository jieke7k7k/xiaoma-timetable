import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../utils/note_notice.dart';
import '../widgets/app_dialog.dart';
import '../widgets/empty_state.dart';

/// 星期几的中文简称（weekday 1=周一 … 7=周日）
const List<String> _weekdayNames = ['', '一', '二', '三', '四', '五', '六', '日'];

/// 备注页（v3·AI 备注）
///
/// 按日期分组列出全部备注（最近的日期在最前），可新增（选日期 + 填内容）、
/// 编辑、删除（删除前二次确认）。数据全部走 notesProvider + notes 表，
/// 增删改后该 Provider 会顺带刷新通知栏常驻通知与桌面小部件。
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('备注'), centerTitle: true),
      body: notesAsync.when(
        data: (notes) {
          if (notes.isEmpty) {
            return const EmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: '还没有备注',
              message: '点右下角加号，记下某天要做的事或要带的东西',
            );
          }
          // 日期倒序（最近的在前），同一天内保持写入顺序
          final dates = notes.map((n) => n.date).toSet().toList()..sort();
          final sections = dates.reversed.toList();
          final byDate = <String, List<Note>>{
            for (final d in dates)
              d: notes.where((n) => n.date == d).toList(),
          };
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.l, AppSpacing.s, AppSpacing.l, AppSpacing.l),
            itemCount: sections.length,
            itemBuilder: (context, i) {
              final date = sections[i];
              final list = byDate[date]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs, AppSpacing.m, 0, AppSpacing.s),
                    child: Text(
                      _dateTitle(date),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  for (final note in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s),
                      child: ListTile(
                        leading: Icon(
                          Icons.sticky_note_2_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(note.content),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: () => _confirmDelete(note),
                        ),
                        onTap: () => _showEditor(note: note),
                      ),
                    ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '加载失败',
          message: '$e',
          actionLabel: '重试',
          onAction: () => ref.read(notesProvider.notifier).reload(),
        ),
      ),
      // WB_SPEC_230 第 7 节 a：全站三处 FAB 统一为 extended（带文字长条）
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新增备注'),
      ),
    );
  }

  /// 分组标题：「今天」「明天」优先，其余显示「yyyy年M月d日 周X」
  String _dateTitle(String date) {
    final now = DateTime.now();
    if (date == noteDayKey(now)) return '今天';
    if (date ==
        noteDayKey(now.add(const Duration(days: 1)))) {
      return '明天';
    }
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return '${DateFormat('yyyy年M月d日').format(parsed)}'
        ' 周${_weekdayNames[parsed.weekday]}';
  }

  /// 新增/编辑备注对话框（必填内容 + 可选日期，默认今天）
  Future<void> _showEditor({Note? note}) async {
    final isEdit = note != null;
    var pickedDate = note != null
        ? (DateTime.tryParse(note.date) ?? DateTime.now())
        : DateTime.now();
    final controller = TextEditingController(text: note?.content ?? '');

    final saved = await showDialog<bool>(
      context: context,
      // WB_SPEC_230 第 4.2 节第 5 类：只换外层壳（StatefulBuilder 仍在外层），
      // content 的 Column 外包 SingleChildScrollView——小屏软键盘顶起时
      // 多行备注输入框不会 RenderFlex overflowed。
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AppDialog(
          title: isEdit ? '编辑备注' : '新增备注',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(_dateTitle(noteDayKey(pickedDate))),
                  subtitle: Text(noteDayKey(pickedDate)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: pickedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      helpText: '选择备注日期',
                    );
                    if (d != null) setState(() => pickedDate = d);
                  },
                ),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                  // WB_SPEC_230 第 5.2 节：手写圆角框删掉，统一吃全局 inputDecorationTheme
                  decoration: const InputDecoration(
                    hintText: '要记点什么？',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(const SnackBar(content: Text('备注内容不能为空')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final content = controller.text.trim();
    final dateKey = noteDayKey(pickedDate);
    try {
      if (isEdit) {
        await ref
            .read(notesProvider.notifier)
            .updateNote(note.copyWith(date: dateKey, content: content));
      } else {
        await ref.read(notesProvider.notifier).addNote(Note(
              date: dateKey,
              content: content,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(isEdit ? '已保存' : '已新增备注')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  /// 删除二次确认：备注删掉就找不回来了，必须点一下确认
  Future<void> _confirmDelete(Note note) async {
    if (note.id == null) return;
    // WB_SPEC_230 第 4.2 节第 2 类：破坏性删除确认（确认按钮 error 色）
    final ok = await showAppConfirmDialog(
      context,
      title: '删除这条备注？',
      message: note.content,
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(notesProvider.notifier).deleteNote(note.id!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已删除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }
}
