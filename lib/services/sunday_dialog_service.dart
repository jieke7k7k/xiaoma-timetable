import '../database/dao.dart';
import '../utils/sunday_dialog.dart';

/// 周日收尾弹窗的判定与落库（WB_SPEC_215 第 1 节）。
///
/// 只做两件事：
/// - [shouldShow]：读 app_settings 里记下的「已读日期」，配合纯函数
///   [isSundayDialogDue] 判断今天要不要弹；
/// - [markShown]：把今天记为已读（写在弹窗弹出的那一刻，所以「知道了」
///   「看下周」「点弹窗外区域关闭」三种关闭方式等效）。
///
/// 关键点：判定依据是**持久化的日期**，不是页面 State 的布尔值。
/// 主页与设置之间来回切时壳内视图会被重建，但库里那行日期还在，
/// 同一天不会再弹；到了下一个周日日期变了，自然重新弹一次。
class SundayDialogGate {
  /// [clock] 只为单测注入固定日期；不传则每次判定都读 [sundayDialogNow]
  /// （运行时即 [DateTime.now]，测试可临时替换）。
  SundayDialogGate({DateTime Function()? clock}) : _clock = clock;

  final DateTime Function()? _clock;

  /// 当前时间（注入优先，否则读全局时钟）
  DateTime _now() => (_clock ?? sundayDialogNow)();

  /// 今天该不该弹（今天是周日 + 正看本周 + 今天还没记过已读）。
  Future<bool> shouldShow({
    required int displayWeek,
    required int todayWeek,
  }) async {
    final now = _now();
    // 先跑纯条件：不是周日或不在本周就直接返回，不必多读一次库
    if (!isSundayDialogDue(
      now: now,
      displayWeek: displayWeek,
      todayWeek: todayWeek,
    )) {
      return false;
    }
    final shownDate = await Dao.instance.getSetting(kSundayDialogShownDateKey);
    return isSundayDialogDue(
      now: now,
      displayWeek: displayWeek,
      todayWeek: todayWeek,
      shownDate: shownDate,
    );
  }

  /// 记为「今天已读」：写 app_settings 的 [kSundayDialogShownDateKey]。
  /// 每次弹窗都覆盖写当天日期，库里只留最近一次，不会无限增长。
  Future<void> markShown() async {
    await Dao.instance.setSetting(
      kSundayDialogShownDateKey,
      sundayDialogDateStamp(_now()),
    );
  }
}
