import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/app_styles.dart';

/// 应用启动页（阶段五·视觉打磨）
///
/// 纯 Dart 实现的应用内 Splash：品牌 Logo + 应用名 + 一句 slogan，
/// 短暂停留后进入主页。不依赖任何原生启动主题/资源插件，
/// 深浅色跟随 MaterialApp 主题（surface 底色），深色模式无白色闪屏。
///
/// 为什么停留约 1 秒：通知初始化与 Provider 首帧读库都在启动瞬间进行，
/// 启动页既给了品牌展示，也把「读库期间的白屏窗口」兜住。
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  /// 启动页停留时长（毫秒）
  static const int _durationMs = 900;

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // 首帧渲染后再淡入，避免首帧就带动画导致跳变
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    Timer(const Duration(milliseconds: _durationMs), () {
      if (mounted) {
        // 替换路由进入主页，返回键不会退回启动页
        Navigator.pushReplacementNamed(context, '/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 品牌 Logo：圆角色块 + 日历图标
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius:
                              BorderRadius.circular(AppRadii.logo),
                        ),
                        child: Icon(
                          Icons.calendar_month_rounded,
                          size: 48,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.l),
                      Text(
                        '小马课表',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppSpacing.s),
                      Text(
                        '简约 · 零广告的课程表',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 底部细进度圈：告诉用户正在进入，不是卡死
            const Padding(
              padding: EdgeInsets.only(bottom: 48),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
