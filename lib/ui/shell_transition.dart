/// 壳内一级视图切换动效（2026-11-05 用户定：三种都做，做成开关让用户自己选）。
///
/// 切换不够丝滑的根因（Argon 诊断）：旧 AnimatedSwitcher 每次切换都同步销毁
/// 重建整棵 Widget 树（设置页首次 build/layout 掉帧），且两页交叉淡入淡出、
/// 中段各占 50% 透明度叠出重影。
///
/// 三种实现（[ShellTransitionStyle] 三选一，默认柔和）：
/// - **A 灵动＋微位移**（[ParallaxShellBody]）：多页常驻保活，
///   旧页先淡出、新页后淡入（不重叠），16px 水平微位移，240ms；
/// - **B 柔和**（[PageTransitionSwitcher] + [FadeThroughTransition]，
///   animations 包，默认）：220ms，旧页会卸载、滚动位置不保留；
/// - **C 疾速**（[QuickFadeShellBody]）：多页常驻保活、纯透明度 140ms。
///
/// WB_SPEC_238 §2：底栏变三键（今日 / 课表 / 我的），三处动效都按三页处理；
/// 今日视图的空状态「课表」链接经 [ShellTransitionView.onNavigateToSchedule]
/// 切回课表 Tab。
library;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../models/ui_settings.dart';
import '../pages/settings_page.dart';
import '../pages/today_view_page.dart';
import '../pages/week_view_page.dart';
import '../widgets/home_tab_bar.dart';

/// 壳内视图区：按 [ShellTransitionStyle] 三选一。
class ShellTransitionView extends StatelessWidget {
  const ShellTransitionView({
    super.key,
    required this.currentTab,
    required this.style,
    this.onNavigateToSchedule,
  });

  final HomeShellTab currentTab;
  final ShellTransitionStyle style;

  /// 今日视图空状态点「课表」时切回课表 Tab 的回调
  final VoidCallback? onNavigateToSchedule;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case ShellTransitionStyle.fadeThroughParallax:
        return ParallaxShellBody(
          currentTab: currentTab,
          onNavigateToSchedule: onNavigateToSchedule,
        );
      case ShellTransitionStyle.fadeThroughOfficial:
        return PageTransitionSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder:
              (
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
            child: switch (currentTab) {
              HomeShellTab.today => RepaintBoundary(
                child: TodayViewPage(
                  onNavigateToSchedule: onNavigateToSchedule,
                ),
              ),
              HomeShellTab.schedule => const RepaintBoundary(
                child: WeekViewPage(),
              ),
              HomeShellTab.settings => const RepaintBoundary(
                    child: SettingsPage(isEmbeddedInShell: true),
                  ),
            },
          ),
        );
      case ShellTransitionStyle.quickFade:
        return QuickFadeShellBody(
          currentTab: currentTab,
          onNavigateToSchedule: onNavigateToSchedule,
        );
    }
  }
}

/// 底栏三键在动效里的左右顺序：今日 0、课表 1、我的 2。
int _tabIndex(HomeShellTab tab) => switch (tab) {
  HomeShellTab.today => 0,
  HomeShellTab.schedule => 1,
  HomeShellTab.settings => 2,
};

/// A：灵动＋微位移（Argon 方案 A）。
///
/// 三页常驻内存（`Visibility maintainSize/maintainState`＋[RepaintBoundary] 缓存
/// 为 GPU 纹理），切换时 0 重建、0 Layout。透明度错峰：旧页在 t 0.0→0.45
/// 完全淡出，新页在 t 0.35→1.0 淡入，两页永不在 50% 透明度重叠；新页带
/// 16px 水平微位移（点「我的」从右侧滑入、点「今日」从左侧滑入，正好呼应
/// 底栏「今日在左、课表居中、我的在右」），显现的页做 0.985→1.0 微缩放。
///
/// WB_SPEC_238 §2：三页版——每次切换只涉及「旧页→新页」这一对（今日直跳
/// 我的时中间的课表页不参与、不闪现），控制器按「一次切换」走 0→1，
/// 而不是按「位置」走 0→1。
///
/// 注意：Argon 原文未写 dispose，这里补上——控制器不释放会泄漏 Ticker。
class ParallaxShellBody extends StatefulWidget {
  const ParallaxShellBody({
    super.key,
    required this.currentTab,
    this.onNavigateToSchedule,
  });

  final HomeShellTab currentTab;
  final VoidCallback? onNavigateToSchedule;

  @override
  State<ParallaxShellBody> createState() => _ParallaxShellBodyState();
}

