import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/providers.dart';
import '../services/channel_service.dart';
import '../utils/tap_unlock.dart';

/// 关于页（1.2.4）：版本号、检查更新、公告入口、更新日志、开源许可、
/// 使用帮助、问题反馈与开发者信息——完整应用该有的收尾都在这一页。
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  PackageInfo? _pkg;
  ChannelInfo? _channel;
  Set<String> _seen = {};
  bool _checking = false;
  String? _updateHint;

  /// 版本行连点解锁计数器（WB_SPEC_212 第 3 节）：5 次、2 秒窗口内判定。
  final TapUnlockCounter _versionTapCounter = TapUnlockCounter();

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _pkg = p);
    });
    ChannelService.cached().then((c) async {
      final seen = await ChannelService.seenIds();
      if (mounted) {
        setState(() {
          _channel = c;
          _seen = seen;
        });
      }
    });
  }

  int get _currentCode => int.tryParse(_pkg?.buildNumber ?? '') ?? 0;

  /// 版本行点击：连续点满 5 次（2 秒内）解锁开发者选项（WB_SPEC_212 第 3 节）。
  ///
  /// 误触一次不解锁、不弹窗、不提示；界面上不写任何「连点五次解锁」之类文案，
  /// 也不向普通用户透露解锁方法。解锁成功后给一句轻提示，方便开发者确认。
  /// 2.1.0 返修：等写库完成再提示，写库失败提示失败不谎报；已解锁时重复连点
  /// 不再重复写库、不再重复提示。
  Future<void> _onVersionTap() async {
    if (!_versionTapCounter.tap()) return;
    if (ref.read(developerOptionsProvider).value == true) return;
    final ok = await ref.read(developerOptionsProvider.notifier).unlock();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '开发者选项已开启' : '解锁失败，请稍后重试')),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('打不开这个链接，请检查浏览器')));
      }
    }
  }

  Future<void> _checkUpdate({required bool manual}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      if (manual) _updateHint = null;
    });
    final info = await ChannelService.fetch();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _channel = info;
    });
    if (info == null || info.latest == null) {
      if (manual) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('检查失败：暂时连不上更新通道，稍后再试')));
      }
      return;
    }
    final latest = info.latest!;
    if (_currentCode > 0 && latest.versionCode > _currentCode) {
      setState(() => _updateHint = '有新版本 ${latest.versionName} 可用');
      await _showUpdateDialog(latest);
    } else if (manual) {
      setState(() => _updateHint = '已是最新版本');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已是最新版本')));
    }
  }

  Future<void> _showUpdateDialog(LatestInfo latest) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('新版本 ${latest.versionName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (latest.notes.isNotEmpty) Text(latest.notes),
            const SizedBox(height: 8),
            Text(
              '当前版本 ${_pkg?.version ?? ''}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('以后再说'),
          ),
          if (latest.releaseUrl.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _launch(latest.releaseUrl);
              },
              child: const Text('更新说明'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (latest.downloadUrl.isNotEmpty) _launch(latest.downloadUrl);
            },
            child: const Text('去下载'),
          ),
        ],
      ),
    );
  }

  void _showPrivacy() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('隐私说明'),
        content: const SingleChildScrollView(
          child: Text(
            '小马课表是一款完全本地运行的应用：\n\n'
            '· 你的课表、学期、考试与全部设置只保存在这台手机里，不会上传到任何服务器。\n'
            '· 唯一的联网行为是读取公开的「版本与公告」通道（只下载、不发送你的任何数据），以及你主动点的外链（下载新版、问题反馈）。\n'
            '· 导入的字体文件保存在 App 私有目录，卸载即删除。\n'
            '· 数据备份文件由你自己保管，里面包含你的全部课表数据，请不要随意转发。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unseen =
        _channel?.announcements.where((a) => !_seen.contains(a.id)).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('关于小马课表'), centerTitle: true),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.calendar_month,
                size: 40,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '小马课表',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          // 版本行（WB_SPEC_212 第 3 节）：连点 5 次解锁开发者选项；
          // 版本还没加载出来时不可点（也谈不上解锁）
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pkg == null ? null : _onVersionTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  _pkg == null
                      ? '版本加载中…'
                      : '版本 ${_pkg!.version}（${_pkg!.buildNumber}）',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('开发者：jieke × 小马', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: Text(
              _updateHint ??
                  (_pkg == null ? '读取当前版本中…' : '当前 ${_pkg!.version}'),
            ),
            trailing: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => _checkUpdate(manual: true),
          ),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('公告'),
            subtitle: Text(
              _channel == null
                  ? '暂无缓存，点开查看'
                  : _channel!.announcements.isEmpty
                  ? '暂无公告'
                  : '最新：${_channel!.announcements.first.title}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unseen > 0)
                  Badge(
                    label: Text('$unseen'),
                    child: const Icon(Icons.chevron_right),
                  )
                else
                  const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () async {
              await Navigator.pushNamed(context, '/announcements');
              final seen = await ChannelService.seenIds();
              if (mounted) setState(() => _seen = seen);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('更新日志'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/changelog'),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('使用帮助'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/help'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('隐私说明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPrivacy,
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('开源许可'),
            subtitle: const Text('第三方库与字体的许可声明'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: '小马课表',
              applicationVersion: _pkg?.version,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('问题反馈'),
            subtitle: const Text('到公开通道仓提 Issue'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launch(ChannelService.issuesUrl),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('项目主页'),
            subtitle: const Text('公开通道仓（版本与公告发布处）'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launch(ChannelService.homeUrl),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
