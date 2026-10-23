import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/ui_settings.dart';
import 'database/dao.dart';
import 'pages/about_page.dart';
import 'pages/ai_chat_page.dart';
import 'pages/ai_settings_page.dart';
import 'pages/announcements_page.dart';
import 'pages/bridge_page.dart';
import 'pages/changelog_page.dart';
import 'pages/course_edit_page.dart';
import 'pages/course_tools_page.dart';
import 'pages/data_manage_page.dart';
import 'pages/course_override_page.dart';
import 'pages/course_search_page.dart';
import 'pages/exam_countdown_page.dart';
import 'pages/free_time_page.dart';
import 'pages/help_page.dart';
import 'pages/notes_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/permission_page.dart';
import 'pages/share_image_page.dart';
import 'pages/import_page.dart';
import 'pages/semester_manage_page.dart';
import 'pages/settings_page.dart';
import 'pages/time_settings_page.dart';
import 'pages/week_view_page.dart';
import 'providers/providers.dart';
import 'widgets/permission_guide.dart';

import 'package:quick_actions/quick_actions.dart';

import 'services/auto_backup_service.dart';
import 'services/bridge_service.dart';
import 'services/fonts_service.dart';
import 'services/notification_service.dart';
import 'services/ongoing_notice_service.dart';
import 'services/widget_service.dart';
import 'ui/app_styles.dart';
import 'ui/grid_metrics.dart';

/// 全局异常日志的持久化键（app_settings 表）。
/// 只保留最近一条，值为「时间 + 摘要」，供用户反馈/自查时查看。
const String kLastErrorLogKey = 'last_error_log';

void main() {
  // 全局异常兜底（1.3.1）：整个启动流程包进 zone——框架层错误（构建/布局/绘制）
  // 由 FlutterError.onError 接住，zone 内未捕获的异步异常由第二个回调接住，
  // 两条路统一落到 _recordError，不再红屏原文、也不静默闪退。
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 框架层错误（构建/布局/绘制抛的异常）：先按 Flutter 默认方式输出到
      // 控制台，再记一条日志。不转发给 zone，避免同一错误重复记录两次。
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(_recordError(details.exception, details.stack));
      };
      // 兜底界面：任何 build 失败都显示中文提示，不再是红屏堆栈原文
      ErrorWidget.builder = (_) => const _FriendlyErrorWidget();
      await _initServices();
      runApp(const ProviderScope(child: SimpleTimetableApp()));
      // 通知初始化挪到首帧之后：时区库加载 + 插件平台通道都不是首帧渲染所需，
      // 不再占启动串行时间。失败只打日志不阻断（rescheduleAll 内部也会兜底
      // 初始化，两者共用同一个 Future，不会重复跑、也不会抢跑）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initNotifications());
      });
    },
    (error, stack) => unawaited(_recordError(error, stack)),
  );
}

/// 启动前置初始化（1.3.2 瘦身）：只留导入字体。
///
/// 字体必须在 runApp 前注册完，否则首帧用默认字体、字体到位后再换一次会闪；
/// 本地通知与首帧无关，已挪到 [_initNotifications]（首帧后跑）。
/// 任何一步抛错都只打日志，绝不阻断 runApp。
Future<void> _initServices() async {
  try {
    // 载入用户导入的字体（1.2.1）：runApp 前完成注册，主题首帧即生效、无闪烁
    await FontsService.init();
  } catch (e) {
    debugPrint('字体初始化失败：$e');
  }
}

/// 本地通知初始化（1.3.2）：首帧之后再跑，不再拖慢启动。
///
/// 失败只是不响铃，容错风格与上一轮一致——只打日志、绝不阻断，
/// 也不写 last_error_log（那是给崩溃兜底的，这里是可预期的降级）。
Future<void> _initNotifications() async {
  try {
    // 初始化本地通知（时区 + 插件 + 渠道）；内部幂等，与 rescheduleAll 共用一次
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('通知初始化失败：$e');
  }
}

/// 记录最近一条错误到 app_settings 的 [kLastErrorLogKey]（覆盖式，只留一条）。
///
/// 摘要取异常 toString（连续空白压平）后截断到 300 字；堆栈太长且多是内部帧，
/// 只留在控制台，不入库。[stack] 参数保留给将来接上报用。
/// 写库本身可能失败（库还没建好、磁盘满、 isolate 已死），失败一律吞掉——
/// 兜底逻辑里再抛异常会变成二次崩溃，比原错误更糟。
Future<void> _recordError(Object error, StackTrace? stack) async {
  try {
    final summary = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = summary.length > 300 ? summary.substring(0, 300) : summary;
    final text = '[${_formatDateTime(DateTime.now())}] $short';
    await Dao.instance.setSetting(kLastErrorLogKey, text);
  } catch (_) {
    // 兜底的兜底：静默
  }
}

