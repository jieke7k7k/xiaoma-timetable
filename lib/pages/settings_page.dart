import 'package:flutter/material.dart';

import '../ui/app_styles.dart';

/// 设置页（QQ 式分级）
///
/// 2.0.5（WB_SPEC_205 第 1 节）起首页只保留分组标题 + 每类一行入口行
/// （图标 + 名称 + 一行副标题 + ›），**首页不出现任何开关 / 滑杆 / 选择器**；
/// 点进每个分类才看到该组的全部设置项（见 settings_sections.dart）。
///
/// 2.0.6（WB_SPEC_206 第 1 节）去掉全部分组小标题：小标题与入口行同名，
/// 纯重复。首页现在只留入口行，组与组之间用比行内更大的 AppSpacing 间距分隔；
/// 入口行本身、顺序、副标题、跳转全不动。
///
/// 取代 2.0.3 的「外观平铺首页」规范：原先直接摆在首页的学期设置三项、外观组
/// （实时预览 + 主题 + 格子外观 + 卡片显示 + 课程配色 + 主题颜色 + 字体）、
/// 提醒四项、学期与数据六行、权限摘要、桌面小组件说明，全部下沉到各自子页，
/// 控件与业务逻辑原样搬过去（不许丢项、不许改行为）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        children: [
          const _EntryTile(
            icon: Icons.badge_outlined,
            title: '学期设置',
            subtitle: '学期名称、开学日期、总周数',
            route: '/settings-semester',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.palette_outlined,
            title: '外观',
            subtitle: '主题、实时预览、格子外观、课程配色与显示字体',
            route: '/settings-appearance',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.notifications_active_outlined,
            title: '提醒',
            subtitle: '上课提醒、上课播报、今日课程常驻通知、提前提醒',
            route: '/settings-reminders',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.handyman_outlined,
            title: '课表工具',
            subtitle: '课程搜索、空闲时段、考试倒计时、导出课表图片、日期备注',
            route: '/course-tools',
          ),
          const SizedBox(height: AppSpacing.l),
          // 和智能助手聊聊：入口图标换像素小马灰版（2.0.5，WB_SPEC_205 第 5 节）
          ListTile(
            leading: const _XiaomaIcon(selected: false),
            title: const Text('和智能助手聊聊'),
            subtitle: const Text('带着课表上下文回答问题，也能帮你改课表（改前会先确认）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/ai-chat'),
          ),
          const SizedBox(height: AppSpacing.s),
          const _EntryTile(
            icon: Icons.settings_outlined,
            title: '智能助手设置',
            subtitle: '接口地址、模型名、API Key、测试对话与 AI 桥',
            route: '/ai-settings',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.folder_outlined,
            title: '学期与数据',
            subtitle: '导入课表、学期管理、备份恢复、导出 ICS、数据管理',
            route: '/settings-data',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.shield_outlined,
            title: '权限',
            subtitle: '通知、精确闹钟、电池优化',
            route: '/settings-permissions',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.info_outline,
            title: '关于小马课表',
            subtitle: '版本、检查更新、公告、更新日志与开源许可',
            route: '/about',
          ),
          const SizedBox(height: AppSpacing.l),
          const _EntryTile(
            icon: Icons.widgets_outlined,
            title: '桌面小组件',
            subtitle: '今日课程小组件的添加说明',
            route: '/settings-widget',
          ),
        ],
      ),
    );
  }
}

/// 分类入口行（图标 + 名称 + 一行副标题 + ›）：点进对应子页/已有二级页
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}

/// 像素小马图标（assets/icons/ 下两版 PNG），按选中态切换玫红/灰。
/// 用于「和智能助手聊聊」入口行，尺寸与原图标视觉大小一致（约 24dp）。
class _XiaomaIcon extends StatelessWidget {
  const _XiaomaIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      selected
          ? 'assets/icons/xiaoma_assistant_selected.png'
          : 'assets/icons/xiaoma_assistant_unselected.png',
      width: 24,
      height: 24,
    );
  }
}
