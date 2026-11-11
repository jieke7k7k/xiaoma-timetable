import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../ui/app_styles.dart';
import 'web_import_page.dart';

/// 首次启动引导（1.2.4，WB_SPEC_231 第 3 节升级）：三页——
/// ① 课表从哪来（5 条导入路径一览，整行可点、点按直达）；
/// ② 桌面小部件；③ 记得备份（②③ 文案沿用 1.2.4，只补一个直达入口）。
///
/// 只在第一次打开时出现（标记存 app_settings.onboarding_done），可跳过。
///
/// 直达的路由闭环（规格第 3.2 节，硬要求）：点任意一条路径时**先**写引导完成
/// 标记（[onDone]，由根门卫落库并 invalidate），**再**导航——
/// 顺序颠倒会出现「已经进过导入页，退回却落在引导页」的死角。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, required this.onDone});

  /// 看完/跳过/直达前回调（由根门卫落库标记并放行主页）
  final Future<void> Function() onDone;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

/// 引导页里的一条导入路径（与 ImportPage 的入口一一对应，不多不少）
class _ImportPath {
  const _ImportPath({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    this.web = false,
  });

  final IconData icon;
  final String title;

  /// 照搬 ImportPage 对应入口的副标题，不重写
  final String subtitle;

  /// 直达的命名路由；[web] 为 true 时改走 WebImportPage（它没有命名路由）
  final String route;
  final bool web;
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  /// 5 条导入路径：教务网页抓取 / ICS / 图片识别 / PDF / 手动建课。
  /// 注意没有 Excel——导入页里不存在这个入口（规格第 9 节纠正 1）。
  static const _paths = <_ImportPath>[
    _ImportPath(
      icon: Icons.cloud_download_outlined,
      title: '从教务官网导入',
      subtitle: '内置浏览器登录学校教务系统，打开课表页后一键抓取',
      route: '/import',
      web: true,
    ),
    _ImportPath(
      icon: Icons.calendar_month_outlined,
      title: '导入 ICS 日历文件',
      subtitle: '从教务系统导出的 .ics 文件，自动匹配星期/节次/周次',
      route: '/import',
    ),
    _ImportPath(
      icon: Icons.photo_camera_outlined,
      title: '拍照 / 相册识别课表',
      subtitle: '本地 OCR 识别课表截图（中文），支持手动核对修正',
      route: '/import',
    ),
    _ImportPath(
      icon: Icons.picture_as_pdf_outlined,
      title: '导入 PDF 课表文件',
      subtitle: '提取 PDF 文本后复用相同解析流程',
      route: '/import',
    ),
    _ImportPath(
      icon: Icons.edit_outlined,
      title: '手动建课',
      subtitle: '直接填课程名与时间，适合临时加课、补录单门课',
      route: '/course-edit',
    ),
  ];

  /// 第 2、3 页：文案沿用 1.2.4 一字不动，只补一个直达设置页的入口
  static const _pages = [
    (
      Icons.widgets_outlined,
      '把课表放到桌面',
      '长按桌面空白处添加「小马课表」小部件，\n今天还没上完的课一眼就能看到，\n不用每次打开 App。',
      '/settings-widget',
      '去看桌面小部件设置',
    ),
    (
      Icons.backup_outlined,
      '记得备份',
      '你的数据只存在这台手机里。\n换手机前去「设置 → 数据管理」导出备份，\n新手机上一次恢复到位。',
      '/settings-data',
      '去看数据备份设置',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 当前学期 id（口径同 ImportPage 的 `_currentIdFrom`：取 isCurrent 那条）
  Future<int?> _currentSemesterId() async {
    try {
      final list = await ref.read(semestersProvider.future);
      for (final s in list) {
        if (s.isCurrent) return s.id;
      }
    } catch (_) {
      // 读库失败不挡路，下面退回内存里的当前学期
    }
    return ref.read(currentSemesterProvider).value?.id;
  }

  /// 直达一条导入路径：**先写标记、再导航**（规格第 3.2 节）
  Future<void> _openPath(_ImportPath path) async {
    final nav = Navigator.of(context);
    // 学期 id 必须在写标记之前读：标记一写，根门卫就会换掉本页
    final semesterId = path.web ? await _currentSemesterId() : null;
    await widget.onDone();
    if (path.web && semesterId != null) {
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => WebImportPage(semesterId: semesterId),
        ),
      );
      return;
    }
    // 全新用户还没有学期（或非网页路径）：退化为进导入页，由它自己的
    // 「新建学期 → 导入」流程兜住，不在引导页里另造一套建学期流程
    nav.pushNamed(path.route);
  }

  /// 第 2、3 页的直达按钮：同样先写标记再导航
  Future<void> _openSettings(String route) async {
    final nav = Navigator.of(context);
    await widget.onDone();
    nav.pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 共 3 页：0 = 路径一览，1、2 = _pages；末页是索引 2
    final isLast = _page == _pages.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => widget.onDone(),
                child: const Text('跳过'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length + 1,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  if (i == 0) return _buildPathsPage(context);
                  final (icon, title, body, route, actionLabel) = _pages[i - 1];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadii.logo),
                          ),
                          child: Icon(
                            icon,
                            size: 56,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => _openSettings(route),
                          child: Text(actionLabel),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length + 1; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: () {
                  if (isLast) {
                    widget.onDone();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(isLast ? '开始使用' : '下一页'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 第 1 页：课表从哪来——5 条路径一览，整行可点
  Widget _buildPathsPage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '课表从哪来',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            '任选一条，点一下直接去对应的导入方式。',
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.l),
          for (final p in _paths) _PathRow(path: p, onTap: () => _openPath(p)),
        ],
      ),
    );
  }
}

/// 一条导入路径：图标 + 标题 + 副标题，整行可点（点按即直达）
class _PathRow extends StatelessWidget {
  const _PathRow({required this.path, required this.onTap});

  final _ImportPath path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Icon(
                path.icon,
                size: 22,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
