import 'package:flutter/material.dart';

/// 使用帮助页（1.2.4）：三个最常用的操作各一段短说明。
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    const sections = [
      (
        Icons.upload_file_outlined,
        '从 WakeUp 等 App 导入课表',
        '先在对方 App 里把课表导出/分享为 ICS 文件（或截图、PDF）；'
            '然后打开小马课表的「设置 → 导入课表」，选这个文件即可。'
            '导入前会让你确认开学日期，导入后如有时间对不上的课程，会进入校准环节逐节对齐。',
      ),
      (
        Icons.backup_outlined,
        '数据备份与换机恢复',
        '所有课表数据都只存在这台手机里。去「设置 → 数据管理 → 备份到文件」'
            '把全部数据导出成一个 JSON 文件存好；换手机或重装后，在同一位置'
            '「从备份恢复」选这个文件即可整体还原。建议每个学期备份一次。',
      ),
      (
        Icons.widgets_outlined,
        '添加桌面小部件',
        '在手机桌面长按空白处 →「小组件」→ 找到「小马课表」添加。'
            '小部件会显示今天还没上完的课程；若长时间不刷新，先检查系统'
            '电池设置里是否限制了小马课表的后台运行，也可以到「设置 → 桌面小部件」'
            '里点一次「立即刷新桌面小部件」。',
      ),
      (
        Icons.notifications_outlined,
        '上课提醒没响？',
        '去「设置 → 提醒」确认开关已开，并允许小马课表的通知权限；'
            '小米等机型还需要在系统设置里给小马课表开「自启动」并把电池策略'
            '设为无限制，否则系统会拦截定时提醒。',
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
