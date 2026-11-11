import 'package:flutter/material.dart';

/// 带「双色衬底缺口」的圆角输入框边框（WB_SPEC_231 第 11 节）
///
/// 要解决的问题：标签浮到边框上时，横线正好从字中间穿过。标准
/// [OutlineInputBorder] 在标签浮起时**会**在描边上留缺口（gap），所以缺口本身
/// 不是问题；问题是 `filled: true` 的填充块顶边也在 y = rect.top 这条线上——
/// 描边断了，填充色与页面底色的交界线却照旧从字中间划过（规格第 11.2 节核实：
/// 8 处字段都是标准写法、没有外层 Container 边框，真因是这个填充色交界线）。
///
/// 修法（规格采纳的落法 A）：在原生缺口基础上补一层双色衬底——
/// 缺口区域的上半截填页面底色、下半截填框内填充色，分界正好压在边框线所在的
/// y = rect.top 上。这样字中间那道交界线被衬底「抹平」，两侧描边照旧断开，
/// 视觉上就是线从字两边断开、字中间干净留空。
///
/// 只在全局 `inputDecorationTheme` 里替换，业务页面零改动；其余行为
/// （圆角、描边色、空态时标签印在框里）全部继承 [OutlineInputBorder] 原生实现。
class CleanGapOutlineInputBorder extends OutlineInputBorder {
  const CleanGapOutlineInputBorder({
    super.borderSide,
    super.borderRadius,
    // 汉字方块字更饱满，左右各留 6dp 呼吸空白，不贴首尾汉字
    super.gapPadding = 6.0,
    required this.pageBackgroundColor,
    required this.fillColor,
  });

  /// 框外的页面底色（衬底上半截用）
  final Color pageBackgroundColor;

  /// 框内的填充色（衬底下半截用，与 inputDecorationTheme.fillColor 同值）
  final Color fillColor;

  /// 衬底半高：浮动标签正文字号约 16，上下各留一点余量盖住字身
  static const double _backingHalfHeight = 12.0;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    // 先按原生逻辑画描边与填充（缺口由 super 自己让出来）
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
    if (gapStart == null || gapExtent <= 0.0) return;
    // 缺口左右再多铺一点，避免描边端点与衬底之间露出 1px 的填充边
    final left = gapStart - gapPadding;
    final right = gapStart + gapExtent + gapPadding;
    final paint = Paint()..style = PaintingStyle.fill;
    // 上半截：页面底色（与框外一致，做到「这里没有框」）
    canvas.drawRect(
      Rect.fromLTRB(left, rect.top - _backingHalfHeight, right, rect.top),
      paint..color = pageBackgroundColor,
    );
    // 下半截：框内填充色（与框内一致，做到「框内也没多一条线」）
    canvas.drawRect(
      Rect.fromLTRB(left, rect.top, right, rect.top + _backingHalfHeight),
      paint..color = fillColor,
    );
  }

  @override
  CleanGapOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return CleanGapOutlineInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      pageBackgroundColor: pageBackgroundColor,
      fillColor: fillColor,
    );
  }
}
