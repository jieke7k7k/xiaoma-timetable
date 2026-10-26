import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/course_override.dart';
import '../models/menu_config.dart';
import '../models/note.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/widget_service.dart';
import '../ui/grid_metrics.dart';
import '../utils/week_calc.dart';

/// 当前激活学期
class CurrentSemesterNotifier extends AsyncNotifier<Semester> {
  @override
  Future<Semester> build() async {
    final s = await Dao.instance.getCurrentSemester();
    if (s == null) {
      throw StateError('未找到当前学期，请尝试重启应用');
    }
    return s;
  }

  Future<void> updateSemester(Semester updated) async {
    await Dao.instance.updateSemester(updated);
    state = AsyncData(updated);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 直接写入学期对象（不触发 AsyncLoading）。
  /// 供切换激活学期时使用：保证 value 全程非空，下游 Provider 无闪烁地重建。
  void setDirectly(Semester s) => state = AsyncData(s);
}

final currentSemesterProvider =
    AsyncNotifierProvider<CurrentSemesterNotifier, Semester>(
      CurrentSemesterNotifier.new,
    );

/// 数据变更后的统一联动（提醒重排 + 今日课程常驻通知 + 桌面小组件）。
///
/// 课程增删改、单次调课、切换学期、编辑当前学期都走这一份——三处散落各写一遍
/// 迟早会漏挂某一项。三个服务内部都已捕获异常，fire-and-forget 不阻塞 UI。
void _notifyDataChanged() {
  unawaited(NotificationService.instance.rescheduleAll());
  unawaited(OngoingNoticeService.instance.refresh());
  unawaited(WidgetService.instance.refreshWidgets());
}

/// 全部学期列表（学期管理页使用）
///
/// 切换激活学期的统一入口在 [SemestersNotifier.switchTo]：
/// 事务保证 isCurrent 唯一后，直接把新学期写入 currentSemesterProvider 的 state
/// （不走 AsyncLoading，避免周视图闪烁），下游 coursesProvider / todayWeekProvider
/// watch 到变化后自动重建，周视图、设置页无需手动刷新。
/// 后续通知提醒 / 桌面小组件 / 常驻通知栏的重排也应挂在这个入口（见 ARCHITECTURE.md）。
class SemestersNotifier extends AsyncNotifier<List<Semester>> {
  @override
  Future<List<Semester>> build() => Dao.instance.getAllSemesters();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// 新建学期（默认不激活，建好后由用户手动切换）
  Future<int> addSemester(Semester s) async {
    final id = await Dao.instance.insertSemester(s);
    await reload();
    return id;
  }

  /// 编辑学期（名称 / 开学日期 / 总周数）
  ///
  /// [updated] 由学期表单返回，编辑模式下带原 id 与 isCurrent，落库按 id 更新同一行。
  /// 被编辑的正是当前学期时，除了刷库与刷列表还要同步内存：
  /// `setDirectly`（免 AsyncLoading，与导入页改开学日期同一写法）让 todayWeekProvider /
  /// 周视图 / 提醒计划立刻按新的开学日期与总周数工作；随后走与其它数据变更完全
  /// 一致的联动（提醒重排 + 常驻通知 + 小部件）。
  /// 非当前学期只改库 + 刷列表——它的字段不参与任何当前数据的计算。
  Future<void> updateSemester(Semester updated) async {
    await Dao.instance.updateSemester(updated);
    final isCurrent = ref.read(currentSemesterProvider).value?.id == updated.id;
    if (isCurrent) {
      ref.read(currentSemesterProvider.notifier).setDirectly(updated);
    }
    await reload();
    if (!isCurrent) return;
    // 总周数被改小时，浏览周可能越界（PageView 页码越界会崩），先钳回来
    ref.read(displayWeekProvider.notifier).clampToTotalWeeks();
    _notifyDataChanged();
  }

