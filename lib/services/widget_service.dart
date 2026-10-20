import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../database/dao.dart';
import '../utils/ongoing_notice.dart';

/// 桌面小组件服务（阶段四·第 2 项，Android only）
///
/// 把「今日剩余 / 明日课程预告」的标题 + 行文案通过 home_widget 下发给原生小组件。
/// 复用 [buildOngoingNotice] 纯函数（与常驻通知栏同一套 B 决策），不另写判断逻辑。
///
/// 数据通过 [HomeWidget.saveWidgetData] 写入 home_widget 专用的 SharedPreferences，
/// 原生 CourseWidgetProvider 读取后渲染。下发的两个键：
/// - widget_title：标题，如「今日剩余课程（共 3 节）」
/// - widget_lines：行文案 JSON 数组，如 ["08:00-08:45 高等数学 A101", ...]
///
/// 小组件是否显示由用户在桌面手动添加决定，App 侧不做开关，只在数据变化时推送更新。
/// 全部异常 try/catch 打中文日志，绝不闪退。
class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  /// Android 小组件 Provider 的简单类名（不带包名），home_widget 用它定位组件
  static const String _androidWidgetName = 'CourseWidgetProvider';

  /// 全限定类名（含包名），home_widget 0.10.x 用它 Class.forName 定位 Provider
  static const String _qualifiedAndroidName =
      'com.jieke.xiaomakebiao.CourseWidgetProvider';

  /// 重新计算并推送小组件数据。
  ///
  /// 挂点：SemestersNotifier.switchTo、CoursesNotifier.addCourse/updateCourse/deleteCourse
  /// 末尾 + HomeShell.initState（App 启动）。若用户尚未在桌面添加小组件，updateWidget
  /// 是空操作，不会报错。
  Future<void> refreshWidgets() async {
    try {
      final semester = await Dao.instance.getCurrentSemester();
      String title;
      List<String> lines;
      if (semester == null) {
        // 无当前学期（理论上不会发生）：给兜底文案，避免小组件空白
        title = '小马课表';
        lines = const ['暂无课程'];
      } else {
        final courses = await Dao.instance.getCoursesBySemester(semester.id!);
        final slots = await Dao.instance.getTimeSlots();
        // 单次调课（阶段五）：停课的本次不展示，调课的按新时间/教室展示
        final overrides =
            await Dao.instance.getOverridesBySemester(semester.id!);
        final notice = buildOngoingNotice(
          now: DateTime.now(),
          semester: semester,
          courses: courses,
          timeSlots: slots,
          overrides: overrides,
        );
        title = notice.title;
        // buildOngoingNotice 已保证 lines 非空（明日无课兜底「明天暂无课程」），
        // 这里再兜底一次，防止未来改动导致空列表
        lines = notice.lines.isEmpty ? const ['暂无课程'] : notice.lines;
      }

      await HomeWidget.saveWidgetData<String>('widget_title', title);
      await HomeWidget.saveWidgetData<String>('widget_lines', jsonEncode(lines));
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        qualifiedAndroidName: _qualifiedAndroidName,
      );
    } catch (e) {
      debugPrint('刷新桌面小组件失败：$e');
    }
  }
}
