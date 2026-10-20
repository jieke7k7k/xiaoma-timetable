import 'package:flutter/material.dart';

import '../models/course.dart';
import '../ui/app_styles.dart';
import '../utils/morandi_palette.dart';

/// 周视图课程卡片（莫兰迪底色圆角卡片，展示 课程名、教室、老师三项）
///
/// 跨节次合并时高度由父布局按 (endSection - startSection + 1) 撑高。
/// 单击进入详情，长按弹出编辑/删除菜单。
/// 深色模式下底色经 [MorandiPalette.desaturateForDark] 降饱和降明度，
/// 文字切换为浅色系，保证深色背景上的对比度（阶段五·深色适配）。
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    required this.onLongPress,
    this.dimmed = false,
    this.badgeText,
    this.showNoteDot = false,
  });

  final Course course;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// 置灰状态（设置里开启「显示非本周课程」时使用）
  final bool dimmed;

  /// 右上角角标文字，如同格多课时的「+2」；为空不显示
  final String? badgeText;

  /// 课程有备注时在右上角显示小圆点提示
  final bool showNoteDot;

  bool get _hasBadge =>
      (badgeText != null && badgeText!.isNotEmpty) || showNoteDot;

  @override
  Widget build(BuildContext context) {
    // 深色模式：底色降饱和降明度 + 浅色文字；浅色模式：原色 + 深色文字
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark
        ? MorandiPalette.desaturateForDark(Color(course.colorValue))
        : Color(course.colorValue);
    final titleColor = Color(
        isDark ? MorandiPalette.darkTextColor : MorandiPalette.textColor);
    final subtitleColor = Color(isDark
        ? MorandiPalette.darkSubTextColor
        : MorandiPalette.subTextColor);
    // 角标/备注圆点在深色下反色为浅色块+深字，浅色下保持深色块+白字
    final badgeBg = Color(isDark
        ? MorandiPalette.darkBadgeBackground
        : MorandiPalette.textColor);
    final badgeFg = isDark
        ? Color(MorandiPalette.darkBadgeTextColor)
        : Colors.white;
    return Opacity(
      opacity: dimmed ? 0.35 : 1,
      child: Material(
        color: cardColor,
        // 圆角统一取全局常量（视觉规范：卡片 12px）
        borderRadius: BorderRadius.circular(AppRadii.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                // 名称、教室、老师拼成一个富文本整体展示：单节卡片高度有限时
                // 由 maxLines 统一截断省略，避免多 Text 纵向堆叠溢出
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: course.name,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      if (course.classroom != null &&
                          course.classroom!.isNotEmpty)
                        TextSpan(
                          text: '\n${course.classroom!}',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 10,
                            height: 1.1,
                          ),
                        ),
                      if (course.teacher != null && course.teacher!.isNotEmpty)
                        TextSpan(
                          text: '\n${course.teacher!}',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 10,
                            height: 1.1,
                          ),
                        ),
                    ],
                  ),
                  maxLines:
                      (course.endSection - course.startSection + 1) == 1
                          ? 3
                          : 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 右上角角标区：备注圆点 + 多课「+N」
              if (_hasBadge)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showNoteDot)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: badgeBg,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (showNoteDot &&
                          badgeText != null &&
                          badgeText!.isNotEmpty)
                        const SizedBox(width: 4),
                      if (badgeText != null && badgeText!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            // 卡片角标（+N / 调）是 chip 级小元素，圆角统一取全局常量
                            borderRadius:
                                BorderRadius.circular(AppRadii.chip),
                          ),
                          child: Text(
                            badgeText!,
                            style: TextStyle(
                              color: badgeFg,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