  /// 切换激活学期：刷新下游所有 watch 当前学期的 Provider
  Future<void> switchTo(int semesterId) async {
    await Dao.instance.setCurrentSemester(semesterId);
    // 直接写入新 state 而非 reload()：保证 currentSemesterProvider.value 全程非空，
    // todayWeekProvider / coursesProvider watch 到变化后无闪烁地自动重建
    final target = await Dao.instance.getCurrentSemester();
    if (target != null) {
      ref.read(currentSemesterProvider.notifier).setDirectly(target);
      // 学期列表本身也要刷新 isCurrent 标记（state 此时必然有值，兜底走 reload）
      final list = state.value;
      if (list != null) {
        state = AsyncData([
          for (final s in list) s.copyWith(isCurrent: s.id == semesterId),
        ]);
      } else {
        await reload();
      }
    }
    // 浏览周重置为新学期的「本周」
    ref.read(displayWeekProvider.notifier).goToday();

    // 学期切换后重排提醒 / 刷新常驻通知 / 刷新小组件（与其它数据变更同一份口径）
    _notifyDataChanged();
  }

  /// 删除学期（级联删除课程与调课记录）。
  /// 当前激活学期不允许删除，由调用方（UI）先行拦截，这里再兜底校验。
  Future<void> deleteSemester(int id) async {
    final current = await Dao.instance.getCurrentSemester();
    if (current?.id == id) {
      throw Exception('不能删除当前正在使用的学期');
    }
    await Dao.instance.deleteSemester(id);
    await reload();
  }
}

final semestersProvider =
    AsyncNotifierProvider<SemestersNotifier, List<Semester>>(
      SemestersNotifier.new,
    );

/// 节次时间表
///
/// 2.0.0 复审 C3：作息时间直接决定桌面小部件每行开头的「上课时间」，所以
/// [updateSlot] / [addSection] / [removeLastSection] / [applyPresetBigSections]
/// 四个改动作息的方法末尾统一挂一次小部件刷新。放在 provider 层而不是每个页面
/// 各补一遍——改作息的入口有三个（作息设置页、导入校准、一键套用），漏一处就会
/// 出现「页面上是新时间、桌面还是旧时间」这类对不上的反馈。
class TimeSlotsNotifier extends AsyncNotifier<List<TimeSlot>> {
  @override
  Future<List<TimeSlot>> build() => Dao.instance.getTimeSlots();

  Future<void> updateSlot(TimeSlot slot) async {
    await Dao.instance.updateTimeSlot(slot);
    final list = state.value ?? [];
    // 已有节次替换、没有的新增（导入校准扩出的新节次靠这条进状态）
    state = AsyncData(
      [
        for (final s in list) s.section == slot.section ? slot : s,
        if (!list.any((s) => s.section == slot.section)) slot,
      ]..sort((a, b) => a.section.compareTo(b.section)),
    );
    // 小部件每行都要带上课/下课时间，作息一改就得重推（2.0.0 复审 C3）
    unawaited(WidgetService.instance.refreshWidgets());
  }

  /// 增加一节（末尾追加）：开始 = 上一节结束 + 10 分钟课间，时长沿用上一节；
  /// 一节都没有时从第 1 节 08:00-08:40 起步。总节数上限 20。
  Future<void> addSection() async {
    final list = <TimeSlot>[...(state.value ?? const <TimeSlot>[])]
      ..sort((a, b) => a.section.compareTo(b.section));
    if (list.length >= 20) return;
    final TimeSlot next;
    if (list.isEmpty) {
      next = const TimeSlot(section: 1, startTime: '08:00', endTime: '08:40');
    } else {
      final last = list.last;
      final lastStart = _slotMin(last.startTime) ?? 8 * 60;
      final lastEnd = _slotMin(last.endTime) ?? lastStart + 40;
      final duration = lastEnd - lastStart;
      final start = lastEnd + 10;
      next = TimeSlot(
        section: last.section + 1,
        startTime: _slotHm(start),
        endTime: _slotHm(start + (duration > 0 ? duration : 40)),
      );
    }
    await Dao.instance.updateTimeSlot(next);
    state = AsyncData([...list, next]);
    // 作息变了 → 小部件重推（见类注释）
    unawaited(WidgetService.instance.refreshWidgets());
  }

