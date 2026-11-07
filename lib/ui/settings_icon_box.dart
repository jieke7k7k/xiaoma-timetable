import 'package:flutter/material.dart';

import 'app_styles.dart';

/// 设置页入口行图标：语义化分组柔和彩色底块（WB_SPEC_222，Argon 方案形态 C）。
///
/// 形态：32×32 圆角方块底（圆角走 [AppRadii.chip]=10）＋ 20dp 描边图标。
/// 颜色：全站只用 5 个语义色；方块底色＝基色经 `Color.lerp(base, primary, 0.15)`
/// 注入 15% 当前主题色，再按深浅取透明度（浅色 0.18／深色 0.22，system 组浅色 0.12／
/// 深色 0.18）；图标本身用深色系（浅色）／浅色系（深色），绝对不用纯白
/// （描边图标配纯白显得空心）。
///
/// 色值一律写进枚举，业务页面不许写死 `Color(0xFF...)`（换主题翻车）。
enum SettingsIconCategory {
  /// 课表与学期：蓝。
  schedule(
    base: Color(0xFF4A90D9),
    lightIcon: Color(0xFF2F6BB3),
    darkIcon: Color(0xFF7AB3F0),
  ),

  /// 外观：紫。
  appearance(
    base: Color(0xFF8E44AD),
    lightIcon: Color(0xFF7A3B9B),
    darkIcon: Color(0xFFB07BD0),
  ),

  /// 提醒：橙。
  reminder(
    base: Color(0xFFF39C12),
    lightIcon: Color(0xFFD35400),
    darkIcon: Color(0xFFF5A623),
  ),

  /// 备份恢复：绿。
  data(
    base: Color(0xFF27AE60),
    lightIcon: Color(0xFF1E8449),
    darkIcon: Color(0xFF58D68D),
  ),

  /// 关于／系统：灰。方块底透明度比其余四组低一档（灰底太重会发脏）。
  system(
    base: Color(0xFF7F8C8D),
    lightIcon: Color(0xFF616A6B),
    darkIcon: Color(0xFFAEB6BF),
  );

  const SettingsIconCategory({
    required this.base,
    required this.lightIcon,
    required this.darkIcon,
  });

  /// 语义基色（方块底色的起点，注入 15% primary 后再取透明度）。
  final Color base;

  /// 浅色模式下的图标色。
  final Color lightIcon;

  /// 深色模式下的图标色。
  final Color darkIcon;

  // 方块底透明度（222 复审优化建议 2：魔法数提为具名常量，改透明度只动一处）。
  static const double _alphaStandardLight = 0.18;
  static const double _alphaStandardDark = 0.22;
  static const double _alphaSystemLight = 0.12;
  static const double _alphaSystemDark = 0.18;

  /// 方块底透明度：浅色 0.18／深色 0.22，system 组浅色 0.12／深色 0.18。
  double backgroundAlpha(bool isDark) {
    if (this == SettingsIconCategory.system) {
      return isDark ? _alphaSystemDark : _alphaSystemLight;
    }
    return isDark ? _alphaStandardDark : _alphaStandardLight;
  }
}

/// 设置入口行 leading／secondary 通用图标盒（WB_SPEC_222）。
///
/// `settings_page.dart` 与 `settings_sections.dart` 共用这一个组件，
/// 保证设置首页与各二级页风格统一。
class SettingsIconBox extends StatelessWidget {
  const SettingsIconBox({
    super.key,
    required this.icon,
    required this.category,
  });

  final IconData icon;
  final SettingsIconCategory category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    // 注入 15% 当前主题色：换主题时 5 组色跟着带一点主题色调，
    // 既有区分又像同一套调色盘出品（Argon 避坑清单第 2 条）。
    final blended = Color.lerp(category.base, scheme.primary, 0.15)!;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: blended.withValues(alpha: category.backgroundAlpha(isDark)),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Icon(
        icon,
        size: 20,
        color: isDark ? category.darkIcon : category.lightIcon,
      ),
    );
  }
}
