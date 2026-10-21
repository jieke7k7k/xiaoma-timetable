import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/ui_settings.dart';
import 'pages/course_edit_page.dart';
import 'pages/course_override_page.dart';
import 'pages/course_search_page.dart';
import 'pages/exam_countdown_page.dart';
import 'pages/free_time_page.dart';
import 'pages/share_image_page.dart';
import 'pages/import_page.dart';
import 'pages/semester_manage_page.dart';
import 'pages/settings_page.dart';
import 'pages/ui_settings_page.dart';
import 'pages/splash_page.dart';
import 'pages/time_settings_page.dart';
import 'pages/week_view_page.dart';
import 'providers/providers.dart';
import 'services/fonts_service.dart';
import 'services/notification_service.dart';
import 'services/ongoing_notice_service.dart';
import 'services/widget_service.dart';
import 'ui/app_styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化本地通知（时区 + 插件 + 渠道）；失败仅打日志，不影响 App 启动
  await NotificationService.instance.initialize();
  // 载入用户导入的字体（1.2.1）：runApp 前完成注册，主题首帧即生效、无闪烁
  await FontsService.init();
  runApp(const ProviderScope(child: SimpleTimetableApp()));
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
    // 主题种子色与显示字体由「界面设置」驱动（1.1.1）：种子色默认雾绿 0xFF6B8E7B，
    // 用户可在界面设置里换预置或自定义；provider 未加载完时用默认值渲染首帧
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
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
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
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
          ),
        ),
      ),
      themeMode: themeMode,
      // 启动页作为初始路由：品牌展示 + 兜住首帧读库窗口，停留后替换进主页
      initialRoute: '/splash',
      routes: {
        '/': (context) => const HomeShell(),
        // 应用启动页（纯 Dart，无原生资源依赖）
        '/splash': (context) => const SplashPage(),
        // 课程新建/编辑：arguments 为 courseId(int，编辑) 或 Map(新建预填)
        '/course-edit': (context) => const CourseEditPage(),
        // 作息时间设置
        '/time-settings': (context) => const TimeSettingsPage(),
        // 界面设置（格子外观/配色方案/主题色/字体）
        '/ui-settings': (context) => const UiSettingsPage(),
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
      },
    );
  }
}

/// 主框架：底部导航「课表 / 新建 / 设置」
///
/// IndexedStack 只保留「课表」和「设置」两个常驻页：新建课程页走独立路由，
/// 避免在根路由保存时 pop 黑屏或表单状态残留。
/// 中间的「新建」按钮不切换页面，而是弹出选择框（手动新建 / 导入课表）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 当前常驻页：0 = 课表，1 = 设置
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // App 启动后重排当日提醒（滚动窗口向前推进，覆盖 App 被杀后台的场景）。
    // rescheduleAll 内部已捕获全部异常，安全地 fire-and-forget。
    unawaited(NotificationService.instance.rescheduleAll());
    // App 启动后刷新今日课程常驻通知（读库 + MethodChannel，内部已捕获异常）
    unawaited(OngoingNoticeService.instance.refresh());
    // App 启动后刷新桌面小组件（读库 + home_widget，内部已捕获异常）
    unawaited(WidgetService.instance.refreshWidgets());
  }

  static const _pages = [
    WeekViewPage(),
    SettingsPage(),
  ];

  void _onDestinationSelected(int i) {
    if (i == 1) {
      // 中间「新建」：不切页，弹出新建方式选择
      _showCreateSheet();
      return;
    }
    // i == 0 课表，i == 2 设置
    setState(() => _index = i == 2 ? 1 : 0);
  }

  /// 新建方式选择：手动新建课程 / 导入课表（ICS / 图片 OCR / PDF）
  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('手动新建课程'),
              subtitle: const Text('逐项填写课程信息'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/course-edit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('导入课表'),
              subtitle: const Text('ICS / 图片 OCR / PDF，支持冲突检测'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/import');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index == 0 ? 0 : 2,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: '新建',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
