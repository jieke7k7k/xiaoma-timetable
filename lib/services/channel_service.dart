import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 公开通道（1.2.4）：App 从公开小仓库读一个 channel.json，同时拿到
/// 「最新版本信息」和「公告」——支撑检查更新与公告功能，无需后端服务器。
///
/// 通道文件：https://raw.githubusercontent.com/jieke7k7k/xiaoma-app-channel/main/channel.json
/// 发布方（开发者）改那个文件即可，所有装了 App 的人下次打开就能看到。
///
/// 本地状态存文档目录 channel_state.json：缓存的通道内容、已读公告 id、
/// 已关闭的横幅与版本号，避免重复打扰；所有读写都容错，坏了就当没缓存。
class LatestInfo {
  const LatestInfo({
    required this.versionName,
    required this.versionCode,
    required this.notes,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String versionName;
  final int versionCode;
  final String notes;
  final String downloadUrl;
  final String releaseUrl;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.date,
    required this.level,
  });

  final String id;
  final String title;
  final String body;
  final String date;

  /// normal 普通 / important 重要（首次会弹窗）
  final String level;

  bool get isImportant => level == 'important';
}

class ChannelInfo {
  const ChannelInfo({required this.latest, required this.announcements});

  final LatestInfo? latest;
  final List<Announcement> announcements;
}

/// 解析通道 JSON（纯函数，可测）；任何字段缺失/类型不对都尽量兜底，
/// 整体坏掉返回 null。
ChannelInfo? parseChannel(String raw) {
  try {
    final map = jsonDecode(raw);
    if (map is! Map<String, dynamic>) return null;
    LatestInfo? latest;
    final l = map['latest'];
    if (l is Map<String, dynamic>) {
      latest = LatestInfo(
        versionName: l['versionName'] as String? ?? '',
        versionCode: (l['versionCode'] as num?)?.toInt() ?? 0,
        notes: l['notes'] as String? ?? '',
        downloadUrl: l['downloadUrl'] as String? ?? '',
        releaseUrl: l['releaseUrl'] as String? ?? '',
      );
    }
    final announcements = <Announcement>[];
    final list = map['announcements'];
    if (list is List) {
      for (final a in list) {
        if (a is Map<String, dynamic> && a['id'] is String) {
          announcements.add(
            Announcement(
              id: a['id'] as String,
              title: a['title'] as String? ?? '',
              body: a['body'] as String? ?? '',
              date: a['date'] as String? ?? '',
              level: a['level'] as String? ?? 'normal',
            ),
          );
        }
      }
    }
    return ChannelInfo(latest: latest, announcements: announcements);
  } catch (_) {
    return null;
  }
}

/// 通道里的最新版是否比当前安装的新（按 versionCode 比，纯函数可测）
bool hasNewerVersion(ChannelInfo info, int currentVersionCode) =>
    info.latest != null && info.latest!.versionCode > currentVersionCode;

class ChannelService {
  ChannelService._();

  static const String channelUrl =
      'https://raw.githubusercontent.com/jieke7k7k/xiaoma-app-channel/main/channel.json';

  /// 问题反馈入口：公开通道仓的 Issues（源码仓是私有的，外人打不开）
  static const String issuesUrl =
      'https://github.com/jieke7k7k/xiaoma-app-channel/issues';

  /// 对外主页：公开通道仓
  static const String homeUrl =
      'https://github.com/jieke7k7k/xiaoma-app-channel';

  static Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/channel_state.json');
  }

  static Future<Map<String, dynamic>> _readState() async {
    try {
      final f = await _stateFile();
      if (!await f.exists()) return {};
      final map = jsonDecode(await f.readAsString());
      return map is Map<String, dynamic> ? map : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeState(Map<String, dynamic> state) async {
    try {
      final f = await _stateFile();
      await f.writeAsString(jsonEncode(state));
    } catch (_) {
      // 状态存不下只是少点记忆，不能影响功能
    }
  }

  /// 缓存中的通道内容（离线/首屏先用它垫着）
  static Future<ChannelInfo?> cached() async {
    final state = await _readState();
    final raw = state['cache'] as String?;
    return raw == null ? null : parseChannel(raw);
  }

  /// 拉取最新通道内容并写缓存；失败返回缓存，都没有返回 null
  static Future<ChannelInfo?> fetch() async {
    final state = await _readState();
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(channelUrl));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final raw = await resp.transform(utf8.decoder).join();
        final info = parseChannel(raw);
        if (info != null) {
          state['cache'] = raw;
          state['lastCheckAt'] = DateTime.now().millisecondsSinceEpoch;
          await _writeState(state);
          return info;
        }
      }
    } catch (_) {
      // 无网/超时：静默回退缓存
    }
    final raw = state['cache'] as String?;
    return raw == null ? null : parseChannel(raw);
  }

  /// 是否该做一次静默检查（距上次成功拉取超过 20 小时）
  static Future<bool> shouldSilentCheck() async {
    final state = await _readState();
    final last = state['lastCheckAt'] as int? ?? 0;
    return DateTime.now().millisecondsSinceEpoch - last >
        const Duration(hours: 20).inMilliseconds;
  }

  static Future<Set<String>> _idSet(String key) async {
    final state = await _readState();
    final list = state[key];
    return list is List ? list.whereType<String>().toSet() : {};
  }

  static Future<void> _addIds(String key, Iterable<String> ids) async {
    final state = await _readState();
    final cur = state[key] is List
        ? (state[key] as List).whereType<String>().toSet()
        : <String>{};
    cur.addAll(ids);
    state[key] = cur.toList();
    await _writeState(state);
  }

  /// 已读公告 id 集合
  static Future<Set<String>> seenIds() => _idSet('seenIds');

  static Future<void> markSeen(Iterable<String> ids) => _addIds('seenIds', ids);

  /// 被用户关掉横幅的公告 id（不再横幅打扰，公告页仍可见）
  static Future<Set<String>> dismissedIds() => _idSet('dismissedIds');

  static Future<void> dismiss(String id) => _addIds('dismissedIds', [id]);

  /// 已关闭过更新提示的版本号（同一个新版本只提示到被关掉为止）
  static Future<int> dismissedVersionCode() async {
    final state = await _readState();
    return state['dismissedVersionCode'] as int? ?? 0;
  }

  static Future<void> dismissVersion(int versionCode) async {
    final state = await _readState();
    state['dismissedVersionCode'] = versionCode;
    await _writeState(state);
  }
}
