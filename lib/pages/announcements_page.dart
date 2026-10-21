import 'package:flutter/material.dart';

import '../services/channel_service.dart';
import '../widgets/empty_state.dart';

/// 公告页（1.2.4）：展示公开通道里的全部公告（新→旧），打开即全部标已读。
class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late final Future<ChannelInfo?> _future = ChannelService.fetch();

  @override
  void initState() {
    super.initState();
    // 打开公告页 = 全部已读（横幅与角标据此消失）
    _future.then((info) {
      if (info != null) {
        ChannelService.markSeen(info.announcements.map((a) => a.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公告'), centerTitle: true),
      body: FutureBuilder<ChannelInfo?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data?.announcements ?? const [];
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.campaign_outlined,
              title: '暂无公告',
              message: '没有网络或暂时没有发布过公告，稍后再来看看',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final a = list[i];
              final scheme = Theme.of(context).colorScheme;
              return Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (a.isImportant)
                            Chip(
                              label: const Text('重要'),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                color: scheme.onErrorContainer,
                              ),
                              backgroundColor: scheme.errorContainer,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      if (a.date.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            a.date,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(a.body, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
