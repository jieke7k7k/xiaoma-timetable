import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/course_override.dart';
import '../models/note.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../utils/widget_data.dart';

/// 桌面小部件服务（Android only）
///
/// 数据经 [HomeWidget.saveWidgetData] 写入 home_widget 专用 SharedPreferences，
/// 原生 CourseWidgetProvider 读取后渲染。
///
/// 1.2.2 改版：下发整包 JSON（键 widget_payload），结构见 utils/widget_data.dart
/// （顶栏学期名 + 日期周次、课程列表行：色条/课名/教室教师/起止时间）。
/// 此前（≤1.2.1）的 widget_title / widget_lines 两键不再写入，原生侧已同步。
///
/// 1.3.4 跨天自动切换：额外写 widget_payload_days（键 yyyy-MM-dd → 该日 payload
/// JSON，共 7 天）。原生 Provider 每次重绘先按本地今天日期取这份，取不到才回退
/// widget_payload——解决「长假不开 App，小部件停在旧日期」的已知限制。
///
/// 1.2.1 教训：链路代码全对时小部件仍可能永不刷新——投递层不可靠
/// （厂商省电吞广播、周期为 0 无系统重绘）。对策：updatePeriodMillis=30 分钟
/// 兜底重绘（原生元数据）、本类保存后回读校验、设置页手动刷新入口。
///
/// 小部件是否显示由用户在桌面手动添加决定，App 侧不做开关，只在数据变化时推送。
/// 全部异常 try/catch 打中文日志，绝不闪退。
class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  /// Android 小部件 Provider 的简单类名（不带包名），home_widget 用它定位组件
  static const String _androidWidgetName = 'CourseWidgetProvider';

  /// 部件自检状态（1.2.7）：原生 Provider 每次 onUpdate 回写的记录，
  /// 设置页展示——上次更新时间、实例数、首个异常（无异常时 error 为 null）
  Future<({int ts, int ids, String? error})> debugStatus() async {
    final ts = await HomeWidget.getWidgetData<int>('dbg_widget_ts');
    final ids = await HomeWidget.getWidgetData<int>('dbg_widget_ids');
    final error = await HomeWidget.getWidgetData<String>('dbg_widget_error');
    return (ts: ts ?? 0, ids: ids ?? 0, error: error);
  }

  /// 全限定类名（含包名），home_widget 0.10.x 用它 Class.forName 定位 Provider
  static const String _qualifiedAndroidName =
      'com.jieke.xiaomakebiao.CourseWidgetProvider';

  /// 重新计算并推送小部件数据。
  ///
  /// 挂点：课程/学期数据变更钩子（providers）末尾 + HomeShell.initState（App 启动）
  /// + 设置页手动刷新入口。若用户尚未在桌面添加小部件，updateWidget 是空操作。
  Future<void> refreshWidgets() async {
    try {
      final semester = await Dao.instance.getCurrentSemester();
      final uiRaw = await Dao.instance.getSetting('ui_settings');
      final ui = uiRaw == null
          ? const UiSettings()
          : UiSettings.fromEncoded(uiRaw);
      final List<Course> courses = semester == null
          ? const <Course>[]
          : await Dao.instance.getCoursesBySemester(semester.id!);
      final List<TimeSlot> timeSlots = semester == null
          ? const <TimeSlot>[]
          : await Dao.instance.getTimeSlots();
      final List<CourseOverride> overrides = semester == null
          ? const <CourseOverride>[]
          : await Dao.instance.getOverridesBySemester(semester.id!);

      final now = DateTime.now();
      // 备注按日分组（今天 + 未来 6 天，与逐日 payload 同一窗口）。
      // 一次批量查出来再按日期键分桶，避免逐日重复查库。
      final Map<String, List<Note>> notesByDate =
          await _notesByDateFrom(now, days: 7);
      final payload = buildWidgetPayload(
        now: now,
        semester: semester,
        courses: courses,
        timeSlots: timeSlots,
        overrides: overrides,
        ui: ui,
        notesByDate: notesByDate,
      );
      final json = jsonEncode(payload.toJson());
      await HomeWidget.saveWidgetData<String>('widget_payload', json);
      // 回读校验（1.2.1）：个别设备上通道写入可能静默失败，读回不一致就重写一次
      final back = await HomeWidget.getWidgetData<String>('widget_payload');
      if (back != json) {
        debugPrint('小部件数据回读不一致，重写一次');
        await HomeWidget.saveWidgetData<String>('widget_payload', json);
      }
      // 逐日 payload（1.3.4）：今天 + 未来 6 天，键是 yyyy-MM-dd。
      // 原生 Provider 每次重绘按设备本地日期取对应那份，长假不开 App 也能跨天切换。
      final daysJson = jsonEncode(
        buildWidgetPayloadDays(
          now: now,
          semester: semester,
          courses: courses,
          timeSlots: timeSlots,
          overrides: overrides,
          ui: ui,
          notesByDate: notesByDate,
        ),
      );
      await HomeWidget.saveWidgetData<String>('widget_payload_days', daysJson);
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        qualifiedAndroidName: _qualifiedAndroidName,
      );
    } catch (e) {
      debugPrint('刷新桌面小部件失败：$e');
    }
  }

  /// 取 [now] 起 [days] 天的备注，按 yyyy-MM-dd 分桶。
  /// 读库失败（表不存在等）吞掉返回空表——小部件没有备注也要能照常显示课程，
  /// 绝不让「备注读不到」把整份 payload 拖垮成黑框。
  Future<Map<String, List<Note>>> _notesByDateFrom(
    DateTime now, {
    int days = 7,
  }) async {
    try {
      final today = DateTime(now.year, now.month, now.day);
      final keys = [
        for (var i = 0; i < days; i++) widgetDayKey(today.add(Duration(days: i))),
      ];
      final notes = await Dao.instance.getNotesByDates(keys);
      final out = <String, List<Note>>{};
      for (final n in notes) {
        out.putIfAbsent(n.date, () => <Note>[]).add(n);
      }
      return out;
    } catch (e) {
      debugPrint('读取备注失败（小部件按无备注继续）：$e');
      return const {};
    }
  }
}
