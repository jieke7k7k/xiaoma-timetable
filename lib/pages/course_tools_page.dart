import 'package:flutter/material.dart';

/// 课表工具（设置 → 课表工具）：功能类入口的二级页
///
/// 2.0.2（WB-202 第 2 项·A 方案）：课程搜索 / 空闲时段 / 考试倒计时 /
/// 导出课表图片 / 日期备注这五样从设置页一级页面收进这里，一级页只留
/// 一行入口。路由全部复用原有页面（一个都没丢），本页只做归拢。
/// 2.1.7（WB_SPEC_218 第 ④ 节）：菜单管理从设置首页移入本页底部（路由不变）。
class CourseToolsPage extends StatelessWidget {
  const CourseToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('课表工具'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.search_outlined),
            title: const Text('课程搜索'),
            subtitle: const Text('按课名 / 老师 / 教室搜当前学期的课，点结果跳到那一周'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/course-search'),
          ),
          ListTile(
            leading: const Icon(Icons.free_breakfast_outlined),
            title: const Text('空闲时段'),
            subtitle: const Text('按周列出每天没课的时段，找空档排事情'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/free-time'),
          ),
          ListTile(
            leading: const Icon(Icons.event_note_outlined),
            title: const Text('考试倒计时'),
            subtitle: const Text('设置了考试日期的课程按日期升序排列'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/exam-countdown'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('导出课表图片'),
            subtitle: const Text('把当前浏览的那一周渲染成图片，走系统分享'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/share-image'),
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('日期备注'),
            subtitle: const Text('按日期记录待办备忘，可在通知栏与桌面小部件显示'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/notes'),
          ),
          ListTile(
            // 2.1.7（WB_SPEC_218 第 ④ 节）：菜单管理从设置首页移入课表工具页底部，
            // 路由不变（/menu-manage），只在归拢层级、不再单独占首页一行。
            leading: const Icon(Icons.tune_outlined),
            title: const Text('菜单管理'),
            subtitle: const Text('右上角菜单里显示哪些功能、按什么顺序排'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/menu-manage'),
          ),
        ],
      ),
    );
  }
}