  /// 减少一节（删除最后一节），并把午休/晚餐分段点钳回新范围。总节数下限 4。
  Future<void> removeLastSection() async {
    final list = <TimeSlot>[...(state.value ?? const <TimeSlot>[])]
      ..sort((a, b) => a.section.compareTo(b.section));
    if (list.length <= 4) return;
    await Dao.instance.deleteTimeSlot(list.last.section);
    final rest = list.sublist(0, list.length - 1);
    state = AsyncData(rest);
    final seg = ref.read(segmentSettingsProvider).value;
    if (seg != null) {
      final n = rest.length;
      if (seg.lunchAfterSection > n - 2) {
        await ref
            .read(segmentSettingsProvider.notifier)
            .setLunchAfterSection(n - 2 < 1 ? 1 : n - 2);
      }
      if (seg.dinnerAfterSection > n) {
        await ref
            .read(segmentSettingsProvider.notifier)
            .setDinnerAfterSection(n);
      }
    }
    // 作息变了 → 小部件重推（见类注释）
    unawaited(WidgetService.instance.refreshWidgets());
  }

  /// 一键套用常用大节时间（1-2 节 09:40-12:00，3-4 节 14:00-16:20）
  Future<void> applyPresetBigSections() async {
    const preset = {
      1: ('09:40', '10:40'),
      2: ('10:40', '12:00'),
      3: ('14:00', '15:10'),
      4: ('15:10', '16:20'),
    };
    for (final entry in preset.entries) {
      await Dao.instance.updateTimeSlot(
        TimeSlot(
          section: entry.key,
          startTime: entry.value.$1,
          endTime: entry.value.$2,
        ),
      );
    }
    await reload();
    // 作息变了 → 小部件重推（见类注释）
    unawaited(WidgetService.instance.refreshWidgets());
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// "HH:mm" → 当天分钟数（非法返回 null），供节次增减推算时间用
int? _slotMin(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// 当天分钟数 → "HH:mm"
String _slotHm(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

final timeSlotsProvider =
    AsyncNotifierProvider<TimeSlotsNotifier, List<TimeSlot>>(
      TimeSlotsNotifier.new,
    );

/// 当前学期下的全部课程（含增删改）
class CoursesNotifier extends AsyncNotifier<List<Course>> {
  @override
  Future<List<Course>> build() async {
    final semester = await ref.watch(currentSemesterProvider.future);
    return Dao.instance.getCoursesBySemester(semester.id!);
  }

  Future<int> addCourse(Course course) async {
    final semester = await ref.read(currentSemesterProvider.future);
    final id = await Dao.instance.insertCourse(
      course.copyWith(semesterId: semester.id!),
    );
    await reload();
    // 新增课程后重排当天提醒（内部已捕获异常）
    unawaited(NotificationService.instance.rescheduleAll());
    // 新增课程后刷新今日课程常驻通知
    unawaited(OngoingNoticeService.instance.refresh());
    // 新增课程后刷新桌面小组件
    unawaited(WidgetService.instance.refreshWidgets());
    return id;
  }

  Future<void> updateCourse(Course course) async {
    await Dao.instance.updateCourse(course);
    await reload();
    unawaited(NotificationService.instance.rescheduleAll());
    // 改课时间/教室后刷新常驻通知
    unawaited(OngoingNoticeService.instance.refresh());
    // 改课后刷新桌面小组件
    unawaited(WidgetService.instance.refreshWidgets());
  }

  Future<void> deleteCourse(int id) async {
    await Dao.instance.deleteCourse(id);
    await reload();
    unawaited(NotificationService.instance.rescheduleAll());
    // 删课后刷新常驻通知
    unawaited(OngoingNoticeService.instance.refresh());
    // 删课后刷新桌面小组件
    unawaited(WidgetService.instance.refreshWidgets());
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final coursesProvider = AsyncNotifierProvider<CoursesNotifier, List<Course>>(
  CoursesNotifier.new,
);

/// 当前学期的全部单次调课记录（阶段五·节假日调课）
///
/// watch 当前学期，切学期自动联动。增删调课后除刷新本 provider 外，
/// 还要触发与课程增删改相同的三处联动（提醒重排 / 常驻通知 / 小组件），
/// 因为调课会改变未来 7 天的提醒计划与今日课程文案。
class CourseOverridesNotifier extends AsyncNotifier<List<CourseOverride>> {
  @override
  Future<List<CourseOverride>> build() async {
    final semester = await ref.watch(currentSemesterProvider.future);
    return Dao.instance.getOverridesBySemester(semester.id!);
  }

  /// 保存一条单次调课（同一课程同一周至多一条，重复保存等同覆盖）。
  /// [o.targetWeek]：正常调整传 originalWeek；停课传 CourseOverride.cancelFlag。
  Future<void> saveOverride(CourseOverride o) async {
    await Dao.instance.upsertOverride(o);
    await reload();
    _notifyServices();
  }

  /// 撤销一条单次调课，课程回到原规律
  Future<void> deleteOverride(int id) async {
    await Dao.instance.deleteOverride(id);
    await reload();
    _notifyServices();
  }

  /// 与 CoursesNotifier 增删改相同的联动：提醒重排 + 常驻通知 + 小组件。
  /// 三个服务内部均已捕获异常，fire-and-forget 不阻塞 UI。
  void _notifyServices() => _notifyDataChanged();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final courseOverridesProvider =
    AsyncNotifierProvider<CourseOverridesNotifier, List<CourseOverride>>(
      CourseOverridesNotifier.new,
    );

/// 全部备注（v3·AI 备注）：按日期升序，与学期无关。
///
/// 增删改后只联动「备注常驻通知 + 桌面小部件」两处——备注不参与上课提醒，
/// 不需要 rescheduleAll（那里面第一步就是 cancelAll，白清一遍滚动窗口）。
class NotesNotifier extends AsyncNotifier<List<Note>> {
  @override
  Future<List<Note>> build() => Dao.instance.getAllNotes();

  Future<int> addNote(Note note) async {
    final id = await Dao.instance.insertNote(note);
    await reload();
    _notifyServices();
    return id;
  }

  Future<void> updateNote(Note note) async {
    await Dao.instance.updateNote(note);
    await reload();
    _notifyServices();
  }

  Future<void> deleteNote(int id) async {
    await Dao.instance.deleteNote(id);
    await reload();
    _notifyServices();
  }

  /// 备注变化的联动：常驻通知重算（今天/明天没备注时会自己取消）+ 小部件重推。
  /// 两个服务内部均已捕获异常，fire-and-forget 不阻塞 UI。
  void _notifyServices() {
    unawaited(NotificationService.instance.refreshNoteNotice());
    unawaited(WidgetService.instance.refreshWidgets());
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final notesProvider = AsyncNotifierProvider<NotesNotifier, List<Note>>(
  NotesNotifier.new,
);

/// 今天是本学期第几周（依赖当前学期，设置页改开学日期后自动刷新）
final todayWeekProvider = Provider<int>((ref) {
  final semester = ref.watch(currentSemesterProvider).value;
  if (semester == null) return 0;
  return WeekCalc.currentWeek(semester.startDateParsed, DateTime.now());
});

/// 周视图当前正在浏览的周次（PageView 滑动切换，默认跳到本周）
///
/// 1.2.5 修复偶尔停在第一周：旧实现 build 时一次性 read 今天周次，启动
/// 瞬间学期还没加载完就读到兜底值、之后不再纠正。现改为：用户没手动
/// 切周前持续 watch 今天的周次（数据一到自动落到本周）；setWeek 定住
/// 后以用户操作为准；goToday 解除定住重新跟随。
///
/// 1.3.1 越界钳制：[WeekCalc.currentWeek] 允许返回超过学期总周数的实际
/// 周数（学期已结束仍继续计数），但本值直接用作 PageView 的页码，
/// 超出 totalWeeks 会越界崩溃，故一律钳到 [1, totalWeeks]；
/// 学期未加载（totalWeeks = 0）时保持原行为——只保下限 1。
class DisplayWeekNotifier extends Notifier<int> {
  /// 用户手动定住的周次；null 表示跟随「今天是第几周」
  int? _pinned;

  @override
  int build() {
    final today = ref.watch(todayWeekProvider);
    final totalWeeks = _totalWeeks();
    return WeekCalc.clampForPage(_pinned ?? today, totalWeeks);
  }

  void setWeek(int week) {
    _pinned = WeekCalc.clampForPage(week, _totalWeeks());
    state = _pinned!;
  }

  /// 回到「本周」：解除定住，重新跟随今天
  void goToday() {
    _pinned = null;
    state = WeekCalc.clampForPage(ref.read(todayWeekProvider), _totalWeeks());
  }

  /// 学期总周数变化后重新钳制浏览周（编辑当前学期时用）。
  ///
  /// 总周数被改小时，原浏览周可能超出范围，而它直接用作 PageView 的页码，
  /// 越界会崩。没越界时保持用户当前浏览的周不动（不做「回到本周」的跳页）。
  void clampToTotalWeeks() {
    final clamped = WeekCalc.clampForPage(state, _totalWeeks());
    if (_pinned != null) _pinned = clamped;
    state = clamped;
  }

  /// 当前学期总周数；学期未加载（value 为 null）返回 0，表示「不限制上限」
  int _totalWeeks() => ref.read(currentSemesterProvider).value?.totalWeeks ?? 0;
}

final displayWeekProvider = NotifierProvider<DisplayWeekNotifier, int>(
  DisplayWeekNotifier.new,
);

/// 设置开关：是否显示非本周课程（置灰），默认隐藏
class ShowOtherWeeksNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle(bool value) => state = value;
}

final showOtherWeeksProvider = NotifierProvider<ShowOtherWeeksNotifier, bool>(
  ShowOtherWeeksNotifier.new,
);

/// 设置开关：周末无课时自动收起周六日（5 列宽屏显示），默认开启
class AutoCollapseWeekendNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle(bool value) => state = value;
}

final autoCollapseWeekendProvider =
    NotifierProvider<AutoCollapseWeekendNotifier, bool>(
      AutoCollapseWeekendNotifier.new,
    );

/// 上课提醒设置（阶段四）：开关 + 提前分钟，持久化到 app_settings 表
class ReminderSettings {
  final bool enabled;
  final int advanceMinutes; // 可选 5/10/15/30，默认 15

  const ReminderSettings({required this.enabled, required this.advanceMinutes});

  ReminderSettings copyWith({bool? enabled, int? advanceMinutes}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        advanceMinutes: advanceMinutes ?? this.advanceMinutes,
      );
}

/// 上课提醒设置状态：读自 app_settings 表；改动即持久化并触发重排
class ReminderSettingsNotifier extends AsyncNotifier<ReminderSettings> {
  @override
  Future<ReminderSettings> build() async {
    final enabled = await Dao.instance.getSettingBool(
      'reminder_enabled',
      false,
    );
    final advance = await Dao.instance.getSettingInt(
      'reminder_advance_minutes',
      15,
    );
    return ReminderSettings(enabled: enabled, advanceMinutes: advance);
  }

  /// 开启/关闭提醒。开启时由 UI 先申请权限再调用；此处只负责持久化 + 重排
  Future<void> setEnabled(bool value) async {
    await Dao.instance.setSetting('reminder_enabled', value ? '1' : '0');
    state = AsyncData(
      ReminderSettings(
        enabled: value,
        advanceMinutes: state.value?.advanceMinutes ?? 15,
      ),
    );
    // 开启则排期，关闭则清空（rescheduleAll 内部处理）
    unawaited(NotificationService.instance.rescheduleAll());
  }

  /// 修改提前分钟（5/10/15/30）
  Future<void> setAdvanceMinutes(int minutes) async {
    await Dao.instance.setSetting('reminder_advance_minutes', '$minutes');
    state = AsyncData(
      ReminderSettings(
        enabled: state.value?.enabled ?? false,
        advanceMinutes: minutes,
      ),
    );
    unawaited(NotificationService.instance.rescheduleAll());
  }
}

final reminderSettingsProvider =
    AsyncNotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
      ReminderSettingsNotifier.new,
    );

/// 今日课程常驻通知栏开关（阶段四·第 3 项）：读自 app_settings 表，默认开启
class OngoingNoticeSettingsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return Dao.instance.getSettingBool('ongoing_enabled', true);
  }

  /// 开/关常驻通知。开启时立即重算下发；关闭时清通知停服务。
  Future<void> setEnabled(bool value) async {
    await Dao.instance.setSetting('ongoing_enabled', value ? '1' : '0');
    state = AsyncData(value);
    if (value) {
      unawaited(OngoingNoticeService.instance.refresh());
    } else {
      unawaited(OngoingNoticeService.instance.stop());
    }
  }
}

final ongoingNoticeSettingsProvider =
    AsyncNotifierProvider<OngoingNoticeSettingsNotifier, bool>(
      OngoingNoticeSettingsNotifier.new,
    );

/// 主题模式设置（阶段五·深色适配）：跟随系统 / 浅色 / 深色三档，
/// 持久化到 app_settings 表（键 theme_mode，值 "system"/"light"/"dark"，默认 system）。
/// main.dart 的 MaterialApp.themeMode watch 本 provider，切换即时生效且重启后保持。
class ThemeSettingsNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    // 数据库读取异常（如表损坏）时兜底回跟随系统，不能让主题设置拖垮启动
    try {
      return _fromString(await Dao.instance.getSetting('theme_mode'));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// app_settings 存的字符串 → ThemeMode；非法值/空值一律回跟随系统
  static ThemeMode _fromString(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// 切换主题模式：先持久化再更新内存 state，MaterialApp watch 后即时重建
  Future<void> setMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    try {
      await Dao.instance.setSetting('theme_mode', value);
    } catch (e) {
      // 持久化失败不阻断切换（本次会话内仍生效），只打日志
      debugPrint('主题模式持久化失败：$e');
    }
    state = AsyncData(mode);
  }
}

final themeSettingsProvider =
    AsyncNotifierProvider<ThemeSettingsNotifier, ThemeMode>(
      ThemeSettingsNotifier.new,
    );

/// 作息分段设置（阶段六·作息三段化）：午休/晚餐分段点，持久化到 app_settings 表。
/// 键名 lunch_after_section（默认 5）、dinner_after_section（默认 9）。
/// 分段规则：节次 ≤ 午休分段点为上午，≤ 晚餐分段点为下午，其余为晚上。
class SegmentSettings {
  final int lunchAfterSection; // 午休在第几节课之后
  final int dinnerAfterSection; // 晚餐在第几节课之后

  const SegmentSettings({
    required this.lunchAfterSection,
    required this.dinnerAfterSection,
  });

  SegmentSettings copyWith({int? lunchAfterSection, int? dinnerAfterSection}) =>
      SegmentSettings(
        lunchAfterSection: lunchAfterSection ?? this.lunchAfterSection,
        dinnerAfterSection: dinnerAfterSection ?? this.dinnerAfterSection,
      );
}

/// 作息分段设置状态：读自 app_settings 表；改动即持久化并触发下游刷新分组/分隔带。
class SegmentSettingsNotifier extends AsyncNotifier<SegmentSettings> {
  @override
  Future<SegmentSettings> build() async {
    final lunch = await Dao.instance.getSettingInt('lunch_after_section', 5);
    final dinner = await Dao.instance.getSettingInt('dinner_after_section', 9);
    return SegmentSettings(
      lunchAfterSection: lunch,
      dinnerAfterSection: dinner,
    );
  }

  /// 修改午休分段点。钳制到 [1, 晚餐分段点-1]，保证午休点 < 晚餐点且上午段至少 1 节。
  Future<void> setLunchAfterSection(int value) async {
    final dinner = state.value?.dinnerAfterSection ?? 9;
    final max = dinner - 1;
    final v = value < 1 ? 1 : (value > max ? max : value);
    await Dao.instance.setSetting('lunch_after_section', '$v');
    state = AsyncData(
      SegmentSettings(lunchAfterSection: v, dinnerAfterSection: dinner),
    );
  }

  /// 修改晚餐分段点。钳制到 [午休分段点+1, +∞)，保证午休点 < 晚餐点；
  /// 上限由作息设置页按当前最大节次进一步钳制。
  Future<void> setDinnerAfterSection(int value) async {
    final lunch = state.value?.lunchAfterSection ?? 5;
    final min = lunch + 1;
    final v = value < min ? min : value;
    await Dao.instance.setSetting('dinner_after_section', '$v');
    state = AsyncData(
      SegmentSettings(lunchAfterSection: lunch, dinnerAfterSection: v),
    );
  }
}

final segmentSettingsProvider =
    AsyncNotifierProvider<SegmentSettingsNotifier, SegmentSettings>(
      SegmentSettingsNotifier.new,
    );

/// 休息时段设置状态（WB_SPEC_209 第 6 节）：午休/晚间各自显隐 + 自定义起止时间，
/// 持久化到 app_settings 表。键名 band_lunch_visible / band_dinner_visible /
/// band_lunch_start / band_lunch_end / band_dinner_start / band_dinner_end。
/// 起止时间必须是合法 "HH:mm" 且开始早于结束，否则不保存（返回 false）。
class BandSettingsNotifier extends AsyncNotifier<BandSettings> {
  @override
  Future<BandSettings> build() async {
    return BandSettings(
      lunchVisible:
          await Dao.instance.getSettingBool('band_lunch_visible', true),
      dinnerVisible:
          await Dao.instance.getSettingBool('band_dinner_visible', true),
      lunchStart: await Dao.instance.getSetting('band_lunch_start') ?? '12:00',
      lunchEnd: await Dao.instance.getSetting('band_lunch_end') ?? '14:00',
      dinnerStart:
          await Dao.instance.getSetting('band_dinner_start') ?? '17:10',
      dinnerEnd: await Dao.instance.getSetting('band_dinner_end') ?? '18:00',
    );
  }

  BandSettings get _cur => state.value ?? const BandSettings();

  Future<void> setLunchVisible(bool value) async {
    await Dao.instance.setSetting('band_lunch_visible', value ? '1' : '0');
    state = AsyncData(_cur.copyWith(lunchVisible: value));
  }

  Future<void> setDinnerVisible(bool value) async {
    await Dao.instance.setSetting('band_dinner_visible', value ? '1' : '0');
    state = AsyncData(_cur.copyWith(dinnerVisible: value));
  }

  /// 设置午休起止时间；开始早于结束才保存，返回是否保存成功。
  Future<bool> setLunchTime(String start, String end) async {
    if (!bandRangeValid(start, end)) return false;
    await Dao.instance.setSetting('band_lunch_start', start);
    await Dao.instance.setSetting('band_lunch_end', end);
    state = AsyncData(_cur.copyWith(lunchStart: start, lunchEnd: end));
    return true;
  }

  /// 设置晚间起止时间；开始早于结束才保存，返回是否保存成功。
  Future<bool> setDinnerTime(String start, String end) async {
    if (!bandRangeValid(start, end)) return false;
    await Dao.instance.setSetting('band_dinner_start', start);
    await Dao.instance.setSetting('band_dinner_end', end);
    state = AsyncData(_cur.copyWith(dinnerStart: start, dinnerEnd: end));
    return true;
  }
}

final bandSettingsProvider =
    AsyncNotifierProvider<BandSettingsNotifier, BandSettings>(
      BandSettingsNotifier.new,
    );

/// 界面设置状态（1.1.1）：整体 JSON 持久化到 app_settings 的 ui_settings 键。
/// 改动即落库并通知全 App（主题色/字体在 MaterialApp 层监听，格子外观在周视图监听）。
class UiSettingsNotifier extends AsyncNotifier<UiSettings> {
  @override
  Future<UiSettings> build() async {
    return UiSettings.fromEncoded(await Dao.instance.getSetting('ui_settings'));
  }

  /// 整体替换（设置页每次调节都走这里）：先落库再发状态，保证重启后一致
  Future<void> apply(UiSettings next) async {
    await Dao.instance.setSetting('ui_settings', next.encode());
    state = AsyncData(next);
  }

  /// 便捷更新：基于当前值 copyWith 后整体替换
  Future<void> updateWith(UiSettings Function(UiSettings) fn) async {
    final cur = state.value ?? const UiSettings();
    await apply(fn(cur));
  }
}

final uiSettingsProvider =
    AsyncNotifierProvider<UiSettingsNotifier, UiSettings>(
      UiSettingsNotifier.new,
    );

/// 首次启动引导是否已看完（1.2.4）：app_settings 的 onboarding_done 键。
/// 恢复出厂会清掉这个键，引导会重新出现（符合出厂语义）。
final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  return await Dao.instance.getSetting('onboarding_done') == '1';
});

/// 开发者选项解锁状态（WB_SPEC_212 第 3 节）：关于页版本行连点 5 次解锁，
/// 持久化到 app_settings 的 `developer_options_unlocked` 键（"1"/"0"，默认关）。
///
/// 重装 / 清数据后键随之消失，自动回到未解锁——符合预期，不做云端同步。
class DeveloperOptionsNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // 读库异常（如表损坏）兜底未解锁，不让它拖垮设置页
    try {
      return await Dao.instance.getSettingBool('developer_options_unlocked', false);
    } catch (_) {
      return false;
    }
  }

