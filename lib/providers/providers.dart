import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/course_override.dart';
import '../models/semester.dart';
import '../models/time_slot.dart';
import '../services/notification_service.dart';
import '../services/ongoing_notice_service.dart';
import '../services/widget_service.dart';
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
        CurrentSemesterNotifier.new);

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

    // 学期切换后重排提醒（滚动窗口换成新学期课程；内部已捕获异常，不阻塞 UI）
    unawaited(NotificationService.instance.rescheduleAll());
    // 学期切换后刷新今日课程常驻通知
    unawaited(OngoingNoticeService.instance.refresh());
    // 学期切换后刷新桌面小组件（内部已捕获异常）
    unawaited(WidgetService.instance.refreshWidgets());
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
        SemestersNotifier.new);

/// 节次时间表
class TimeSlotsNotifier extends AsyncNotifier<List<TimeSlot>> {
  @override
  Future<List<TimeSlot>> build() => Dao.instance.getTimeSlots();

  Future<void> updateSlot(TimeSlot slot) async {
    await Dao.instance.updateTimeSlot(slot);
    final list = state.value ?? [];
    state = AsyncData([
      for (final s in list) s.section == slot.section ? slot : s,
    ]);
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
      await Dao.instance.updateTimeSlot(TimeSlot(
        section: entry.key,
        startTime: entry.value.$1,
        endTime: entry.value.$2,
      ));
    }
    await reload();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final timeSlotsProvider =
    AsyncNotifierProvider<TimeSlotsNotifier, List<TimeSlot>>(
        TimeSlotsNotifier.new);

/// 当前学期下的全部课程（含增删改）
class CoursesNotifier extends AsyncNotifier<List<Course>> {
  @override
  Future<List<Course>> build() async {
    final semester = await ref.watch(currentSemesterProvider.future);
    return Dao.instance.getCoursesBySemester(semester.id!);
  }

  Future<int> addCourse(Course course) async {
    final semester = await ref.read(currentSemesterProvider.future);
    final id = await Dao.instance
        .insertCourse(course.copyWith(semesterId: semester.id!));
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

final coursesProvider =
    AsyncNotifierProvider<CoursesNotifier, List<Course>>(CoursesNotifier.new);

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
  void _notifyServices() {
    unawaited(NotificationService.instance.rescheduleAll());
    unawaited(OngoingNoticeService.instance.refresh());
    unawaited(WidgetService.instance.refreshWidgets());
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final courseOverridesProvider =
    AsyncNotifierProvider<CourseOverridesNotifier, List<CourseOverride>>(
        CourseOverridesNotifier.new);

/// 今天是本学期第几周（依赖当前学期，设置页改开学日期后自动刷新）
final todayWeekProvider = Provider<int>((ref) {
  final semester = ref.watch(currentSemesterProvider).value;
  if (semester == null) return 0;
  return WeekCalc.currentWeek(
      DateTime.parse(semester.startDate), DateTime.now());
});

/// 周视图当前正在浏览的周次（PageView 滑动切换，默认跳到本周）
class DisplayWeekNotifier extends Notifier<int> {
  @override
  int build() => ref.read(todayWeekProvider);

  void setWeek(int week) => state = week < 1 ? 1 : week;

  /// 回到「本周」；未开学（todayWeek=0，如刚切到下学期）时至少停在第 1 周
  void goToday() {
    final w = ref.read(todayWeekProvider);
    state = w < 1 ? 1 : w;
  }
}

final displayWeekProvider = NotifierProvider<DisplayWeekNotifier, int>(
    DisplayWeekNotifier.new);

/// 设置开关：是否显示非本周课程（置灰），默认隐藏
class ShowOtherWeeksNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle(bool value) => state = value;
}

final showOtherWeeksProvider =
    NotifierProvider<ShowOtherWeeksNotifier, bool>(ShowOtherWeeksNotifier.new);

/// 设置开关：周末无课时自动收起周六日（5 列宽屏显示），默认开启
class AutoCollapseWeekendNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void toggle(bool value) => state = value;
}

final autoCollapseWeekendProvider =
    NotifierProvider<AutoCollapseWeekendNotifier, bool>(
        AutoCollapseWeekendNotifier.new);

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
    final enabled =
        await Dao.instance.getSettingBool('reminder_enabled', false);
    final advance =
        await Dao.instance.getSettingInt('reminder_advance_minutes', 15);
    return ReminderSettings(enabled: enabled, advanceMinutes: advance);
  }

  /// 开启/关闭提醒。开启时由 UI 先申请权限再调用；此处只负责持久化 + 重排
  Future<void> setEnabled(bool value) async {
    await Dao.instance.setSetting('reminder_enabled', value ? '1' : '0');
    state = AsyncData(ReminderSettings(
      enabled: value,
      advanceMinutes: state.value?.advanceMinutes ?? 15,
    ));
    // 开启则排期，关闭则清空（rescheduleAll 内部处理）
    unawaited(NotificationService.instance.rescheduleAll());
  }

  /// 修改提前分钟（5/10/15/30）
  Future<void> setAdvanceMinutes(int minutes) async {
    await Dao.instance.setSetting('reminder_advance_minutes', '$minutes');
    state = AsyncData(ReminderSettings(
      enabled: state.value?.enabled ?? false,
      advanceMinutes: minutes,
    ));
    unawaited(NotificationService.instance.rescheduleAll());
  }
}

final reminderSettingsProvider =
    AsyncNotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);

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
        OngoingNoticeSettingsNotifier.new);

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
        ThemeSettingsNotifier.new);

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
        lunchAfterSection: lunch, dinnerAfterSection: dinner);
  }

  /// 修改午休分段点。钳制到 [1, 晚餐分段点-1]，保证午休点 < 晚餐点且上午段至少 1 节。
  Future<void> setLunchAfterSection(int value) async {
    final dinner = state.value?.dinnerAfterSection ?? 9;
    final max = dinner - 1;
    final v = value < 1 ? 1 : (value > max ? max : value);
    await Dao.instance.setSetting('lunch_after_section', '$v');
    state = AsyncData(SegmentSettings(
      lunchAfterSection: v,
      dinnerAfterSection: dinner,
    ));
  }

  /// 修改晚餐分段点。钳制到 [午休分段点+1, +∞)，保证午休点 < 晚餐点；
  /// 上限由作息设置页按当前最大节次进一步钳制。
  Future<void> setDinnerAfterSection(int value) async {
    final lunch = state.value?.lunchAfterSection ?? 5;
    final min = lunch + 1;
    final v = value < min ? min : value;
    await Dao.instance.setSetting('dinner_after_section', '$v');
    state = AsyncData(SegmentSettings(
      lunchAfterSection: lunch,
      dinnerAfterSection: v,
    ));
  }
}

final segmentSettingsProvider =
    AsyncNotifierProvider<SegmentSettingsNotifier, SegmentSettings>(
        SegmentSettingsNotifier.new);