class _ParallaxShellBodyState extends State<ParallaxShellBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 当前正在进行的切换：旧页 → 新页（相等表示已落定，无切换在途）。
  HomeShellTab _fromTab = HomeShellTab.schedule;
  HomeShellTab _toTab = HomeShellTab.schedule;

  // 三个页面实例常驻内存，加上 RepaintBoundary 缓存为 GPU 纹理，动画 0 重建开销
  late final List<Widget> _pages = [
    RepaintBoundary(
      child: TodayViewPage(onNavigateToSchedule: widget.onNavigateToSchedule),
    ),
    const RepaintBoundary(child: WeekViewPage()),
    const RepaintBoundary(child: SettingsPage(isEmbeddedInShell: true)),
  ];

  @override
  void initState() {
    super.initState();
    _fromTab = widget.currentTab;
    _toTab = widget.currentTab;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      // 落定态：控制器停在 1，不透明度按 _toTab 直接算满
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant ParallaxShellBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      _fromTab = oldWidget.currentTab;
      _toTab = widget.currentTab;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 某页在切换进度 t 下的透明度（错峰淡出/淡入，中间页不参与）：
  /// 旧页在 t 0.0→0.45 完全淡出；新页在 t 0.35→1.0 淡入。
  double _opacityFor(HomeShellTab tab, double t) {
    if (_fromTab == _toTab) {
      return tab == _toTab ? 1.0 : 0.0;
    }
    if (tab == _fromTab) {
      return (1.0 - (t / 0.45)).clamp(0.0, 1.0);
    }
    if (tab == _toTab) {
      return ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  /// 某页在切换进度 t 下的水平微位移（16px）：
  /// - 旧页往自己那侧滑出（今日向左、我的向右；课表往行进反方向滑出）；
  /// - 新页从自己那侧滑入（今日从左、我的从右；课表从行进方向滑入）。
  double _dxFor(HomeShellTab tab, double eased) {
    final movingRight = _tabIndex(_toTab) > _tabIndex(_fromTab);
    final remain = 1.0 - eased;
    if (tab == _fromTab && _fromTab != _toTab) {
      return switch (tab) {
        HomeShellTab.today => -16.0 * remain,
        HomeShellTab.settings => 16.0 * remain,
        // 课表旧页：往行进反方向滑出（去我的时向左，去今日时向右）
        HomeShellTab.schedule => (movingRight ? -16.0 : 16.0) * remain,
      };
    }
    if (tab == _toTab && _fromTab != _toTab) {
      return switch (tab) {
        HomeShellTab.today => -16.0 * remain,
        HomeShellTab.settings => 16.0 * remain,
        // 课表新页：从行进方向滑入（从今日来时从右，从我的来时从左）
        HomeShellTab.schedule => (movingRight ? 16.0 : -16.0) * remain,
      };
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // 三页各自的透明度（M3 Emphasized Decelerate 曲线映射）
        final opacities = {
          for (final tab in HomeShellTab.values)
            tab: Curves.easeOutCubic.transform(_opacityFor(tab, t)),
        };

        return ColoredBox(
          // 铺一层底色，防止两页交接瞬间漏出黑底
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final tab in HomeShellTab.values)
                // 完全透明时 IgnorePointer 禁用点击，TickerMode 停掉隐藏页动画，
                // ExcludeSemantics 阻断非当前页的读屏焦点穿透（S3-3）
              IgnorePointer(
                  ignoring: widget.currentTab != tab,
                child: ExcludeSemantics(
                  excluding: widget.currentTab != tab,
                  child: Visibility(
                    visible: opacities[tab]! > 0.0,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: TickerMode(
                      enabled: opacities[tab]! > 0.0,
                      child: Opacity(
                          opacity: opacities[tab]!,
                        child: Transform.translate(
                            offset: Offset(_dxFor(tab, opacities[tab]!), 0),
                          child: Transform.scale(
                              // 微缩放（仅对正在显现的页面做 0.985→1.0）
                              scale: 0.985 + 0.015 * opacities[tab]!,
                              child: _pages[_tabIndex(tab)],
                          ),
                        ),
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
/// 三页常驻内存，外包 140ms 纯透明度过渡（不做缩放——缩放会让密集网格的
/// 文字边缘产生重采样锯齿感）。点底栏是为了最快改配置，不是为了看动画。
class QuickFadeShellBody extends StatelessWidget {
  const QuickFadeShellBody({
    super.key,
    required this.currentTab,
    this.onNavigateToSchedule,
  });

  final HomeShellTab currentTab;
  final VoidCallback? onNavigateToSchedule;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: currentTab != HomeShellTab.today,
          child: ExcludeSemantics(
            excluding: currentTab != HomeShellTab.today,
            child: AnimatedOpacity(
              opacity: currentTab == HomeShellTab.today ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              // TickerMode 放在 AnimatedOpacity 内部：淡出动效照常完成，
              // 隐藏页内的 MarqueeText 等 Ticker 立即停转（S3-3）
              child: TickerMode(
                enabled: currentTab == HomeShellTab.today,
                child: RepaintBoundary(
                  child: TodayViewPage(onNavigateToSchedule: onNavigateToSchedule),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          ignoring: currentTab != HomeShellTab.schedule,
          child: ExcludeSemantics(
            excluding: currentTab != HomeShellTab.schedule,
            child: AnimatedOpacity(
              opacity: currentTab == HomeShellTab.schedule ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: TickerMode(
                enabled: currentTab == HomeShellTab.schedule,
                child: const RepaintBoundary(child: WeekViewPage()),
              ),
            ),
          ),
        ),
        IgnorePointer(
          ignoring: currentTab != HomeShellTab.settings,
          child: ExcludeSemantics(
            excluding: currentTab != HomeShellTab.settings,
            child: AnimatedOpacity(
              opacity: currentTab == HomeShellTab.settings ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: TickerMode(
                enabled: currentTab == HomeShellTab.settings,
                child: const RepaintBoundary(
                  child: SettingsPage(isEmbeddedInShell: true),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
