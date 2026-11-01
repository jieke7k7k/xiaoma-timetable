/// 周日收尾弹窗的「已读日期」判定（WB_SPEC_215 第 1 节）。
///
/// 2.1.3 及以前，弹窗是否弹过只记在页面 State 的布尔值里：从主页切到设置
/// 再切回主页，壳内一级视图被换掉、State 重建，标记丢失，弹窗又弹一次。
/// 2.1.4 起改为「按日期记」：把弹过的日期（yyyy-MM-dd）落到 app_settings，
/// 页面重建、切 Tab、杀进程重进读的都是同一个值，同一个周日只弹一次。
///
/// 本文件只放纯函数（不碰库、不碰 UI），单测直接覆盖；
/// 读库/写库由 services/sunday_dialog_service.dart 的 [SundayDialogGate] 负责。
library;

/// 可替换的「现在」时钟：运行时就是 [DateTime.now]。
///
/// 只为测试提供：把日期锁到某个周日，才能在不改系统时间的前提下验证
/// 「同一天不重弹、下个周日重新弹」。生产代码只会读它、从不修改它。
DateTime Function() sundayDialogNow = DateTime.now;

/// 「周日弹窗已读日期」在 app_settings 里的键名，值形如 `2026-11-01`。
const String kSundayDialogShownDateKey = 'sunday_dialog_shown_date';

/// 日期戳（yyyy-MM-dd 本地时间）：只比日期不比时间，
/// 同一个周日的凌晨与深夜算同一天，不会因为跨小时重复弹。
String sundayDialogDateStamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// 今天是否该弹周日收尾弹窗（纯函数，单测直接覆盖）。
///
/// 三条同时成立才弹，与 2.1.3 的判断口径一致，只多了一条「今天还没记过已读」：
/// 1. 今天是周日（`DateTime.sunday`，即 weekday == 7）；
/// 2. 当前正看本周（显示周 == 今天所在周），翻到别的周不打扰；
/// 3. [shownDate] 不等于今天的日期戳——[shownDate] 为 null 表示从未弹过。
///
/// [shownDate] 是从 app_settings 读出来的持久化值，不是内存标记，
/// 所以「切设置 Tab 再切回」「同周日内页面重建」「杀进程重进」都不会重弹。
bool isSundayDialogDue({
  required DateTime now,
  required int displayWeek,
  required int todayWeek,
  String? shownDate,
}) {
  if (now.weekday != DateTime.sunday) return false;
  if (displayWeek != todayWeek) return false;
  return shownDate != sundayDialogDateStamp(now);
}
