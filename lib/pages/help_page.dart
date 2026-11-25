import 'package:flutter/material.dart';

/// 使用帮助页（1.2.4）：四个最常用的操作各一段短说明。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = [
      (
        Icons.upload_file_outlined,
        '从 WakeUp 等 App 导入课表',
        '在原 App 中将课表导出为 ICS 文件（或截图、PDF），'
            '再于「设置 → 数据备份与换机 → 导入课表」（或主页右上角「+」→ 导入课表）中选择该文件。'
            '导入前需确认开学日期；作息时间不一致时，将逐节校准。',
      ),
      (
        Icons.backup_outlined,
        '数据备份与换机恢复',
        '全部数据仅保存在本机。于「设置 → 数据备份与换机 → 备份到文件」'
            '导出 JSON 备份；换机或重装后，在同一位置'
            '「从备份恢复」导入该文件。建议每学期备份一次。',
      ),
      (
        Icons.widgets_outlined,
        '添加桌面小部件',
        '长按桌面空白处 →「小组件」→ 添加「小马课表」。'
            '小部件显示当日未结束的课程；若长时间未刷新，请检查系统'
            '电池设置是否限制后台运行，或于「设置 → 桌面小组件」'
            '执行「立即刷新桌面小部件」。',
      ),
      (
        Icons.notifications_outlined,
        '上课提醒未响',
        '请确认「设置 → 上课提醒」开关已开启，并授予通知权限；'
            '小米等机型还需在系统设置中开启「自启动」，并将电池策略'
            '设为无限制，否则系统将拦截定时提醒。',
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('使用帮助'), centerTitle: true),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final (icon, title, body) = sections[i];
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
