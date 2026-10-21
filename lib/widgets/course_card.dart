import 'package:flutter/material.dart';

import '../models/course.dart';
import '../utils/color_schemes.dart';
import '../utils/morandi_palette.dart';

/// 周视图课程卡片（圆角卡片，展示 课程名、教室、老师、备注）
///
/// 跨节次合并时高度由父布局按 (endSection - startSection + 1) 撑高。
/// 单击进入详情，长按弹出编辑/删除菜单（菜单是否可用由周视图编辑模式决定）。
/// 显示色经当前配色方案映射（[displayColorValue]，由调用方用
/// mapCourseColor 算好传入；不传则用课程存储色）。
/// 圆角、边框、字号档位、显示项开关均来自「界面设置」，由调用方传入，
/// 默认值保持 1.1.0 之前的观感，方便其他场景（如预览）直接复用。
/// 深色模式下底色经 [MorandiPalette.desaturateForDark] 降饱和降明度，
/// 文字切换为浅色系，保证深色背景上的对比度。
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    required this.onLongPress,
    this.dimmed = false,
    this.badgeText,
    this.displayColorValue,
    this.cornerRadius = 12,
    this.boldBorder = false,
    this.textScale = 1.0,
    this.showClassroom = true,
    this.showTeacher = true,
    this.showNote = true,
  });

  final Course course;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 置灰状态（设置里开启「显示非本周课程」时使用）
  final bool dimmed;

  /// 右上角角标文字，如同格多课时的「+N」；为空不显示
  final String? badgeText;

  /// 实际显示色（ARGB，已按当前配色方案映射）；为空用课程存储色
  final int? displayColorValue;

  /// 圆角半径（界面设置）
  final double cornerRadius;

  /// 是否加粗边框：边框取格子色加深版（界面设置）
  final bool boldBorder;

  /// 文字缩放系数（界面设置）：实际字号 = 基准字号 × 系数
  final double textScale;

  /// 是否显示教室 / 老师 / 备注（界面设置）
  final bool showClassroom;
  final bool showTeacher;
  final bool showNote;

  double get _nameSize => 12 * textScale;
  double get _subSize => 10 * textScale;

  @override
  Widget build(BuildContext context) {
    // 深色模式：底色降饱和降明度 + 浅色文字；浅色模式：原色 + 深色文字
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = Color(displayColorValue ?? course.colorValue);
    final cardColor =
        isDark ? MorandiPalette.desaturateForDark(baseColor) : baseColor;
    final titleColor = Color(
        isDark ? MorandiPalette.darkTextColor : MorandiPalette.textColor);
    final subtitleColor = Color(isDark
        ? MorandiPalette.darkSubTextColor
        : MorandiPalette.subTextColor);
    // 角标在深色下反色为浅色块+深字，浅色下保持深色块+白字
    final badgeBg = Color(isDark
        ? MorandiPalette.darkBadgeBackground
        : MorandiPalette.textColor);
    final badgeFg = isDark
        ? Color(MorandiPalette.darkBadgeTextColor)
        : Colors.white;
    // 加粗边框：取「实际显示底色」加深一档，同色系描边不跳色
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
      side: boldBorder
          ? BorderSide(color: darkenColor(cardColor), width: 1.4)
          : BorderSide.none,
    );
    final noteText = course.note?.trim() ?? '';
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Material(
        color: cardColor,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          customBorder: shape,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                // 名称、教室、老师、备注拼成一个富文本整体展示：单节卡片高度
                // 有限时由 maxLines 统一截断省略，避免多 Text 纵向堆叠溢出。
                // 备注用斜体小字跟在最后（1.1.1 起替代原右上角小圆点）。
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: course.name,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: _nameSize,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      if (showClassroom &&
                          course.classroom != null &&
                          course.classroom!.isNotEmpty)
                        TextSpan(
                          text: '\n${course.classroom!}',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: _subSize,
                            height: 1.1,
                          ),
                        ),
                      if (showTeacher &&
                          course.teacher != null &&
                          course.teacher!.isNotEmpty)
                        TextSpan(
                          text: '\n${course.teacher!}',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: _subSize,
                            height: 1.1,
                          ),
                        ),
                      if (showNote && noteText.isNotEmpty)
                        TextSpan(
                          text: '\n$noteText',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: _subSize,
                            fontStyle: FontStyle.italic,
                            height: 1.1,
                          ),
                        ),
                    ],
                  ),
                  maxLines:
                      (course.endSection - course.startSection + 1) == 1
                          ? 4
                          : 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 右上角角标（多课「+N」/ 调课「调」）
              if (badgeText != null && badgeText!.isNotEmpty)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText!,
                      style: TextStyle(
                        color: badgeFg,
                        fontSize: (10 * textScale).clamp(8.0, 13.0),
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