/// 「yyyy-MM-dd HH:mm:ss」本地时间文本（不引 intl，避免 locale 数据依赖）
String _formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// 兜底错误界面（1.3.1）：替换 Flutter 默认的红屏堆栈。
///
/// 刻意不依赖 Theme / Material（出错时祖先未必存在），自带 Directionality
/// 与 DefaultTextStyle，保证它自己永远不会再抛异常。
class _FriendlyErrorWidget extends StatelessWidget {
  const _FriendlyErrorWidget();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF5A5A5A),
          decoration: TextDecoration.none,
        ),
        textAlign: TextAlign.center,
        // 不做「撑满父级」的写法（width: double.infinity 在父级无界宽时
        // 会算出无限尺寸而二次抛错），尺寸由内容决定，居中交给 Column
        child: Container(
          color: const Color(0xFFF5F2EC),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Color(0xFF8A8578),
              ),
              const SizedBox(height: 12),
              const Text(
                '页面出错了',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                '小马课表遇到了一点问题，已记录日志。\n'
                '重启应用一般就能恢复；若反复出现，'
                '可在「设置 → 数据管理」先备份再反馈。',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 小马课表 App 入口
class SimpleTimetableApp extends ConsumerWidget {
  const SimpleTimetableApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Material 3 风格，浅色/深色无缝切换
    // 主题三档（跟随系统/浅色/深色）由 ThemeSettingsNotifier 持久化在 app_settings 表，
    // provider 加载完成前（首帧）先按跟随系统渲染，读库完成后立即切到持久化值
    final themeMode =
        ref.watch(themeSettingsProvider).value ?? ThemeMode.system;
    // 主题种子色与显示字体由「外观」设置驱动（1.1.1）：种子色默认雾绿 0xFF6B8E7B，
    // 用户可在外观设置里换预置或自定义；provider 未加载完时用默认值渲染首帧
    final uiSettings =
        ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final seed = Color(uiSettings.themeSeedValue);
    final colorScheme = ColorScheme.fromSeed(seedColor: seed);
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    final fontFamily = FontsService.resolveFamily(uiSettings);
    // 全局统一圆角/弹层形状（阶段五·视觉打磨）：卡片 12px、BottomSheet 顶部 16px，
    // 具体常量见 ui/app_styles.dart，页面内不要再各自硬编码
    return MaterialApp(
      title: '小马课表',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        fontFamily: fontFamily,
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.sheet),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkColorScheme,
        fontFamily: fontFamily,
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadii.sheet),
            ),
          ),
        ),
      ),
      themeMode: themeMode,
      // 1.3.2 启动提速：取消应用内启动页，首帧直接进主页。
      // 原生启动窗口背景（Android LaunchTheme 的 launch_background）一直铺到
      // Flutter 首帧，所以不会白闪；主页数据未就绪时自带加载态（见 _RootGate
      // 与 WeekViewPage），不会是坏掉的空白页。
      initialRoute: '/',
      routes: {
        '/': (context) => const _RootGate(),
        // 课程新建/编辑：arguments 为 courseId(int，编辑) 或 Map(新建预填)
        '/course-edit': (context) => const CourseEditPage(),
        // 作息时间设置
        '/time-settings': (context) => const TimeSettingsPage(),
        // 课程导入入口
        '/import': (context) => const ImportPage(),
        // 学期管理（新建/切换/删除学期）
        '/semester-manage': (context) => const SemesterManagePage(),
        // 考试倒计时（当前学期设置了考试日期的课程，按日期升序）
        '/exam-countdown': (context) => const ExamCountdownPage(),
        // 课程搜索（1.2.0：按课名/老师/教室搜当前学期课程，点结果跳周）
        '/course-search': (context) => const CourseSearchPage(),
        // 空闲时段（1.2.0：按周列出每天没课的时段）
        '/free-time': (context) => const FreeTimePage(),
        // 课表导出图片（1.2.0：当前浏览周渲染成图走系统分享）
        '/share-image': (context) => const ShareImagePage(),
        // 节假日单次调课：arguments = {'courseId': int, 'week': int（originalWeek）}
        '/course-override': (context) => const CourseOverridePage(),
        // 关于页（1.2.4：版本/检查更新/公告/日志/许可/帮助/反馈）
        '/about': (context) => const AboutPage(),
        // 公告页（1.2.4：公开通道公告列表）
        '/announcements': (context) => const AnnouncementsPage(),
        // 更新日志页（1.2.4：渲染打包的 CHANGELOG.md）
        '/changelog': (context) => const ChangelogPage(),
        // 使用帮助页（1.2.4）
        '/help': (context) => const HelpPage(),
        // 备注（v3：按日期分组的备忘，同步到常驻通知与桌面小部件）
        '/notes': (context) => const NotesPage(),
        // 内置 AI 助手（2.0.0）：底栏左键是同一个页面，这里给设置页直达用
        '/ai-chat': (context) => const AiChatPage(),
        // AI 助手设置（接口地址 / 模型 / Key）
        '/ai-settings': (context) => const AiSettingsPage(),
        // 课表工具（2.0.2：课程搜索 / 空闲时段 / 考试倒计时 / 导出课表图片 / 日期备注）
        '/course-tools': (context) => const CourseToolsPage(),
        // 权限（通知 / 精确闹钟 / 电池优化，首次启动会引导一次）
        '/permissions': (context) => const PermissionPage(),
        // 数据管理页（1.2.4：占用/备份快捷入口/恢复出厂）
        '/data-manage': (context) => const DataManagePage(),
        // AI 桥（1.3.6：把 GitHub 私有仓当命令信箱；2.0.2 起入口在智能助手设置页）
        '/bridge': (context) => const BridgePage(),
      },
    );
  }
}

