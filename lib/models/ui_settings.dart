import 'dart:convert';

import '../utils/color_schemes.dart';

/// 界面设置（1.1.1 新增）：课表格子外观、课程配色方案、主题色、显示字体。
///
/// 整体以 JSON 存 app_settings 的 ui_settings 键；字段都有默认值，
/// 旧版本没有该键或字段缺失时回退默认，保证升级不丢、损坏不崩。
class UiSettings {
  const UiSettings({
    this.cellHeight = 46,
    this.cornerRadius = 12,
    this.showGridLines = true,
    this.boldBorder = false,
    this.axisShowTime = true,
    this.cardTextSize = 1,
    this.showClassroom = true,
    this.showTeacher = true,
    this.showNote = true,
    this.colorSchemeId = 'morandi',
    this.themePresetId = 'forest',
    this.themeCustomColor,
    this.fontId = 'system',
  });

  /// 课程格子高度（逻辑像素 px），范围 44~96；默认 46 与旧版按屏均分的手感接近
  final double cellHeight;

  /// 课程格子圆角半径，范围 0~20，默认 12（与旧版 AppRadii.card 一致）
  final double cornerRadius;

  /// 是否显示网格线，默认显示
  final bool showGridLines;

  /// 是否给课程格子加粗边框（边框取格子色加深版），默认关
  final bool boldBorder;

  /// 左侧节数栏是否显示每节起止时间，默认显示；关掉只留节次数字
  final bool axisShowTime;

  /// 卡片文字大小档位：0 小 / 1 中（默认）/ 2 大
  final int cardTextSize;

  /// 卡片上是否显示教室，默认显示
  final bool showClassroom;

  /// 卡片上是否显示老师，默认显示
  final bool showTeacher;

  /// 卡片上是否显示备注文字一行，默认显示
  final bool showNote;

  /// 课程配色方案 id（见 kCourseColorSchemes），默认 morandi
  final String colorSchemeId;

  /// 主题预置 id（见 kThemePresets），默认 forest（雾绿，即原默认种子色）
  final String themePresetId;

  /// 自定义主题色（ARGB）；非空时优先于主题预置
  final int? themeCustomColor;

  /// 显示字体 id：system 系统默认 / lxgw 霞鹜文楷 / zcool 站酷快乐体
  final String fontId;

  /// 实际生效的主题种子色（ARGB）
  int get themeSeedValue =>
      themeCustomColor ?? themePresetById(themePresetId).seed;

  /// 实际生效的字体 family（系统默认返回 null，走系统字体）
  String? get fontFamily => switch (fontId) {
        'lxgw' => 'LXGWWenKai',
        'zcool' => 'ZCOOLKuaiLe',
        _ => null,
      };

  /// 当前课程配色方案
  CourseColorScheme get colorScheme => courseSchemeById(colorSchemeId);

  UiSettings copyWith({
    double? cellHeight,
    double? cornerRadius,
    bool? showGridLines,
    bool? boldBorder,
    bool? axisShowTime,
    int? cardTextSize,
    bool? showClassroom,
    bool? showTeacher,
    bool? showNote,
    String? colorSchemeId,
    String? themePresetId,
    int? themeCustomColor,
    bool clearThemeCustomColor = false,
    String? fontId,
  }) {
    return UiSettings(
      cellHeight: cellHeight ?? this.cellHeight,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      showGridLines: showGridLines ?? this.showGridLines,
      boldBorder: boldBorder ?? this.boldBorder,
      axisShowTime: axisShowTime ?? this.axisShowTime,
      cardTextSize: cardTextSize ?? this.cardTextSize,
      showClassroom: showClassroom ?? this.showClassroom,
      showTeacher: showTeacher ?? this.showTeacher,
      showNote: showNote ?? this.showNote,
      colorSchemeId: colorSchemeId ?? this.colorSchemeId,
      themePresetId: themePresetId ?? this.themePresetId,
      themeCustomColor:
          clearThemeCustomColor ? null : (themeCustomColor ?? this.themeCustomColor),
      fontId: fontId ?? this.fontId,
    );
  }

  Map<String, dynamic> toJson() => {
        'cellHeight': cellHeight,
        'cornerRadius': cornerRadius,
        'showGridLines': showGridLines,
        'boldBorder': boldBorder,
        'axisShowTime': axisShowTime,
        'cardTextSize': cardTextSize,
        'showClassroom': showClassroom,
        'showTeacher': showTeacher,
        'showNote': showNote,
        'colorSchemeId': colorSchemeId,
        'themePresetId': themePresetId,
        'themeCustomColor': themeCustomColor,
        'fontId': fontId,
      };

  String encode() => jsonEncode(toJson());

  /// 从 JSON 字符串解析；任何异常都回退全默认（设置损坏不能拖垮启动）
  factory UiSettings.fromEncoded(String? raw) {
    if (raw == null || raw.isEmpty) return const UiSettings();
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return const UiSettings();
      double dbl(String k, double dft, double min, double max) {
        final v = map[k];
        if (v is num) return v.toDouble().clamp(min, max);
        return dft;
      }

      bool bl(String k, bool dft) => map[k] is bool ? map[k] as bool : dft;
      String st(String k, String dft) =>
          map[k] is String ? map[k] as String : dft;
      return UiSettings(
        cellHeight: dbl('cellHeight', 46, 44, 96),
        cornerRadius: dbl('cornerRadius', 12, 0, 20),
        showGridLines: bl('showGridLines', true),
        boldBorder: bl('boldBorder', false),
        axisShowTime: bl('axisShowTime', true),
        cardTextSize: (map['cardTextSize'] is int)
            ? (map['cardTextSize'] as int).clamp(0, 2)
            : 1,
        showClassroom: bl('showClassroom', true),
        showTeacher: bl('showTeacher', true),
        showNote: bl('showNote', true),
        colorSchemeId: st('colorSchemeId', 'morandi'),
        themePresetId: st('themePresetId', 'forest'),
        themeCustomColor:
            map['themeCustomColor'] is int ? map['themeCustomColor'] as int : null,
        fontId: st('fontId', 'system'),
      );
    } catch (_) {
      return const UiSettings();
    }
  }
}
