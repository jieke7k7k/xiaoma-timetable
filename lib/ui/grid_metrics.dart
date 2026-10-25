/// 课表网格尺寸常量：主页周视图与界面设置页的「1:1 预览」共用同一份定义，
/// 保证预览中的格高、列宽、表头高、节次栏宽与主界面完全一致。
///
/// 2.0.8（WB_SPEC_209 第 6 节）起同时承载「休息时段设置」模型与分隔带纯函数
/// （[BandSettings] / [computeActiveBands]），供主页周视图与导出图片同源调用。
library;

/// 左侧节次栏宽度（px）
const double kTimeAxisWidth = 50;

/// 课表表头行高度（px）：月份列 + 星期/日期列
const double kGridHeaderHeight = 46;

/// 午休 / 晚间分隔带高度（px，1.2.1 起 20→24 容纳时间段文字）；
/// 主页、预览、导出图共用，保证高度守恒计算一致
const double kBandHeight = 24;

/// 主页底栏高度（px）：与 main.dart 的 `_HomeBottomBar` SizedBox 同高。
/// 2.0.2（WB-202 第 1 项）起课表网格不再按它留底部内边距——底栏三键改等大
/// 平铺后没有凸起按钮，课表区直接贴合底栏；本常量仅用于底栏自身高度。
const double kBottomBarHeight = 72;

/// 一条分隔带：[after] 第几节之后、[label] 名称（午休/晚间）、
/// [interval] 时间段文本（如 12:00–14:00，可为空）
typedef GridBand = ({int after, String label, String interval});

/// 休息时段设置（WB_SPEC_209 第 6 节）：午休 / 晚间各自的显隐开关与自定义起止时间。
///
/// 纯数据模型，与「分段点」（第几节之后）分离：分段点决定分隔带位置，
/// 这里决定带子显隐与标注时间。默认值与旧版从前后节次时间推导出的观感一致
/// （午休 12:00–14:00、晚间 17:10–18:00，两条都默认显示），老用户升级不突变。
class BandSettings {
  final bool lunchVisible;
  final bool dinnerVisible;
  final String lunchStart;
  final String lunchEnd;
  final String dinnerStart;
  final String dinnerEnd;

  const BandSettings({
    this.lunchVisible = true,
    this.dinnerVisible = true,
    this.lunchStart = '12:00',
    this.lunchEnd = '14:00',
    this.dinnerStart = '17:10',
    this.dinnerEnd = '18:00',
  });

  BandSettings copyWith({
    bool? lunchVisible,
    bool? dinnerVisible,
    String? lunchStart,
    String? lunchEnd,
    String? dinnerStart,
    String? dinnerEnd,
  }) =>
      BandSettings(
        lunchVisible: lunchVisible ?? this.lunchVisible,
        dinnerVisible: dinnerVisible ?? this.dinnerVisible,
        lunchStart: lunchStart ?? this.lunchStart,
        lunchEnd: lunchEnd ?? this.lunchEnd,
        dinnerStart: dinnerStart ?? this.dinnerStart,
        dinnerEnd: dinnerEnd ?? this.dinnerEnd,
      );
}

/// "HH:mm" → 当天分钟数；格式非法或数值越界（时 >23 / 分 >59）返回 null。
int? bandTimeToMinutes(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// 起止时间是否合法：开始必须早于结束。任一非法（含空串）视为不合法。
bool bandRangeValid(String start, String end) {
  final s = bandTimeToMinutes(start);
  final e = bandTimeToMinutes(end);
  if (s == null || e == null) return false;
  return s < e;
}

/// 由分段设置 + 休息时段设置算出生效的分隔带列表（纯函数）。
///
/// 主页周视图与导出图片共用这一份口径：
/// - 关闭的带子不进入结果——不占位、不画线、不占高度，节次连续排列；
/// - 开启的带子 [GridBand.interval] 直接用自定义起止时间（不再从前后节次推导）；
/// - 只保留 after < [sectionCount] 的带子（与旧版过滤口径一致）；
/// - 结果按「午休在前、晚间在后」排列（分段点本身保证 lunch < dinner，此处兜底顺序稳定）。
List<GridBand> computeActiveBands({
  required int lunchAfter,
  required int dinnerAfter,
  required int sectionCount,
  required BandSettings settings,
}) {
  final bands = <GridBand>[];
  if (settings.lunchVisible && lunchAfter < sectionCount) {
    bands.add((
      after: lunchAfter,
      label: '午休',
      interval: '${settings.lunchStart}–${settings.lunchEnd}',
    ));
  }
  if (settings.dinnerVisible && dinnerAfter < sectionCount) {
    bands.add((
      after: dinnerAfter,
      label: '晚间',
      interval: '${settings.dinnerStart}–${settings.dinnerEnd}',
    ));
  }
  return bands;
}
