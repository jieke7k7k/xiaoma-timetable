import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/semester.dart';
import '../providers/providers.dart';
import '../ui/app_styles.dart';
import '../widgets/empty_state.dart';
import '../widgets/semester_form_dialog.dart';

/// 学期管理页
///
/// 功能：
/// - 学期列表：名称、开学日期、总周数、当前激活徽标
/// - 新建学期：名称 + 开学日期（日期选择器，自动对齐周一）+ 总周数（默认 20）
/// - 编辑学期：所有学期（含当前学期）都能改名称 / 开学日期 / 总周数；
///   改的是当前学期时，保存后周次与课表立即按新日期、新总周数重算
/// - 切换激活学期：事务保证同时只有一个 isCurrent，切换后周视图/设置页自动联动刷新
/// - 删除旧学期：不允许删除当前激活学期；二次确认；级联删除该学期下所有课程
class SemesterManagePage extends ConsumerWidget {
  const SemesterManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semestersAsync = ref.watch(semestersProvider);
    final current = ref.watch(currentSemesterProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('学期管理'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSemester(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建学期'),
      ),
      body: semestersAsync.when(
        data: (semesters) {
          if (semesters.isEmpty) {
            // 统一空状态占位（阶段五·视觉打磨）：直接给「新建学期」入口
            return EmptyState(
              icon: Icons.school_outlined,
              title: '还没有学期',
              message: '创建一个学期，开始排你的课表吧',
              actionLabel: '新建学期',
              onAction: () => _createSemester(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
            itemCount: semesters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final s = semesters[i];
              // current 为 null（未加载完）时回退用数据库里的 isCurrent 标记
              final isCurrent = s.id == current?.id || s.isCurrent;
              return Card(
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppRadii.card),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            // 「当前学期」徽标属于 chip 级小元素，圆角统一取全局常量
                            borderRadius:
                                BorderRadius.circular(AppRadii.chip),
                          ),
                          child: Text(
                            '当前学期',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${s.startDate} 开学 · 共 ${s.totalWeeks} 周',
                    style: const TextStyle(fontSize: 12),
                  ),
                  // 当前学期只给「编辑学期」入口；切换与删除仍然不给（从源头杜绝误操作）
                  trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') {
                              _editSemester(context, ref, s);
                            } else if (action == 'switch') {
                              _confirmSwitch(context, ref, s);
                            } else if (action == 'delete') {
                              _confirmDelete(context, ref, s);
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined),
                                title: Text('编辑学期'),
                              ),
                            ),
                            if (!isCurrent) ...[
                              const PopupMenuItem(
                                value: 'switch',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.swap_horiz),
                                  title: Text('切换到该学期'),
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('删除该学期'),
                                ),
                              ),
                            ],
                          ],
                        ),
                  onTap: () {
                    if (isCurrent) return;
                    _confirmSwitch(context, ref, s);
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载学期列表失败：$e', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () =>
                    ref.read(semestersProvider.notifier).reload(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 新建学期：表单含名称、开学日期（日期选择器）、总周数（默认 20）
  Future<void> _createSemester(BuildContext context, WidgetRef ref) async {
    final created = await showSemesterFormDialog(context);
    if (created == null) return;
    try {
      await ref.read(semestersProvider.notifier).addSemester(created);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建「${created.name}」，点击卡片可切换过去')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：$e')));
      }
    }
  }

  /// 编辑学期（名称 / 开学日期 / 总周数），当前学期与其它学期走同一套表单与保存路径。
  ///
  /// 保存后的内存同步与「提醒重排 / 常驻通知 / 小组件」联动都在
  /// `SemestersNotifier.updateSemester` 里（被编辑的是当前学期时才做），页面不自己拼。
  Future<void> _editSemester(
      BuildContext context, WidgetRef ref, Semester s) async {
    final updated = await showSemesterFormDialog(context, initial: s);
    if (updated == null) return;
    try {
      await ref.read(semestersProvider.notifier).updateSemester(updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已更新「${updated.name}」')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  /// 切换激活学期（二次确认）
  Future<void> _confirmSwitch(
      BuildContext context, WidgetRef ref, Semester s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换学期'),
        content: Text('确定切换到「${s.name}」吗？\n课表与周次将显示该学期的内容。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('切换')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(semestersProvider.notifier).switchTo(s.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已切换到「${s.name}」')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('切换失败：$e')));
      }
    }
  }

  /// 删除学期（二次确认，级联删除课程；当前学期已在 UI 层隐藏入口，此处再兜底）
  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Semester s) async {
    final current = ref.read(currentSemesterProvider).value;
    if (current?.id == s.id) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('不能删除当前正在使用的学期，请先切换到其他学期')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除学期'),
        content: Text('确定删除「${s.name}」吗？\n该学期下的所有课程也会一并删除，且不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(semestersProvider.notifier).deleteSemester(s.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已删除「${s.name}」')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }
}