  /// 解锁开发者选项（关于页连点 5 次后调用）：先落库再更新内存 state。
  ///
  /// 返回写库是否成功：失败时不更新状态、不谎报成功，调用方据此决定提示
  /// （2.1.0 返修：此前返回 void，调用方未 await 就弹成功，写库失败也报成功）。
  Future<bool> unlock() async {
    try {
      await Dao.instance.setSetting('developer_options_unlocked', '1');
    } catch (_) {
      return false;
    }
    state = const AsyncData(true);
    return true;
  }
}

final developerOptionsProvider =
    AsyncNotifierProvider<DeveloperOptionsNotifier, bool>(
      DeveloperOptionsNotifier.new,
    );

/// 主页「更多」菜单配置（WB_SPEC_212 第 4 节）：六个功能项的显隐 + 顺序，
/// 持久化到 app_settings 的 `home_menu_config` 键（JSON 数组，见 MenuConfig）。
///
/// 「设置」不在配置里：固定显示、不可关闭、不可排序移出（兜底入口）。
class MenuConfigNotifier extends AsyncNotifier<MenuConfig> {
  @override
  Future<MenuConfig> build() async {
    try {
      return MenuConfig.fromEncoded(
        await Dao.instance.getSetting('home_menu_config'),
      );
    } catch (_) {
      return MenuConfig.defaults();
    }
  }

