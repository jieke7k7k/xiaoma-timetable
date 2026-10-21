import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 更新日志页（1.2.4）：直接渲染打包进 App 的 CHANGELOG.md，
/// 发布新版时自动跟随，无需单独维护一份。
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('更新日志'), centerTitle: true),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('CHANGELOG.md'),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final scheme = Theme.of(context).colorScheme;
          final widgets = <Widget>[];
          for (final raw in snap.data!.split('\n')) {
            final line = raw.trimRight();
            if (line.startsWith('## ')) {
              widgets.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
                  child: Text(
                    line.substring(3),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ),
              );
            } else if (line.startsWith('# ')) {
              widgets.add(
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    line.substring(2),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            } else if (line.startsWith('- ')) {
              widgets.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 0, 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('· '),
                      Expanded(child: Text(line.substring(2))),
                    ],
                  ),
                ),
              );
            } else if (line.trim().isNotEmpty) {
              widgets.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(line),
                ),
              );
            }
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: widgets,
          );
        },
      ),
    );
  }
}
