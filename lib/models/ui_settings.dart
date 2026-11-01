import 'dart:convert';

import '../utils/color_schemes.dart';

/// 底部栏形态（WB_SPEC_216 第 1 节）：两种都实现、都贴底不悬浮，用设置项切换。
///
/// - [tab] 图标+文字标签栏（默认）：栏体撑满整宽、贴住屏幕底边，顶部一条 1 像素
///   细分割线，两格等宽——图标在上、文字在下，选中态图标与文字同为琥珀黄；
/// - [capsule] 胶囊贴底：栏体保持胶囊外形（宽度随内容自适应），贴底、无阴影。
///
/// 2.1.5 起删除 2.1.4 的「通栏贴底」（[id] 曾是 `bar`）：旧库里残留的 `bar`
/// 读取时由 [fromId] 回落到 [tab]，绝不出现未知样式导致无栏或崩溃。
///
/// 存库只存 [id]（`tab` / `capsule`），读取用 [fromId] 兜底——
/// 旧数据没有这个字段、或值被改坏（含旧值 `bar`）时一律回 [tab]。
enum BottomBarStyle {
  tab('tab', '新标签栏'),
  capsule('capsule', '胶囊贴底');

  const BottomBarStyle(this.id, this.label);

  /// 持久化用的字符串值（app_settings 的 ui_settings JSON 字段）
  final String id;

  /// 设置页显示的中文名
  final String label;

  /// 字符串 → 枚举；未知值/空值/旧值 `bar` 一律回默认 [BottomBarStyle.tab]
  static BottomBarStyle fromId(String? raw) {
    for (final s in BottomBarStyle.values) {
      if (s.id == raw) return s;
    }
    return BottomBarStyle.tab;
  }
}

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
    this.showBottomBar = true,
    this.bottomBarStyle = BottomBarStyle.tab,
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

  /// 底部悬浮胶囊栏开关（WB_SPEC_213 第 1 节）：主页底部是否显示悬浮胶囊
  /// （课表/设置切换键）。默认开；用户关闭后持久化记忆，下次启动仍保持关闭。
  /// 旧数据无此字段时按默认开兜底，绝不为 null 导致启动白屏。
  final bool showBottomBar;

  /// 底部栏形态（WB_SPEC_216 第 1 节）：新标签栏 / 胶囊贴底，默认新标签栏。
  ///
  /// 只在 [showBottomBar] 为 true 时有意义；关闭底部栏时保留用户上次选择，
  /// 重新打开后恢复同一形态（不重置成默认）。旧数据无此字段、值为 null、
  /// 值为未知字符串（含 2.1.4 的旧值 `bar`）时一律按默认 [BottomBarStyle.tab] 兜底。
  final BottomBarStyle bottomBarStyle;

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
    bool? showBottomBar,
    BottomBarStyle? bottomBarStyle,
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
      showBottomBar: showBottomBar ?? this.showBottomBar,
      bottomBarStyle: bottomBarStyle ?? this.bottomBarStyle,
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
    'showBottomBar': showBottomBar,
    'bottomBarStyle': bottomBarStyle.id,
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
        // 反序列化容错：旧数据无此字段或字段为 null 时一律按默认开兜底（true）
        showBottomBar: bl('showBottomBar', true),
        // 形态容错（WB_SPEC_216 第 1 节）：缺失/null/未知值/2.1.4 旧值 bar
        // 一律回默认「新标签栏」。fromId 内部已兜底，这里再显式把缺失值先落成
        // 'tab' 只是为了语义清楚——两者结果一致。
        bottomBarStyle: BottomBarStyle.fromId(st('bottomBarStyle', 'tab')),
      );
    } catch (_) {
      return const UiSettings();
    }
  }
}
