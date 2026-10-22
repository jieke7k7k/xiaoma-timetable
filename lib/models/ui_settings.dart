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
    this.showGridLines = false,
    this.borderWidth = 0.0,
    this.axisShowTime = true,
    this.cardTextScale = 1.0,
    this.showClassroom = true,
    this.showTeacher = true,
    this.showNote = true,
    this.colorSchemeId = 'macaron',
    this.themePresetId = 'cocoa',
    this.themeCustomColor,
    this.fontId = 'system',
    this.showParityLabel = true,
    this.showWeekParity = false,
    this.showClassBroadcast = false,
    this.autoFitHeight = true,
    this.highlightTodayColumn = false,
  });

  /// 课程格子高度（逻辑像素 px），范围 44~96；默认 46 与旧版按屏均分的手感接近
  final double cellHeight;

  /// 课程格子圆角半径，范围 0~20，默认 12（与旧版 AppRadii.card 一致）
  final double cornerRadius;

  /// 是否显示网格线（1.2.5 起默认关，新用户首开更干净）
  final bool showGridLines;

  /// 课程格子边框粗细 px（1.2.1 起由「加粗开关」改无极调节）：0~3，默认 0=无边框。
  /// 边框颜色取格子色加深版。旧版 boldBorder=true 迁移为 1.4（旧版加粗的实际宽度）。
  final double borderWidth;

  /// 边框粗细范围与旧版加粗宽度
  static const double borderWidthMin = 0.0;
  static const double borderWidthMax = 3.0;
  static const double legacyBoldBorderWidth = 1.4;

  /// 左侧节数栏是否显示每节起止时间，默认显示；关掉只留节次数字
  final bool axisShowTime;

  /// 卡片文字缩放系数（1.2.0 起由三档改无极调节）：0.8~1.3，默认 1.0。
  /// 课名基准 12、副文本基准 10，实际字号 = 基准 × 系数。
  final double cardTextScale;

  /// 字号缩放系数范围
  static const double textScaleMin = 0.8;
  static const double textScaleMax = 1.3;

  /// 旧版三档（小/中/大）迁移到最接近的缩放系数
  static double scaleFromLegacyLevel(int level) => switch (level.clamp(0, 2)) {
    0 => 0.92,
    2 => 1.08,
    _ => 1.0,
  };

  /// 卡片上是否显示教室，默认显示
  final bool showClassroom;

  /// 卡片上是否显示老师，默认显示
  final bool showTeacher;

  /// 卡片上是否显示备注文字一行，默认显示
  final bool showNote;

  /// 课程配色方案 id（见 kCourseColorSchemes），默认 macaron 马卡龙·甜心（1.2.5）
  final String colorSchemeId;

  /// 主题预置 id（见 kThemePresets），默认 cocoa 可可棕（1.2.5；此前为 forest 雾绿）
  final String themePresetId;

  /// 自定义主题色（ARGB）；非空时优先于主题预置
  final int? themeCustomColor;

  /// 显示字体 id：system 系统默认 / lxgw 霞鹜文楷 / zcool 站酷快乐体 /
  /// smiley 得意黑 / noto 思源黑体；imp_ 开头为用户导入字体（见 FontsService）
  final String fontId;

  /// 标题是否显示单双周（1.2.3）。2.0.1 起已由 [showWeekParity] 取代——
  /// 保留此字段只为兼容老用户已存的旧值，不再参与界面显示。
  final bool showParityLabel;

  /// 标题是否显示单双周后缀（2.0.1 起接管原 showParityLabel 的职责）：
  /// 开时左上角标题为「第 X 周 · 单周/双周」，关时只显示「第 X 周」。默认关。
  ///
  /// 2.0.0 时这个字段管的是左上角那枚「单周/双周」小药丸，与标题里的后缀重复；
  /// 2.0.1 删掉药丸、由它统一控制标题后缀，默认改为关（只影响没手动改过的用户）。
  final bool showWeekParity;

  /// 主页顶部是否显示上课播报（当前/下一节课状态条，2.0.1），默认关。
  /// 只影响主页顶部那条播报条，常驻通知不受此开关控制。
  final bool showClassBroadcast;

  /// 行高自适应一屏（1.2.3）：开启后按可用高度均分行高、整表恰好一屏，
  /// 此时格子高度设置不生效；1.2.5 起默认开（新用户首开即一屏）
  final bool autoFitHeight;

  /// 今天整列边框高亮开关（1.2.6）：1.2.5 的整列边框改为可关，默认关
  final bool highlightTodayColumn;

  /// 实际生效的主题种子色（ARGB）
  int get themeSeedValue =>
      themeCustomColor ?? themePresetById(themePresetId).seed;

  /// 实际生效的字体 family（系统默认返回 null，走系统字体）
  String? get fontFamily => switch (fontId) {
    'lxgw' => 'LXGWWenKai',
    'zcool' => 'ZCOOLKuaiLe',
    'smiley' => 'SmileySans',
    'noto' => 'NotoSansSC',
    _ => null,
  };

  /// 当前课程配色方案
  CourseColorScheme get colorScheme => courseSchemeById(colorSchemeId);

  UiSettings copyWith({
    double? cellHeight,
    double? cornerRadius,
    bool? showGridLines,
    double? borderWidth,
    bool? axisShowTime,
    double? cardTextScale,
    bool? showClassroom,
    bool? showTeacher,
    bool? showNote,
    String? colorSchemeId,
    String? themePresetId,
    int? themeCustomColor,
    bool clearThemeCustomColor = false,
    String? fontId,
    bool? showParityLabel,
    bool? showWeekParity,
    bool? showClassBroadcast,
    bool? autoFitHeight,
    bool? highlightTodayColumn,
  }) {
    return UiSettings(
      cellHeight: cellHeight ?? this.cellHeight,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      showGridLines: showGridLines ?? this.showGridLines,
      borderWidth: borderWidth ?? this.borderWidth,
      axisShowTime: axisShowTime ?? this.axisShowTime,
      cardTextScale: cardTextScale ?? this.cardTextScale,
      showClassroom: showClassroom ?? this.showClassroom,
      showTeacher: showTeacher ?? this.showTeacher,
      showNote: showNote ?? this.showNote,
      colorSchemeId: colorSchemeId ?? this.colorSchemeId,
      themePresetId: themePresetId ?? this.themePresetId,
      themeCustomColor: clearThemeCustomColor
          ? null
          : (themeCustomColor ?? this.themeCustomColor),
      fontId: fontId ?? this.fontId,
      showParityLabel: showParityLabel ?? this.showParityLabel,
      showWeekParity: showWeekParity ?? this.showWeekParity,
      showClassBroadcast: showClassBroadcast ?? this.showClassBroadcast,
      autoFitHeight: autoFitHeight ?? this.autoFitHeight,
      highlightTodayColumn: highlightTodayColumn ?? this.highlightTodayColumn,
    );
  }

  Map<String, dynamic> toJson() => {
    'cellHeight': cellHeight,
    'cornerRadius': cornerRadius,
    'showGridLines': showGridLines,
    'borderWidth': borderWidth,
    'axisShowTime': axisShowTime,
    'cardTextScale': cardTextScale,
    'showClassroom': showClassroom,
    'showTeacher': showTeacher,
    'showNote': showNote,
    'colorSchemeId': colorSchemeId,
    'themePresetId': themePresetId,
    'themeCustomColor': themeCustomColor,
    'fontId': fontId,
    'showParityLabel': showParityLabel,
    'showWeekParity': showWeekParity,
    'showClassBroadcast': showClassBroadcast,
    'autoFitHeight': autoFitHeight,
    'highlightTodayColumn': highlightTodayColumn,
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
        showGridLines: bl('showGridLines', false),
        // 新键优先；缺失时读旧版加粗开关迁移（开=1.4px，关=无边框）
        borderWidth: (map['borderWidth'] is num)
            ? (map['borderWidth'] as num).toDouble().clamp(
                borderWidthMin,
                borderWidthMax,
              )
            : (bl('boldBorder', false) ? legacyBoldBorderWidth : 0.0),
        axisShowTime: bl('axisShowTime', true),
        // 新键优先；缺失时读旧版三档并迁移，老设置不丢
        cardTextScale: (map['cardTextScale'] is num)
            ? (map['cardTextScale'] as num).toDouble().clamp(
                textScaleMin,
                textScaleMax,
              )
            : (map['cardTextSize'] is int)
            ? scaleFromLegacyLevel(map['cardTextSize'] as int)
            : 1.0,
        showClassroom: bl('showClassroom', true),
        showTeacher: bl('showTeacher', true),
        showNote: bl('showNote', true),
        colorSchemeId: st('colorSchemeId', 'macaron'),
        themePresetId: st('themePresetId', 'cocoa'),
        themeCustomColor: map['themeCustomColor'] is int
            ? map['themeCustomColor'] as int
            : null,
        fontId: st('fontId', 'system'),
        showParityLabel: bl('showParityLabel', true),
        showWeekParity: bl('showWeekParity', false),
        showClassBroadcast: bl('showClassBroadcast', false),
        autoFitHeight: bl('autoFitHeight', true),
        highlightTodayColumn: bl('highlightTodayColumn', false),
      );
    } catch (_) {
      return const UiSettings();
    }
  }
}
