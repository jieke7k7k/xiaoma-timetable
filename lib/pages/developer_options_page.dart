import 'package:flutter/material.dart';

import '../ui/app_styles.dart';

/// 开发者选项页（WB_SPEC_212 第 3 节）：路由 `/developer-options`。
///
/// 内置 AI 相关功能全部收进这里，普通用户在设置页看不到任何 AI 字样；
/// 解锁方式见 about_page.dart（关于页版本行连点 5 次），本页不做任何解锁
/// 判断——能进来说明已解锁（设置页只在解锁后显示入口）。
///
/// 内含且仅含以下三项，跳转与原页面行为一律不变：
/// - 智能助手聊天（/ai-chat）
/// - 智能助手设置（/ai-settings，内含 AI 桥 /bridge 入口）
/// - 智能助手历史（/ai-history）
class DeveloperOptionsPage extends StatelessWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('开发者选项'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
        children: [
          const _EntryTile(
            icon: Icons.chat_bubble_outline,
            title: '智能助手聊天',
            subtitle: '与智能助手对话（隐藏入口，功能与原来一致）',
            route: '/ai-chat',
          ),
          const Divider(height: 1, thickness: 1),
          const _EntryTile(
            icon: Icons.settings_outlined,
            title: '智能助手设置',
            subtitle: '接口地址、模型名、API Key、测试对话与 AI 桥',
            route: '/ai-settings',
          ),
          const Divider(height: 1, thickness: 1),
          const _EntryTile(
            icon: Icons.history_outlined,
            title: '智能助手历史',
            subtitle: '历史对话与操作记录（撤回）',
            route: '/ai-history',
          ),
        ],
      ),
    );
  }
}

/// 入口行（与设置首页同款：图标 + 名称 + 副标题 + ›）。
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
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }
}