  /// 写操作串行队列（2.1.0 返修）：快速连续开关/拖拽/恢复默认时，
  /// 后一次写必须读到前一次写完的状态，否则后写会覆盖先写导致配置丢失。
  ///
  /// 队列实现刻意让空闲时的第一次写立即启动（与改动前的时序一致，
  /// 不多一个 microtask  hop，避免 UI 回调 fire-and-forget 后单次 pump
  /// 看不到更新）；忙碌时后来者排队，绝不并发写。
  final List<Future<void> Function()> _pendingWrites = [];
  bool _writing = false;

  Future<void> _pumpWrites() {
    if (_writing || _pendingWrites.isEmpty) return Future.value();
    _writing = true;
    final job = _pendingWrites.removeAt(0);
    return job().whenComplete(() {
      _writing = false;
      _pumpWrites();
    });
  }

  /// 在队列里跑一次「读当前配置 → 算出下一配置 → 落库 → 更新 state」。
  ///
  /// 当前配置优先取已加载的 state；加载未完成时先等 build 的 Future
  /// 读出已存配置，绝不拿默认值覆盖已存配置（2.1.0 返修 P1）。
  Future<void> _runLocked(
    MenuConfig Function(MenuConfig current) compute,
  ) {
    final completer = Completer<void>();
    _pendingWrites.add(() async {
      try {
        MenuConfig current;
        if (state is AsyncData<MenuConfig>) {
          current = state.value!;
        } else {
          try {
            current = await future;
          } catch (_) {
            current = MenuConfig.defaults();
          }
        }
        final next = compute(current);
        await Dao.instance.setSetting('home_menu_config', next.encode());
        state = AsyncData(next);
        completer.complete();
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    unawaited(_pumpWrites());
    return completer.future;
  }

  /// 切换某项显隐（只改这一项，不影响其余项的顺序/显隐）。
  Future<void> setVisible(String id, bool visible) =>
      _runLocked((cur) => cur.copyWithVisible(id, visible));

  /// 按 ReorderableListView 的 (oldIndex, newIndex) 语义重排并持久化。
  Future<void> reorder(int oldIndex, int newIndex) =>
      _runLocked((cur) => cur.reorder(oldIndex, newIndex));

  /// 恢复默认：六项全显示、顺序回到第 4 节定版顺序。
  Future<void> reset() => _runLocked((_) => MenuConfig.defaults());
}

final menuConfigProvider = AsyncNotifierProvider<MenuConfigNotifier, MenuConfig>(
  MenuConfigNotifier.new,
);
