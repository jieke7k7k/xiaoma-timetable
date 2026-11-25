import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/ui_settings.dart';
import '../models/time_slot.dart';
import '../ui/app_styles.dart';
import '../utils/color_schemes.dart';
import '../utils/course_display_formatter.dart';
import '../utils/morandi_palette.dart';

/// 周视图课程卡片（圆角卡片，展示 课程名、教室、老师、备注）
///
/// 跨节次合并时高度由父布局按 (endSection - startSection + 1) 撑高。
/// 单击进入详情，长按弹出编辑/删除菜单（菜单是否可用由周视图编辑模式决定）。
/// 显示色经当前配色方案映射（[displayColorValue]，由调用方用
/// mapCourseColor 算好传入；不传则走统一入口 resolveCourseDisplayColor，
/// 按 [colorScheme]（未传用默认方案）映射后再做深色降饱和）。
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
    this.colorScheme,
    this.cornerRadius = 12,
    this.borderWidth = 0.0,
    this.textScale = 1.0,
    this.showClassroom = true,
    this.showTeacher = true,
    this.showNote = true,
    // WB_SPEC_253 §2：导入后可编辑是否隐藏（默认与 UiSettings 一致）
    this.hideNameMarks = true,
    this.hideCampus = true,
    this.showCellTime = false,
    this.showLocationAt = false,
    this.timeSlots = const [],
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

  /// displayColorValue 为空时 resolveCourseDisplayColor 用的配色方案；
  /// 未传用默认方案（UiSettings 默认 colorSchemeId）。
  final CourseColorScheme? colorScheme;

  /// 圆角半径（界面设置）
  final double cornerRadius;

  /// 是否加粗边框：边框取格子色加深版（界面设置）
  /// 边框粗细 px（0=无边框；颜色取卡片色加深版）
  final double borderWidth;

  /// 文字缩放系数（界面设置）：实际字号 = 基准字号 × 系数
  final double textScale;

  /// 是否显示教室 / 老师 / 备注（界面设置）
  final bool showClassroom;
  final bool showTeacher;
  final bool showNote;

  /// 隐藏课名里的标记（方括号前缀、尾部「N周」与尾部符号），默认开
  final bool hideNameMarks;

  /// 隐藏地点里的校区前缀，默认开
  final bool hideCampus;

  /// 在格子内显示上课时间，默认关
  final bool showCellTime;

  /// 上课地点前显示 @，默认关
  final bool showLocationAt;

  /// 目标学期作息（格子内时间取每节起止）；缺失时不显示时间
  final List<TimeSlot> timeSlots;

  double get _nameSize => 12 * textScale;
  double get _subSize => 10 * textScale;

  @override
  Widget build(BuildContext context) {
    // 深色模式：底色降饱和降明度 + 浅色文字；浅色模式：原色 + 深色文字
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final cardColor = displayColorValue != null
        ? MorandiPalette.desaturateForDark(
            Color(displayColorValue!),
            brightness: brightness,
          )
        : resolveCourseDisplayColor(
            course.colorValue,
            colorScheme ?? const UiSettings().colorScheme,
            brightness,
          );
    // B4：卡片底色本身偏深时（自选了深色课程色），即便浅色模式也改用
    // 浅色文字/角标，边框改提亮一档——避免深底深字看不清
    final useLightText = isDark || cardColor.computeLuminance() < 0.42;
    final titleColor = Color(
      useLightText ? MorandiPalette.darkTextColor : MorandiPalette.textColor,
    );
    final subtitleColor = Color(
      useLightText
          ? MorandiPalette.darkSubTextColor
          : MorandiPalette.subTextColor,
    );
    // 角标在浅字模式下反色为浅色块+深字，否则保持深色块+白字
    final badgeBg = Color(
      useLightText
          ? MorandiPalette.darkBadgeBackground
          : MorandiPalette.textColor,
    );
    final badgeFg = useLightText
        ? Color(MorandiPalette.darkBadgeTextColor)
        : Colors.white;
    // 边框：取「实际显示底色」同色系描边（浅底加深、深底提亮）；粗细无极可调
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cornerRadius),
      side: borderWidth > 0
          ? BorderSide(
              color: useLightText
                  ? lightenColor(cardColor)
                  : darkenColor(cardColor),
              width: borderWidth,
            )
          : BorderSide.none,
    );
    final noteText = course.note?.trim() ?? '';
    // WB_SPEC_253 §2/§3：显示层格式化（只改显示文本，不改库值）；
    // 时间行插在课名之后，进现有 maxLines 预算（矮格截断时课名优先）。
    final displayName = CourseDisplayFormatter.formatCourseName(
      course.name,
      hideNameMarks: hideNameMarks,
    );
    final displayClassroom = showClassroom
        ? CourseDisplayFormatter.formatClassroom(
            course.classroom,
            hideCampus: hideCampus,
            showLocationAt: showLocationAt,
          )
        : '';
    final displayCellTime = showCellTime
        ? CourseDisplayFormatter.formatCellTime(
            startSection: course.startSection,
            endSection: course.endSection,
            timeSlots: timeSlots,
          )
        : '';
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
                        text: displayName,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: _nameSize,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      if (displayCellTime.isNotEmpty)
                        TextSpan(
                          text: '\n$displayCellTime',
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: _subSize,
                            height: 1.1,
                          ),
                        ),
                      if (displayClassroom.isNotEmpty)
                        TextSpan(
                          text: '\n$displayClassroom',
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
                  maxLines: (course.endSection - course.startSection + 1) == 1
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
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
