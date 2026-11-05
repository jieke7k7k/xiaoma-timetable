/// 底部栏选中态与丝滑动效常量（WB_SPEC_217 第 1 节；2026-11-05 用户反馈后
/// 按 Argon Q1 方案改为「无框」选中态）。
///
/// 这一版把「选中指示 + 丝滑切换」的所有数字集中在这里，栏体、指示器、按压
/// 回弹各取各的，不在页面里散落硬编码——改手感只改本文件，测试也只
/// 断言本文件的常量，避免「代码写 380、测试写 300」这种两边分叉。
///
/// 曲线与时长全部按 Argon 方案落地：
/// - **选中指示**（底部 20×3 小短条）320ms 减速曲线，只动位置不动颜色；
/// - **图标位移 / 缩放** 380ms 弹簧曲线，与指示器分开；
/// - **颜色**（图标选中态）280ms 减速曲线，与位移彻底分开；
/// - **文字**（字重 / 颜色）180ms 微过渡；
/// - **按压**分两段：按下 90ms 极快缩到 0.92，松手 350ms 弹簧回弹。
/// 三条各管各的，绝不用「一条过渡管所有属性」的老办法（渐变插值天然生硬）。
///
/// 2.1.7 同版本修复：毛玻璃层已整体删除（`BackdropFilter` 在真机上整屏漫溢，
/// 整片课表蒙雾），本文件不再有任何模糊半径与滤镜；金黄滑块也已删除
/// （2026-11-05 用户反馈「选中框」——任何包住图标/文字的色块都不要，
/// 选中态只剩实心图标 + 微放大 + 主题色文字 + 底部小短条）。
/// 壳切换动效（旧 260ms 淡入＋0.985 微缩放）也已删除，见
/// `lib/ui/shell_transition.dart`（三种动效开关）。
library;

import 'package:flutter/widgets.dart';

/// 选中指示小短条的宽度：20dp（Argon 方案 Q1：无框选中态的唯一指示器，
/// 颜色取主题 primary，不再是固定金黄）。
const double kSelectionPillWidth = 20;

/// 选中指示小短条的高度：3dp，两端半圆（半径 1.5dp）。
const double kSelectionPillHeight = 3;

/// 选中指示小短条距栏底的距离：5dp。
const double kSelectionPillBottomGap = 5;

/// 选中指示小短条滑动时长：320ms（Argon 方案 Q1）。
const Duration kSelectionPillDuration = Duration(milliseconds: 320);

/// 选中指示小短条滑动曲线：减速曲线（Argon 方案 Q1）。
const Cubic kSelectionPillCurve = Curves.easeOutCubic;

/// 选中指示器容器宽度占栏宽的比例：小短条放在 50% 宽的容器里水平居中，
/// 容器随选中项在左右两格之间滑动（AnimatedAlign -1/+1），短条本身不贴边。
const double kLiquidIndicatorWidthFactor = 0.5;

/// 指示器滑动时长：380ms（Argon 方案）。
const Duration kLiquidSlideDuration = Duration(milliseconds: 380);

/// 指示器滑动曲线：弹簧曲线（Argon 方案）：
/// Web 侧 `cubic-bezier(0.34, 1.56, 0.64, 1)` 的 Flutter 等价写法。
///
/// 末端过冲（1.56）是「液态」的手感来源——滑块到位时会轻轻弹一下再停住，
/// 而不是匀速到达后戛然而止。
const Cubic kLiquidSpringCurve = Cubic(0.34, 1.56, 0.64, 1.0);

/// 颜色过渡时长：280ms（Argon 方案要求 260~280ms 减速曲线）。
const Duration kLiquidColorDuration = Duration(milliseconds: 280);

/// 颜色过渡曲线：减速曲线，与位移的弹簧曲线分开。
const Cubic kLiquidColorCurve = Curves.easeOutCubic;

/// 按压下沉时长：90ms 极快（Argon 方案要求 80~90ms）。
const Duration kLiquidPressDownDuration = Duration(milliseconds: 90);