/// 根门卫（1.2.4）：第一次打开先过首次引导，看完才进主框架。
/// 引导标记存 app_settings，恢复出厂后会重新出现。
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(onboardingDoneProvider);
    return done.when(
      data: (d) => d
          ? const HomeShell()
          : OnboardingPage(
              onDone: () async {
                await Dao.instance.setSetting('onboarding_done', '1');
                ref.invalidate(onboardingDoneProvider);
              },
            ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // 读标记失败时不挡路，直接进主页
      error: (_, __) => const HomeShell(),
    );
  }
}

/// 主框架：底栏三键「智能助手 / 主页 / 设置」（2.0.0 改版，2.0.1 AI 改名智能助手）
///
/// IndexedStack 常驻三个页：AI 聊天、课表主页、设置；默认停在**主页**。
/// 原来的「新建」页签不再占底栏，改成主页右上角的「+」按钮（见 WeekViewPage），
/// 弹出的仍是原来那套「手动新建 / 导入课表」选择框。
///
/// 底栏是自绘的 [_HomeBottomBar]（不用 NavigationBar）：NavigationDestination
/// 长按会浮出 label 气泡（用户发过截图），自绘按钮天然没有这个行为，也不包
/// Tooltip。2.0.2 起三键等大平铺，中间不再是凸起大圆钮（见 [_HomeBottomBar]）。
///
/// 1.3.6 起是 [ConsumerStatefulWidget]：AI 桥的静默同步可能产生数据变更，
/// 改完要失效 coursesProvider/notesProvider 并联动三个服务，这些都得有 ref。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// 当前常驻页：0 = 智能助手，1 = 主页，2 = 设置
  int _index = 1;

  @override
  void initState() {
    super.initState();
    // 1.3.2 启动提速：启动联动全部挪到首帧之后。
    // 提醒重排 / 常驻通知 / 小组件都要读库或走平台通道，快捷入口注册也是通道调用，
    // 放在 initState 里会和课表首帧渲染抢 isolate；首帧后并发触发，课表先出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupTasks());
      // 首次启动的权限引导（只走一次）；它是几个对话框，不占启动的关键路径
      unawaited(_guidePermissionsOnce());
    });
  }

  /// 首次启动依次引导三项权限（通知 → 精确闹钟 → 电池优化）。
  ///
  /// 标记在引导开始前就写进 app_settings（见 PermissionService.markGuided），
  /// 所以每一步都能「跳过」、跳过与拒绝都不再自动弹。失败只打日志，不打扰启动。
  Future<void> _guidePermissionsOnce() async {
    try {
      await runPermissionGuide(context);
    } catch (e) {
      debugPrint('权限引导失败：$e');
    }
  }

  /// 首帧后的启动联动：五项互不依赖并发跑完，常驻通知顺序殿后（见下方 C5 注）。
  ///
  /// 三个服务内部都已捕获异常，这里再兜一层 try/catch——任一环节出错只打日志，
  /// 不弹错、不影响课表（与上一轮「失败不阻断」的容错风格一致）。
  Future<void> _runStartupTasks() async {
    try {
      await Future.wait(<Future<void>>[
        // 重排当日提醒（滚动窗口向前推进，覆盖 App 被杀后台的场景）。
        // 备注常驻通知在它内部末尾刷新（必须在 cancelAll 之后重建），不另起一项
        NotificationService.instance.rescheduleAll(),
        // 刷新桌面小组件（读库 + home_widget）
        WidgetService.instance.refreshWidgets(),
        _setupQuickActions(),
        // 自动备份（7 天一次，内部全静默，不到期立即返回）
        AutoBackupService.runIfDue(),
        // AI 桥静默同步（未配置会立即返回，失败也静默）
        _silentBridgeSync(),
      ]);
      // 今日课程常驻通知必须排在 rescheduleAll 之后：rescheduleAll 的 cancelAll
      // 会连原生常驻通知一起清掉，并发执行时谁后到谁说了算，常驻通知会被误清
      // （复审 C5）。顺序执行保证它是在 cancelAll 之后重建的。
      await OngoingNoticeService.instance.refresh();
    } catch (e) {
      debugPrint('启动联动刷新失败：$e');
    }
  }

  /// 首帧后静默同步一次 AI 桥。
  ///
  /// 失败一律静默：网不好、令牌过期、仓库还没建 commands/ 目录都属于可预期的
  /// 日常状态，启动时不该用它打扰用户；真有异常也只是打日志（不带令牌）。
  Future<void> _silentBridgeSync() async {
    try {
      final outcome = await BridgeService.instance.syncNow();
      if (outcome.changed && mounted) _applyBridgeChanges();
    } catch (e) {
      debugPrint('AI 桥静默同步失败：$e');
    }
  }

  /// 桥改动数据后的联动刷新（与 BridgePage._applyBridgeChanges 同一份口径，
  /// 改这里记得同步另一处）
  void _applyBridgeChanges() {
    ref.invalidate(coursesProvider);
    ref.invalidate(notesProvider);
    unawaited(NotificationService.instance.rescheduleAll());
    unawaited(WidgetService.instance.refreshWidgets());
  }

  /// 桌面长按快捷入口（1.2.4）：新建课程 / 导入课表直达
  Future<void> _setupQuickActions() async {
    const quickActions = QuickActions();
    await quickActions.initialize((type) {
      if (!mounted) return;
      if (type == 'shortcut_new') {
        Navigator.pushNamed(context, '/course-edit');
      } else if (type == 'shortcut_import') {
        Navigator.pushNamed(context, '/import');
      }
    });
    await quickActions.setShortcutItems(const [
      ShortcutItem(
        type: 'shortcut_new',
        localizedTitle: '新建课程',
        icon: 'ic_shortcut_new',
      ),
      ShortcutItem(
        type: 'shortcut_import',
        localizedTitle: '导入课表',
        icon: 'ic_shortcut_import',
      ),
    ]);
  }

  static const _pages = [AiChatPage(), WeekViewPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _HomeBottomBar(
          index: _index,
          onChanged: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

/// 底栏：左「智能助手」、中「主页」、右「设置」，三键等大平铺
///
/// **刻意不用 NavigationBar**：NavigationDestination 长按会浮出 label 气泡
/// （用户明确要求不要），自绘按钮天然没有这个行为，也不包 Tooltip。
/// 2.0.2（WB-202 第 1 项）：中间按钮取消凸起圆形样式，与左右两键完全一致——
/// 同图标大小（26）、同文字（11 号常显小字）、同高度，三键等大；选中态沿用
/// 主题色 + 加粗即可辨（见 [_SideButton]）。
class _HomeBottomBar extends StatelessWidget {
  const _HomeBottomBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: kBottomBarHeight,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        // 三键等大：各占三分之一宽，图标/文字/高度完全一致
        child: Row(
          children: [
            Expanded(
              child: _SideButton(
                icon: index == 0
                    ? Icons.smart_toy
                    : Icons.smart_toy_outlined,
                label: '智能助手',
                selected: index == 0,
                onTap: () => onChanged(0),
              ),
            ),
            Expanded(
              child: _SideButton(
                icon: index == 1
                    ? Icons.calendar_view_week
                    : Icons.calendar_view_week_outlined,
                label: '主页',
                selected: index == 1,
                onTap: () => onChanged(1),
              ),
            ),
            Expanded(
              child: _SideButton(
                icon: index == 2 ? Icons.settings : Icons.settings_outlined,
                label: '设置',
                selected: index == 2,
                onTap: () => onChanged(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏三个按钮共用（2.0.2 起中间「主页」也是这一样式）：图标 + 常显小字
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      // 不包 Tooltip：长按不许弹名称气泡（用户明确要求）
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
