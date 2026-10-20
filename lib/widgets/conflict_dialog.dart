import 'package:flutter/material.dart';

import '../utils/conflict_detector.dart';

/// 冲突处理方式
enum ConflictResolution {
  /// 跳过新课（不导入当前草稿）
  skip,

  /// 覆盖旧课（删除冲突的已有课程，导入新课）
  overwrite,

  /// 保留两者（都入库，同格叠放显示）
  keepBoth,
}

/// 弹窗询问用户如何处理一次时间冲突
///
/// 返回用户选择；关闭弹窗返回 null（视为跳过该条草稿）。
Future<ConflictResolution?> showConflictDialog(
  BuildContext context,
  CourseConflict conflict,
) {
  return showDialog<ConflictResolution>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('发现时间冲突'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conflict.describe(),
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            '请选择如何处理：',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(ctx).colorScheme.outline,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictResolution.skip),
          child: const Text('跳过新课'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictResolution.overwrite),
          child: const Text('覆盖旧课'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ConflictResolution.keepBoth),
          child: const Text('保留两者'),
        ),
      ],
    ),
  );
}
