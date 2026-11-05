/// 液态玻璃与丝滑动效常量（WB_SPEC_217 第 1 / 第 2 节）。
///
/// 这一版把「液态玻璃 + 丝滑切换」的所有数字集中在这里，栏体、指示器、按压
/// 回弹、壳切换各取各的，不在页面里散落硬编码——改手感只改本文件，测试也只
/// 断言本文件的常量，避免「代码写 380、测试写 300」这种两边分叉。
///
/// 曲线与时长全部按 Argon 方案落地：
/// - **位移**（指示器滑动）380ms 弹簧曲线，只动位置不动渐变；
/// - **颜色**（图标 / 文字选中态）280ms 减速曲线，与位移彻底分开；
/// - **按压**分两段：按下 90ms 极快缩到 0.92，松手 350ms 弹簧回弹；
/// - **壳切换**260ms（反向 200ms），进入减速、退出加速，叠 0.985→1.0 微缩放。
/// 四条各管各的，绝不用「一条过渡管所有属性」的老办法（渐变插值天然生硬）。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// 毛玻璃模糊半径（逻辑像素，浅色主题）。
///
/// WB_SPEC_218 第 ② 节：从 2.1.6 的 15 重模糊改成 3.5 轻透——sigma 一旦超过
/// 6，12~14sp 汉字笔画就会被糊成色块，栏后课表文字不可读。低端机可降为 0。
const double kLiquidGlassBlurSigmaLight = 3.5;

/// 毛玻璃模糊半径（逻辑像素，深色主题）。
///
/// 深色下透光感更难做，取 4.0 略高于浅色，仍远低于「糊笔画」的 6 阈值。
const double kLiquidGlassBlurSigmaDark = 4.0;

/// 按主题亮度取模糊半径：浅色 3.5、深色 4.0。
double liquidGlassBlurSigma(Brightness brightness) =>
    brightness == Brightness.dark
        ? kLiquidGlassBlurSigmaDark
        : kLiquidGlassBlurSigmaLight;

/// 栏体底色（浅色主题）：白色 58%（`0x94FFFFFF`）。
///
/// 放弃 2.1.6 的 72% 重底色（`surface.withValues(alpha: 0.72)`），改高透染色
/// 玻璃——固定纯白 + 58% 不透明，让底色透出来、栏后课表内容本身仍可读。
const Color kLiquidGlassSurfaceColorLight = Color(0x94FFFFFF);

/// 栏体底色（深色主题）：`#18181C` 64%（`0xA318181C`）。
const Color kLiquidGlassSurfaceColorDark = Color(0xA318181C);

/// 按主题亮度取栏体底色。
Color liquidGlassSurfaceColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? kLiquidGlassSurfaceColorDark
        : kLiquidGlassSurfaceColorLight;

/// 栏体顶部描边（浅色主题）：白色 75% 的内高光。
const Color kLiquidGlassEdgeColorLight = Color(0xBFFFFFFF);

/// 栏体顶部描边（深色主题）：白色 14% 的微白边。
const Color kLiquidGlassEdgeColorDark = Color(0x24FFFFFF);

/// 按主题亮度取栏体顶部描边颜色。
Color liquidGlassEdgeColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? kLiquidGlassEdgeColorDark
        : kLiquidGlassEdgeColorLight;

/// 液态滑动指示器的宽度占栏宽的比例：一块 50% 宽的滑块，两格各占一半。
const double kLiquidIndicatorWidthFactor = 0.5;

/// 液态滑动指示器的高度（栏体 64，上下各留 4）。
const double kLiquidIndicatorHeight = 56;

/// 液态滑块的金黄渐变（浅色主题，WB_SPEC_218 第 ② 节）：
/// `#FFE066 65%` → `#F59F00 45%`（半透明染色，非 2.1.6 的满不透明亮金）。
const List<Color> kLiquidSliderGradientLight = <Color>[
  Color(0xA6FFE066),
  Color(0x73F59F00),
];

/// 液态滑块的金黄渐变（深色主题，WB_SPEC_218 第 ② 节）：
/// `#F59F00 28%` → `#D97706 18%`（低不透明透光），再叠加金色内发光描边
/// （[kLiquidSliderBorderDark]）锁边界，杜绝深色下的「泥浆黄」。
const List<Color> kLiquidSliderGradientDark = <Color>[
  Color(0x47F59F00),
  Color(0x2ED97706),
];

/// 深色主题滑块的描边：`#80FBBF24`（金黄 50% 透明）金色内发光。
const Color kLiquidSliderBorderDark = Color(0x80FBBF24);

/// 浅色主题滑块的描边：白色 70% 高光（沿用 2.1.6 的 `0xB3FFFFFF`）。
const Color kLiquidSliderBorderLight = Color(0xB3FFFFFF);

/// 滑块顶部那一抹高光（浅色主题）。
const List<Color> kLiquidSliderGlossLight = <Color>[
  Color(0x59FFFFFF),
  Color(0x00FFFFFF),
];

/// 滑块顶部高光（深色主题）：压到两成，否则深色底上会显得发白。
const List<Color> kLiquidSliderGlossDark = <Color>[
  Color(0x30FFFFFF),
  Color(0x00FFFFFF),
];

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

/// 标签栏图标尺寸（与 2.1.5 一致的 24）。
const double kLiquidTabIconSize = 24;

// ---------------------------------------------------------------------------
// 壳内一级视图切换（WB_SPEC_217 第 2 节）
// ---------------------------------------------------------------------------

/// 壳切换进入时长：260ms。
const Duration kLiquidShellDuration = Duration(milliseconds: 260);

/// 壳切换返回时长：200ms（返回比进入略快，符合「往回走更急」的手感）。
const Duration kLiquidShellReverseDuration = Duration(milliseconds: 200);

/// 壳切换进入曲线：减速（新视图快速到位后稳住）。
const Cubic kLiquidShellInCurve = Curves.easeOutCubic;

/// 壳切换退出曲线：加速（旧视图尽快让位，不与新视图长时间重叠）。
const Cubic kLiquidShellOutCurve = Curves.easeInCubic;

/// 壳切换微缩放的起始值：0.985 → 1.0。
///
/// 纯淡入时新旧视图中段会各占 50% 透明度叠在一起，课表格子与设置列表
/// 交叉出「重影」；叠一点微缩放让两者有轻微前后关系，重影感就消掉了。
/// 幅度刻意压到 1.5% 以内——超过 2% 就能明显看出「页面在缩放」，喧宾夺主。
const double kLiquidShellScaleBegin = 0.985;

/// 壳内一级视图切换过渡（[AnimatedSwitcher.transitionBuilder]）：
/// 淡入 + [kLiquidShellScaleBegin] → 1.0 微缩放。
///
/// 写成公开函数是为了让测试能直接调它、断言「起始缩放确实是 0.985」，
/// 不用靠肉眼判断「有没有微缩放」。
Widget liquidShellTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: kLiquidShellScaleBegin,
        end: 1.0,
      ).animate(animation),
      child: child,
    ),
  );
}

/// 毛玻璃层的模糊滤镜：只模糊、不染色（saturate 由引擎侧不支持，改由底色补）。
///
/// WB_SPEC_218 第 ② 节起按主题亮度取半径：浅色 3.5、深色 4.0。
ImageFilter liquidGlassImageFilter({required Brightness brightness}) {
  final sigma = liquidGlassBlurSigma(brightness);
  return ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}

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
    Duration duration = kLiquidColorDuration,
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
