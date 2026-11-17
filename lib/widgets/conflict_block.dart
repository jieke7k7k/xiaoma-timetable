import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/course.dart';

/// 冲突块外观数据辅助类（WB_SPEC_237 §5）
class ConflictBlockAppearance {
  ConflictBlockAppearance._();

  /// 根据 colorId 获取浅端与深端颜色
  static ({Color light, Color dark}) getColors(String colorId) {
    switch (colorId) {
      case 'mistBlue':
        return (light: const Color(0xFFB9C9D9), dark: const Color(0xFF7E9BB5));
      case 'sage':
        return (light: const Color(0xFFC2CDB4), dark: const Color(0xFF8A9A7A));
      case 'caramel':
      default:
        return (light: const Color(0xFFEBC9A0), dark: const Color(0xFFBE8A5A));
    }
  }

  /// 强度插值：实际深端 = Color.lerp(浅端, 深端, t)。
  ///
  /// App 内冲突块与 PDF 冲突块共用此路径；测试直接断言它（不要直接
  /// 调 Color.lerp，那是框架 API，变异自检「忽略 t」不会变红）。
  /// 注意：新版 Flutter 的 Color.lerp 保留浮点通道（30% 档 R=221.5，
  /// 不四舍五入到 222）；转 8bit 时（如 PDF 的 toARGB32）才进到 222。
  static Color darkEnd(String colorId, double intensity) {
    final colors = getColors(colorId);
    return Color.lerp(colors.light, colors.dark, intensity) ?? colors.dark;
  }
}

/// 冲突课程块组件（WB_SPEC_237 §4.2 & §5）：
/// 支持焦糖/雾蓝/豆沙绿三选、强度线性插值、防真机漫溢的严格毛玻璃效果、
/// 1.5px 虚线分割线以及小屏 (<=600px) 字号降级。
class ConflictBlock extends StatelessWidget {
  const ConflictBlock({
    super.key,
    required this.topCourse,
    required this.bottomCourse,
    required this.height,
    required this.width,
    required this.colorId,
    required this.intensity,
    required this.blurEnabled,
  });

  final Course topCourse;
  final Course bottomCourse;
  final double height;
  final double width;
  final String colorId;
  final double intensity;
  final bool blurEnabled;

