import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../database/dao.dart';
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
      final payload = semester == null
          ? buildWidgetPayload(
              now: DateTime.now(),
              semester: null,
              courses: const [],
              timeSlots: const [],
            )
          : buildWidgetPayload(
              now: DateTime.now(),
              semester: semester,
              courses: await Dao.instance.getCoursesBySemester(semester.id!),
              timeSlots: await Dao.instance.getTimeSlots(),
              overrides: await Dao.instance.getOverridesBySemester(
                semester.id!,
              ),
              ui: uiRaw == null
                  ? const UiSettings()
                  : UiSettings.fromEncoded(uiRaw),
            );
      final json = jsonEncode(payload.toJson());
      await HomeWidget.saveWidgetData<String>('widget_payload', json);
      // 回读校验（1.2.1）：个别设备上通道写入可能静默失败，读回不一致就重写一次
      final back = await HomeWidget.getWidgetData<String>('widget_payload');
      if (back != json) {
        debugPrint('小部件数据回读不一致，重写一次');
        await HomeWidget.saveWidgetData<String>('widget_payload', json);
      }
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        qualifiedAndroidName: _qualifiedAndroidName,
      );
    } catch (e) {
      debugPrint('刷新桌面小部件失败：$e');
    }
  }
}
