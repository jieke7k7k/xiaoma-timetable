/// 壳内一级视图切换动效（2026-11-05 用户定：三种都做，做成开关让用户自己选）。
///
/// 切换不够丝滑的根因（Argon 诊断）：旧 AnimatedSwitcher 每次切换都同步销毁
/// 重建整棵 Widget 树（设置页首次 build/layout 掉帧），且两页交叉淡入淡出、
/// 中段各占 50% 透明度叠出重影。
///
/// 三种实现（[ShellTransitionStyle] 三选一，默认柔和）：
/// - **A 灵动＋微位移**（[ParallaxShellBody]）：双页常驻保活，
///   旧页先淡出、新页后淡入（不重叠），16px 水平微位移，240ms；
/// - **B 柔和**（[PageTransitionSwitcher] + [FadeThroughTransition]，
///   animations 包，默认）：220ms，旧页会卸载、滚动位置不保留；
/// - **C 疾速**（[QuickFadeShellBody]）：双页常驻保活、纯透明度 140ms。
library;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../models/ui_settings.dart';
import '../pages/settings_page.dart';
import '../pages/week_view_page.dart';
import '../widgets/home_tab_bar.dart';

/// 壳内视图区：按 [ShellTransitionStyle] 三选一。
class ShellTransitionView extends StatelessWidget {
  const ShellTransitionView({
    super.key,
    required this.currentTab,
    required this.style,
  });

  final HomeShellTab currentTab;
  final ShellTransitionStyle style;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case ShellTransitionStyle.fadeThroughParallax:
        return ParallaxShellBody(currentTab: currentTab);
      case ShellTransitionStyle.fadeThroughOfficial:
        return PageTransitionSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (
            Widget child,
            Animation<double> primaryAnimation,
            Animation<double> secondaryAnimation,
          ) {
            return FadeThroughTransition(
              animation: primaryAnimation,
              secondaryAnimation: secondaryAnimation,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              child: child,
            );
          },
          child: KeyedSubtree(
            key: ValueKey(currentTab),
            child: currentTab == HomeShellTab.schedule
                ? const RepaintBoundary(child: WeekViewPage())
                : const RepaintBoundary(
                    child: SettingsPage(isEmbeddedInShell: true),
                  ),
          ),
        );
      case ShellTransitionStyle.quickFade:
        return QuickFadeShellBody(currentTab: currentTab);
    }
  }
}

/// A：灵动＋微位移（Argon 方案 A）。
///
/// 两页常驻内存（`Visibility maintainSize/maintainState`＋[RepaintBoundary] 缓存
/// 为 GPU 纹理），切换时 0 重建、0 Layout。透明度错峰：课表页在 t 0.0→0.45
/// 完全淡出，设置页在 t 0.35→1.0 淡入，两页永不在 50% 透明度重叠；新页带
/// 16px 水平微位移（点「设置」从右侧滑入、点「课表」从左侧滑入，正好呼应
/// 底栏「课表在左、设置在右」），显现的页做 0.985→1.0 微缩放。
///
/// 注意：Argon 原文未写 dispose，这里补上——控制器不释放会泄漏 Ticker。
class ParallaxShellBody extends StatefulWidget {
  const ParallaxShellBody({super.key, required this.currentTab});

  final HomeShellTab currentTab;

  @override
  State<ParallaxShellBody> createState() => _ParallaxShellBodyState();
}

class _ParallaxShellBodyState extends State<ParallaxShellBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // 两个页面实例常驻内存，加上 RepaintBoundary 缓存为 GPU 纹理，动画 0 重建开销
  late final List<Widget> _pages = const [
    RepaintBoundary(child: WeekViewPage()),
    RepaintBoundary(child: SettingsPage(isEmbeddedInShell: true)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: widget.currentTab == HomeShellTab.schedule ? 0.0 : 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant ParallaxShellBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      if (widget.currentTab == HomeShellTab.settings) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value; // 0.0 = 课表页，1.0 = 设置页

        // 分段透明度（错峰淡出，彻底消除两页半透明重叠的脏乱感）：
        // 课表页在 t 0.0→0.45 期间完全淡出；设置页在 t 0.35→1.0 期间淡入
        final scheduleOpacity = (1.0 - (t / 0.45)).clamp(0.0, 1.0);
        final settingsOpacity = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

        // 曲线映射（M3 Emphasized Decelerate 曲线）
        final easedSchedule = Curves.easeOutCubic.transform(scheduleOpacity);
        final easedSettings = Curves.easeOutCubic.transform(settingsOpacity);

        // 16px 微距水平视差（贴合底栏「左＝课表，右＝设置」的空间直觉）
        final scheduleDx = -16.0 * (1.0 - easedSchedule);
        final settingsDx = 16.0 * (1.0 - easedSettings);

        // 微缩放（仅对正在显现的页面做 0.985→1.0）
        final scheduleScale = 0.985 + 0.015 * easedSchedule;
        final settingsScale = 0.985 + 0.015 * easedSettings;

        return ColoredBox(
          // 铺一层底色，防止两页交接瞬间漏出黑底
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 周课表页（完全透明时 IgnorePointer 禁用点击，但保持挂载不销毁）
              IgnorePointer(
                ignoring: widget.currentTab != HomeShellTab.schedule,
                child: Visibility(
                  visible: easedSchedule > 0.0,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: Opacity(
                    opacity: easedSchedule,
                    child: Transform.translate(
                      offset: Offset(scheduleDx, 0),
                      child: Transform.scale(
                        scale: scheduleScale,
                        child: _pages[0],
                      ),
                    ),
                  ),
                ),
              ),

              // 2. 设置根页
              IgnorePointer(
                ignoring: widget.currentTab != HomeShellTab.settings,
                child: Visibility(
                  visible: easedSettings > 0.0,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: Opacity(
                    opacity: easedSettings,
                    child: Transform.translate(
                      offset: Offset(settingsDx, 0),
                      child: Transform.scale(
                        scale: settingsScale,
                        child: _pages[1],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// C：疾速微淡入（Argon 方案 C，最稳健、零花哨）。
///
/// 两页常驻内存，外包 140ms 纯透明度过渡（不做缩放——缩放会让密集网格的
/// 文字边缘产生重采样锯齿感）。点底栏是为了最快改配置，不是为了看动画。
class QuickFadeShellBody extends StatelessWidget {
  const QuickFadeShellBody({super.key, required this.currentTab});

  final HomeShellTab currentTab;

  @override
  Widget build(BuildContext context) {
    final isSchedule = currentTab == HomeShellTab.schedule;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !isSchedule,
          child: AnimatedOpacity(
            opacity: isSchedule ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: const RepaintBoundary(child: WeekViewPage()),
          ),
        ),
        IgnorePointer(
          ignoring: isSchedule,
          child: AnimatedOpacity(
            opacity: isSchedule ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: const RepaintBoundary(
              child: SettingsPage(isEmbeddedInShell: true),
            ),
          ),
        ),
      ],
    );
  }
}
