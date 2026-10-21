import 'package:flutter/material.dart';

import '../models/course.dart';
import '../utils/conflict_detector.dart';
import '../utils/import_planner.dart';
import '../utils/week_parser.dart';

/// 导入冲突批量处理页（1.2.0，取代旧版逐条弹窗）
///
/// 一次导入十几门课时不再弹十几个窗：全部冲突汇总成清单——
/// 每处冲突单选 跳过 / 覆盖 / 保留两者；顶部可一键「全部」同选再逐条微调。
/// 点「按此处理并导入」返回与 [items] 同序的选择列表；返回键 = 取消本次导入
/// （回到核对页，草稿保留）。
class ImportConflictsPage extends StatefulWidget {
  const ImportConflictsPage({
    super.key,
    required this.drafts,
    required this.items,
  });

  final List<Course> drafts;
  final List<ImportConflictItem> items;

  @override
  State<ImportConflictsPage> createState() => _ImportConflictsPageState();
}

class _ImportConflictsPageState extends State<ImportConflictsPage> {
  // 默认全部「跳过」：最保守，绝不误删已有课程，用户想要覆盖再主动选
  late final List<ConflictResolution> _choices =
      List.filled(widget.items.length, ConflictResolution.skip);

  static const _weekNames = ['', '一', '二', '三', '四', '五', '六', '日'];

  void _applyAll(ConflictResolution r) {
    setState(() {
      for (var i = 0; i < _choices.length; i++) {
        _choices[i] = r;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 按草稿分组（保持草稿顺序）
    final groups = <int, List<int>>{};
    for (var i = 0; i < widget.items.length; i++) {
      groups.putIfAbsent(widget.items[i].draftIndex, () => []).add(i);
    }
    final plan = ImportPlanner.buildPlan(widget.drafts, widget.items, _choices);
    final willImport = plan.where((p) => p.shouldImport).length;
    final willSkip = plan.length - willImport;

    return Scaffold(
      appBar: AppBar(title: Text('处理时间冲突（${widget.items.length} 处）')),
      body: Column(
        children: [
          // 一键全部同选
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                const Text('全部设为：', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _applyAll(ConflictResolution.skip),
                        child: const Text('全部跳过'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _applyAll(ConflictResolution.overwrite),
                        child: const Text('全部覆盖'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _applyAll(ConflictResolution.keepBoth),
                        child: const Text('全部保留'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final entry in groups.entries) ...[
                  _draftHeader(widget.drafts[entry.key]),
                  for (final i in entry.value) _conflictRow(i),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _choices),
            icon: const Icon(Icons.check),
            label: Text('按此处理并导入（导入 $willImport 门 · 跳过 $willSkip 门）'),
          ),
        ),
      ),
    );
  }

  Widget _draftHeader(Course draft) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Color(draft.colorValue),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '新课《${draft.name}》 · 周${_weekNames[draft.dayOfWeek]} '
              '第${draft.startSection}'
              '${draft.endSection > draft.startSection ? "-${draft.endSection}" : ""}节'
              ' · ${WeekParser.toText(draft.weeks, draft.weekType)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _conflictRow(int i) {
    final item = widget.items[i];
    final other = item.conflict.courseB;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '与《${other.name}》冲突',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Chip(
                  label: Text(item.otherIsDraft ? '本批新课' : '已有课程',
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.conflict.describe(),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ConflictResolution>(
              segments: const [
                ButtonSegment(
                    value: ConflictResolution.skip, label: Text('跳过新课')),
                ButtonSegment(
                    value: ConflictResolution.overwrite, label: Text('覆盖对方')),
                ButtonSegment(
                    value: ConflictResolution.keepBoth, label: Text('保留两者')),
              ],
              selected: {_choices[i]},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _choices[i] = s.first),
            ),
          ],
        ),
      ),
    );
  }
}
