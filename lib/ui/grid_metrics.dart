/// 课表网格尺寸常量：主页周视图与界面设置页的「1:1 预览」共用同一份定义，
/// 保证预览中的格高、列宽、表头高、节次栏宽与主界面完全一致。
library;

/// 左侧节次栏宽度（px）
const double kTimeAxisWidth = 50;

/// 课表表头行高度（px）：月份列 + 星期/日期列
const double kGridHeaderHeight = 46;

/// 午休 / 晚间分隔带高度（px，1.2.1 起 20→24 容纳时间段文字）；
/// 主页、预览、导出图共用，保证高度守恒计算一致
const double kBandHeight = 24;

/// 一条分隔带：[after] 第几节之后、[label] 名称（午休/晚间）、
/// [interval] 时间段文本（如 12:00–14:00，按作息实时计算，可为空）
typedef GridBand = ({int after, String label, String interval});
