import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// AI 路由守卫（WB_SPEC_212 第 3 节补强：入口隐藏之外的第二层）。
///
/// 未解锁用户直接走 /developer-options、/ai-chat、/ai-settings、/ai-history、
/// /bridge 这些路由时，不得看到任何 AI 内容：本页只显示一句占位提示，
/// 首帧后自动退回上一页；退无可退（深链直达）时替换为设置页。
/// 已解锁时原样显示子页；加载中时显示加载圈，不先放行、也不误判为未解锁。
class AiRouteGuard extends ConsumerStatefulWidget {
  const AiRouteGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AiRouteGuard> createState() => _AiRouteGuardState();
}

class _AiRouteGuardState extends ConsumerState<AiRouteGuard> {
  bool _redirectScheduled = false;

  void _scheduleRedirect() {
    if (_redirectScheduled) return;
    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/settings');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = ref.watch(developerOptionsProvider);
    return unlocked.when(
      data: (isUnlocked) {
        if (isUnlocked) return widget.child;
        _scheduleRedirect();
        return const Scaffold(
          body: Center(child: Text('开发者选项未解锁')),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) {
        // 读库失败按未解锁处理，不放行
        _scheduleRedirect();
        return const Scaffold(
          body: Center(child: Text('开发者选项未解锁')),
        );
      },
    );
  }
}
