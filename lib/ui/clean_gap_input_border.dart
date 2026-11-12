import 'dart:ui' as ui show lerpDouble;

import 'package:flutter/material.dart';

/// 「标签留空」圆角输入框边框（WB_SPEC_231 第 12.1 节，落法 1B）
///
/// 要解决的问题：标签浮到边框上时，横线正好从字中间穿过。第 11 节采纳的落法 A
/// 是「保留原生缺口 + 补双色衬底把交界线抹平」，2.3.0 真机上仍不合格——
/// `filled: true` 的填充块顶边与页面底色在 y = rect.top 交汇，描边虽然断了，
/// 色差拼出的台阶线照样从汉字正中横切（2026-11-11 22:04 用户原话：「边框穿过了」）。
///
/// 落法 1B（Argon，以代码为准）：不给描边留缺口，而是**把整个框往下让**——
/// 标签浮起时，填充圆角矩形与完整描边圆角矩形一起下移 `9.0 * gapPercentage`，
/// 标签于是整个站在完整框顶横线的上方，框顶一笔画完、标签脚底与框顶留出可见间隙。
///
/// 具体做法：
/// - 不调 `super.paint()`：否则原生那条带缺口的边框会被再画一遍；
/// - 填充由本边框自画（全局主题里 `filled: false` 把原生填充停掉），
///   避免「原生填充 + 边框自画填充」叠出双层色差；
/// - 描边画**完整**圆角矩形，不留缺口（缺口由标签浮起的位置自然让开）。
///
/// 空态（没聚焦、没内容，标签印在框中间）时 `gapExtent == 0`，`topInset` 归零：
/// 框与填充都停在原位，外观与改前一致。圆角、描边色、五态共用同一 helper，
/// 浅色/深色走同一段代码（[fillColor] 取 `scheme.surfaceContainerHighest`）。
class CleanGapOutlineInputBorder extends OutlineInputBorder {
  const CleanGapOutlineInputBorder({
    super.borderSide,
    super.borderRadius,
    // 汉字方块字更饱满，左右各留 6dp 呼吸空白，不贴首尾汉字
    super.gapPadding = 6.0,
    required this.fillColor,
  });

  /// 框内填充色（原生填充已由 `filled: false` 停掉，改由本边框自画）
  final Color fillColor;

  /// 标签满浮起时整个框（填充 + 描边）下移的距离：`9.0 * gapPercentage`
  ///
  /// 规格正文写「下移 8dp」、代码写 9.0，两处不一致，按规格「以代码为准」取 9.0。
  static const double _topInsetPerGap = 9.0;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    // 只有标签浮起（有缺口）时才让位；空态 gapExtent == 0，框不动、标签照常印在框中间
    final floating = gapStart != null && gapExtent > 0.0 && gapPercentage > 0.0;
    final topInset = floating ? _topInsetPerGap * gapPercentage : 0.0;
    final boxRect = Rect.fromLTRB(
      rect.left,
      rect.top + topInset,
      rect.right,
      rect.bottom,
    );
    final rrect = borderRadius.toRRect(boxRect);
    // 填充：边框自画（全局 filled: false，原生不再铺一层，杜绝双层填充色差）
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    // 描边：完整圆角矩形，一笔画完不留缺口
    if (borderSide.style != BorderSide.none && borderSide.width > 0) {
      canvas.drawRRect(rrect, borderSide.toPaint());
    }
  }

  @override
  CleanGapOutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    Color? fillColor,
  }) {
    return CleanGapOutlineInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
      // 换态（focused/error）时填充色不能丢，否则描边一换就露出原生底色
      fillColor: fillColor ?? this.fillColor,
    );
  }

  /// 焦点切换时 _BorderContainer 用 _InputBorderTween 做插值：begin/end 都是
  /// CleanGap 时必须全程返回 CleanGap，否则父类 OutlineInputBorder.lerpFrom
  /// 会退化成普通 OutlineInputBorder（只画描边不画填充），filled:false 又让
  /// 原生填充停掉，动画约 200ms 内框里是空的、看着先变白再变回来（真机反馈）。
  ///
  /// 三个方法缺一不可：lerpFrom/lerpTo 走同类型插值，scale 兜底（其中一端为
  /// null、或类型不一致时 ShapeBorder.lerp 会调它）。
  @override
  CleanGapOutlineInputBorder scale(double t) {
    return CleanGapOutlineInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
      fillColor: fillColor,
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is CleanGapOutlineInputBorder) {
      return CleanGapOutlineInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: ui.lerpDouble(a.gapPadding, gapPadding, t)!,
        fillColor: Color.lerp(a.fillColor, fillColor, t)!,
      );
    }
    if (a is OutlineInputBorder) {
      return CleanGapOutlineInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: ui.lerpDouble(a.gapPadding, gapPadding, t)!,
        fillColor: Color.lerp(Colors.transparent, fillColor, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is CleanGapOutlineInputBorder) {
      return CleanGapOutlineInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: ui.lerpDouble(gapPadding, b.gapPadding, t)!,
        fillColor: Color.lerp(fillColor, b.fillColor, t)!,
      );
    }
    if (b is OutlineInputBorder) {
      return CleanGapOutlineInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: ui.lerpDouble(gapPadding, b.gapPadding, t)!,
        fillColor: Color.lerp(fillColor, Colors.transparent, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  /// 父类 OutlineInputBorder 的 == 只比 borderSide、borderRadius、gapPadding，
  /// 不认 fillColor：深浅切换时若只变填充色，_BorderContainer 会误判新旧边框
  /// 相等而跳过重绘，背景色卡死在旧颜色。这里把 fillColor 算进去。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is CleanGapOutlineInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding &&
        other.fillColor == fillColor;
  }

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, gapPadding, fillColor);
}