  @override
  Widget build(BuildContext context) {
    final baseColors = ConflictBlockAppearance.getColors(colorId);
    final actualDark =
        ConflictBlockAppearance.darkEnd(colorId, intensity);

    final halfHeight = height / 2;
    final hideTeacher = halfHeight < 50;

    // 小屏字号降级判定：按视口宽（<=600px），不是块自身宽——
    // 周视图列宽只有约 50px，用块宽判定会永远走小屏分支。
    final isSmallScreen = MediaQuery.sizeOf(context).width <= 600;
    final tagFontSize = isSmallScreen ? 7.0 : 8.0;
    final nameFontSize = isSmallScreen ? 8.5 : 10.5;
    final metaFontSize = isSmallScreen ? 8.0 : 9.5;
    // 半块内边距 2px 4px（小屏 2px 2px）；标签内边距 0 3px（小屏 0 2px）
    final halfPadding = isSmallScreen
        ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
    final tagPadding = isSmallScreen
        ? const EdgeInsets.symmetric(horizontal: 2, vertical: 0)
        : const EdgeInsets.symmetric(horizontal: 3, vertical: 0);

    final frostColor = baseColors.light.withValues(alpha: 0.55);

    Widget contentChild = Container(
      width: width,
      height: height,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: blurEnabled ? frostColor : null,
        gradient: blurEnabled
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [baseColors.light, actualDark],
              ),
        border: Border.all(color: const Color(0xFF6B7280), width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6.5),
        child: Column(
          children: [
            // 上半：前半学期。中间分隔只用 _DashedBottomPainter 画虚线，
            // 不要再叠一层实线 BorderSide（否则实线会从虚线间隙透出来）。
            Expanded(
              child: Container(
                width: double.infinity,
                padding: halfPadding,
                child: CustomPaint(
                  painter: _DashedBottomPainter(
                      color: const Color(0xFF6B7280), strokeWidth: 1.5),
                  child: _buildHalfContent(
                    course: topCourse,
                    tagText: '前半学期',
                    hideTeacher: hideTeacher,
                    halfHeight: halfHeight,
                    isSmallScreen: isSmallScreen,
                    tagFontSize: tagFontSize,
                    nameFontSize: nameFontSize,
                    metaFontSize: metaFontSize,
                    tagPadding: tagPadding,
                  ),
                ),
              ),
            ),
            // 下半：后半学期
            Expanded(
              child: Container(
                width: double.infinity,
                padding: halfPadding,
                child: _buildHalfContent(
                  course: bottomCourse,
                  tagText: '后半学期',
                  hideTeacher: hideTeacher,
                  halfHeight: halfHeight,
                  isSmallScreen: isSmallScreen,
                  tagFontSize: tagFontSize,
                  nameFontSize: nameFontSize,
                  metaFontSize: metaFontSize,
                  tagPadding: tagPadding,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (blurEnabled) {
      contentChild = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: contentChild,
        ),
      );
    }

    return contentChild;
  }

  Widget _buildHalfContent({
    required Course course,
    required String tagText,
    required bool hideTeacher,
    required double halfHeight,
    required bool isSmallScreen,
    required double tagFontSize,
    required double nameFontSize,
    required double metaFontSize,
    required EdgeInsets tagPadding,
  }) {
    final meta = hideTeacher
        ? (course.classroom ?? '')
        : '${course.classroom ?? ''}${course.teacher != null ? ' · ${course.teacher}' : ''}';
    final tag = Container(
      padding: tagPadding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        tagText,
        style: TextStyle(
          fontSize: tagFontSize,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF4B5563),
          // 标签是纯中文（「前半学期」/「后半学期」，无下行字母），行高
          // 收到 1.1 也不裁字；不收的话字体自然行高约 1.9 倍，38px 半块
          // 的三行会溢出（见三行分支的注释）。
          height: 1.1,
        ),
      ),
    );
    final nameStyle = TextStyle(
      fontSize: nameFontSize,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF1F2937),
      height: 1.25,
    );
    final metaStyle = TextStyle(
      fontSize: metaFontSize,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF374151),
      height: 1.25,
    );
    // 半块太矮（<38px）时两行放不下会溢出（RenderFlex overflow），改成单行：
    // 标签 + 课名 · 教室（老师名已按 <50 规则藏掉）。单节课的冲突块半块
    // 只有约 21px，只能走这一路。
    if (halfHeight < 38) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              tag,
              const SizedBox(width: 4),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: course.name, style: nameStyle),
                      if (meta.isNotEmpty)
                        TextSpan(
                          text: ' · $meta',
                          style: metaStyle,
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      );
    }
    // 半块够高时标签独占一行（与 PDF 的 _conflictHalfWidget 同口径，
    // 规格 §4.2：每半顶部一个小 pill）。三行实测约 28px（小屏，字号
    // 7/8.5/8，标签行高 1.1、行间无间隔）/ 34px（宽屏，字号 8/10.5/9.5）；
    // 半块内容区 = halfHeight − 6.5（外框 margin 1 + 边框 1.5 + 内边距 4，
    // 按半块分摊），所以小屏半块 ≥38px（内容区 31.5px）、宽屏 ≥44px
    // （内容区 37.5px）才走这路；够不着时退回两行（标签+课名同行、
    // 教室一行），课名可能被截断，是既定折中，不要硬改出溢出。
    // PDF 不用改：它一直用小屏字号，三行在 ≥38pt 时放得下。
    if (halfHeight >= (isSmallScreen ? 38 : 44)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          tag,
          Text(
            course.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          ),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            tag,
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                course.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: metaStyle,
        ),
      ],
    );
  }
}

/// 绘制中间 1.5px 虚线分隔的 CustomPainter
class _DashedBottomPainter extends CustomPainter {
  const _DashedBottomPainter({required this.color, required this.strokeWidth});
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    double startX = 0;
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final y = size.height;

    while (startX < size.width) {
      canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