/// 松手回弹时长：350ms 弹簧（Argon 方案要求 350~380ms）。
const Duration kLiquidPressUpDuration = Duration(milliseconds: 350);

/// 按下态缩放：0.92。
const double kLiquidPressedScale = 0.92;

/// 选中态图标的放大倍率（微微放大，不是明显放大）。
const double kLiquidActiveIconScale = 1.08;

/// 选中态图标的上浮距离（逻辑像素，负值向上）。
const double kLiquidActiveIconLift = -1.5;

/// 标签栏图标尺寸：23dp（Argon 方案 Q1）。
const double kLiquidTabIconSize = 23;

/// 文字过渡时长：180ms 微过渡（Argon 方案 Q1：字重 / 颜色一起过渡）。
const Duration kLiquidLabelDuration = Duration(milliseconds: 180);

// ---------------------------------------------------------------------------
// 颜色 / 位移分开过渡的两个小组件（Argon 方案第 2 条）
// ---------------------------------------------------------------------------

/// 颜色可过渡的图标（WB_SPEC_217 第 1 节）。
///
/// 选中态图标要有 280ms 减速曲线，而 Flutter 没有现成的「AnimatedIcon 颜色」
/// 组件（[Icon] 的颜色是构造参数，直接换会硬切）。这里用
/// [ImplicitlyAnimatedWidget] + [ColorTween] 自己做一个，与官方
/// [AnimatedContainer] 同一套写法：首帧直接给目标色（不是从透明渐入），
/// 之后每次换色都从**当前动画值**继续过渡到新色。
///
/// 图标的位移（上浮）与缩放由外层 [AnimatedSlide] / [AnimatedScale] 负责，
/// 与颜色彻底分开——这就是「不要一条过渡管所有属性」的落地。
class LiquidIcon extends ImplicitlyAnimatedWidget {
  const LiquidIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = kLiquidTabIconSize,
    Duration duration = kLiquidColorDuration,
    Curve curve = kLiquidColorCurve,
  }) : super(duration: duration, curve: curve);

  final IconData icon;

  /// 目标颜色（选中金黄系 / 未选中灰）
  final Color color;

  final double size;

  @override
  ImplicitlyAnimatedWidgetState<LiquidIcon> createState() => _LiquidIconState();
}

class _LiquidIconState extends AnimatedWidgetBaseState<LiquidIcon> {
  ColorTween? _color;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _color =
        visitor(
              _color,
              widget.color,
              (dynamic value) => ColorTween(begin: value as Color?),
            )
            as ColorTween?;
  }

  @override
  Widget build(BuildContext context) {
    return Icon(widget.icon, size: widget.size, color: _color?.evaluate(animation));
  }
}

/// 颜色可过渡的文字（WB_SPEC_217 第 1 节）：与 [LiquidIcon] 同一套写法，
/// 换用 [TextStyleTween]，把 fontSize / fontWeight / color 一起过渡。
///
/// 不用 [AnimatedDefaultTextStyle] 是因为要让 [Text] 自己带着 style——
/// 现有测试直接读 [Text.style] 的颜色，交给 DefaultTextStyle 继承就取不到了。
class LiquidLabel extends ImplicitlyAnimatedWidget {
  const LiquidLabel({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow,
    Duration duration = kLiquidLabelDuration,
    Curve curve = kLiquidColorCurve,
  }) : super(duration: duration, curve: curve);

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  ImplicitlyAnimatedWidgetState<LiquidLabel> createState() =>
      _LiquidLabelState();
}

class _LiquidLabelState extends AnimatedWidgetBaseState<LiquidLabel> {
  TextStyleTween? _style;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _style =
        visitor(
              _style,
              widget.style,
              (dynamic value) => TextStyleTween(begin: value as TextStyle),
            )
            as TextStyleTween?;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: _style?.evaluate(animation),
    );
  }
}
