import 'package:flutter/material.dart';

import 'settings_icon_box.dart';

/// 全 App 统一的弹出菜单项（WB_SPEC_230 第 3.1 节）。
///
/// 三处 ⋮ 菜单（主页顶栏、设置页顶栏、学期行内嵌）共用这一个构造函数，
/// 保证「彩色小底块 + 文字」的行长相完全一致；外壳（圆角 16、米白底、
/// 阴影）由 `main.dart` 的全局 `popupMenuTheme` 统一给，这里不重复设。
///
/// 用法：
/// ```dart
/// buildAppPopupMenuItem<String>(
///   value: '/course-search',
///   icon: Icons.search,
///   category: SettingsIconCategory.schedule,
///   title: '课程搜索',
/// )
/// ```
///
/// 参数：
/// - [value]：菜单项回传值，语义与原 PopupMenuItem 一致（路由 / 动作枚举）；
/// - [icon]：功能图标（20dp 描边图标，由 [SettingsIconBox] 绘制）；
/// - [category]：图标语义色（课表蓝 / 数据绿 / 外观紫 / 提醒橙 / 系统灰 / 删除红）；
/// - [title]：菜单文案（一字不改地沿用原菜单项标题）。
PopupMenuItem<T> buildAppPopupMenuItem<T>({
  required T value,
  required IconData icon,
  required SettingsIconCategory category,
  required String title,
}) {
  return PopupMenuItem<T>(
    value: value,
    child: ListTile(
      leading: SettingsIconBox(icon: icon, category: category),
      title: Text(title),
      // 菜单项自带最小宽度，行内不再叠加上下左右内边距
      contentPadding: EdgeInsets.zero,
    ),
  );
}
