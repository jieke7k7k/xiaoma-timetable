import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/ui_settings.dart';
import 'database/dao.dart';
import 'pages/about_page.dart';
import 'pages/announcements_page.dart';
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
import 'pages/menu_manage_page.dart';
import 'pages/semester_manage_page.dart';
import 'pages/settings_page.dart';
import 'pages/settings_sections.dart';
import 'pages/time_settings_page.dart';
import 'pages/week_view_page.dart';
import 'providers/providers.dart';
import 'widgets/home_tab_bar.dart';

import 'package:quick_actions/quick_actions.dart';

import 'services/auto_backup_service.dart';
import 'services/fonts_service.dart';
import 'services/notification_service.dart';
import 'services/ongoing_notice_service.dart';
import 'utils/color_schemes.dart';
import 'utils/route_observer.dart';
import 'services/widget_service.dart';
import 'ui/app_styles.dart';
import 'ui/bottom_bar_metrics.dart';
import 'ui/clean_gap_input_border.dart';
import 'ui/shell_transition.dart';
import 'ui/page_transitions.dart';

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

/// 输入框主题：五态边框都用 CleanGapOutlineInputBorder（WB_SPEC_231 第 11 节），
/// 抽成一个函数，免得浅色/深色各抄 5 段、改衬底参数时漏改某几态（Kimi 复审优化 1）。
InputDecorationThemeData _gapInputDecorationTheme(ColorScheme scheme) {
  CleanGapOutlineInputBorder border(Color color, {double width = 1.0}) =>
      CleanGapOutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.chip),
        borderSide: BorderSide(color: color, width: width),
        pageBackgroundColor: scheme.surface,
        fillColor: scheme.surfaceContainerHighest,
      );
  return InputDecorationThemeData(
    filled: true,
    fillColor: scheme.surfaceContainerHighest,
    border: border(scheme.outlineVariant),
    enabledBorder: border(scheme.outlineVariant),
    focusedBorder: border(scheme.primary, width: 1.5),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, width: 1.5),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
    // 多行框的 label 贴顶，不悬空压在中间
    alignLabelWithHint: true,
  );
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
    // 主题种子色与显示字体由「外观」设置驱动（1.1.1）：种子色默认雾绿 0xFF3E7B67，
    // 用户可在外观设置里换预置或自定义；provider 未加载完时用默认值渲染首帧
    final uiSettings =
        ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final seed = Color(uiSettings.themeSeedValue);
    // 生产配色唯一入口（复查 Bug 1 / 优化 2）：fidelity 保真 + surface 与
    // 整套容器色一并中性化（只留 4% 种子倾向），浅/深两处同口径。
    final colorScheme = buildAppColorScheme(seed, Brightness.light);
    final darkColorScheme = buildAppColorScheme(seed, Brightness.dark);
    final fontFamily = FontsService.resolveFamily(uiSettings);
    // 全局统一圆角/弹层形状（阶段五·视觉打磨）：卡片 12px、BottomSheet 顶部 16px，
    // 具体常量见 ui/app_styles.dart，页面内不要再各自硬编码
    return MaterialApp(
      title: '小马课表',
      debugShowCheckedModeBanner: false,
      // WB_SPEC_220：全局中文 locale（flutter_localizations，SDK 内置包，
      // 不用 intl 初始化）：两处开学日期日历与其它 Material 文案自动变中文。
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 路由观察者（复查 Bug 3）：子页返回时相关页面可感知并重查状态
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        fontFamily: fontFamily,
        // 2.0.9（WB_SPEC_210 第 1 节）：顶栏全局压矮（toolbarHeight 56 → 48）并贴顶——
        // 状态栏透明（露出 AppBar 同背景色，不再有顶部空白带），浅色下状态栏图标用深色保证可辨。
        appBarTheme: const AppBarTheme(
          toolbarHeight: 48,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
        // 2.1.0（WB_SPEC_212 第 5 节）：全 App 统一标准右滑转场（时长 300ms、
        // 曲线 fastOutSlowIn、不做预测性返回；系统移除动画时归零，见 AppSlidePageTransitionsBuilder）
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: AppSlidePageTransitionsBuilder(android: true),
            TargetPlatform.iOS: AppSlidePageTransitionsBuilder(android: false),
          },
        ),
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          ),
        ),
        // WB_SPEC_230 第 3.1 节：全 App 弹出菜单外壳统一（三处 ⋮ 菜单共用）。
        // 只管外壳三项，position/offset 由各调用点单独传（顶栏与列表行内不同）。
        popupMenuTheme: PopupMenuThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.menu),
          ),
          color: colorScheme.surfaceContainerHigh,
          elevation: 6,
        ),
        // WB_SPEC_230 第 5.1 节：输入框统一成圆角灰阶填充框，一次管全 App
        // （废除 M3 默认下划线样式——多字段表单里横线与 Divider 分不清）。
        // 圆角走 AppRadii.chip，与全站圆润黑白灰统一；不设高度约束，
        // 多行输入框（备注 maxLines: 3）不会被压扁成一行。
        // WB_SPEC_231 第 11 节：边框换成 CleanGapOutlineInputBorder——
        // 标签浮起时缺口处补双色衬底，横线不再从字中间穿过（详见该类注释）。
        inputDecorationTheme: _gapInputDecorationTheme(colorScheme),
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
        // 2.0.9：深色下状态栏图标用浅色保证可辨，其余与浅色一致。
        appBarTheme: const AppBarTheme(
          toolbarHeight: 48,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
        // 2.1.0（WB_SPEC_212 第 5 节）：深色与浅色同款右滑转场，全 App 统一
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: AppSlidePageTransitionsBuilder(android: true),
            TargetPlatform.iOS: AppSlidePageTransitionsBuilder(android: false),
          },
        ),
        cardTheme: const CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          ),
        ),
        // WB_SPEC_230 第 3.1 节：深色菜单外壳（底色比浅色低一档、阴影略重，
        // 深色下靠阴影分层更自然）。
        popupMenuTheme: PopupMenuThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.menu),
          ),
          color: darkColorScheme.surfaceContainer,
          elevation: 8,
        ),
        // WB_SPEC_230 第 5.1 节：深色输入框与浅色同 token、同圆角、同描边宽度。
        // WB_SPEC_231 第 11 节：深色同样换 CleanGapOutlineInputBorder，
        // 衬底两色取深色方案（留空段不画线，字仍可读）。
        inputDecorationTheme: _gapInputDecorationTheme(darkColorScheme),
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
        // 课表工具（2.0.2：课程搜索 / 空闲时段 / 考试倒计时 / 导出课表图片 / 日期备注）
        '/course-tools': (context) => const CourseToolsPage(),
        // 权限（通知 / 精确闹钟 / 电池优化：状态与补开入口，用到时才申请）
        '/permissions': (context) => const PermissionPage(),
        // 数据管理页（1.2.4：占用/备份快捷入口/恢复出厂）
        '/data-manage': (context) => const DataManagePage(),
        // 设置分类子页（2.0.5：设置首页 QQ 式分级，见 settings_sections.dart）
        '/settings-semester': (context) => const SemesterSettingsPage(),
        '/settings-appearance': (context) => const AppearanceSettingsPage(),
        '/settings-reminders': (context) => const RemindersSettingsPage(),
        '/settings-data': (context) => const DataSettingsPage(),
        '/settings-permissions': (context) => const PermissionsSettingsPage(),
        '/settings-widget': (context) => const WidgetSettingsPage(),
        // 设置主页（2.1.0 WB_SPEC_212 第 2 节）：原底栏右键改由右上角「更多」菜单进入
        '/settings': (context) => const SettingsPage(),
        // 菜单管理（2.1.0 WB_SPEC_212 第 4 节）：右上角菜单显隐 + 排序
        '/menu-manage': (context) => const MenuManagePage(),
      },
      // 未知路由兜底（2.1.3 WB_SPEC_214 第 2 节）：路由表里已没有任何 AI 页，
      // 旧深链、旧书签、系统恢复出来的历史栈里的老路由名都会走到这里。
      // 静默回首页：不抛 FlutterError（那会红屏）、不弹提示、不留空页。
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => const _RootGate(),
      ),
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

/// 主框架（2.1.0 WB_SPEC_212 第 1 节：去底栏，主页变单页；
/// 2.1.2 WB_SPEC_213 第 2 节：底部栏以「悬浮胶囊」形态回归，主页升级为单层壳）
///
/// 2.0.0 起这里是底栏三键 + IndexedStack 三页签；2.1.0 起删掉底栏与三页签结构，
/// 根页面只剩周课表主页 WeekViewPage；2.1.3 起底部胶囊恒为两键［课表｜设置］
/// （WB_SPEC_214：解锁展开与第三个键随对应功能一并删除）。
///
/// 2.1.2 起按 `UiSettings.showBottomBar`（默认开）二选一：
/// - 开：单层壳结构，壳内承载［课表、设置根页］两个一级视图，原地淡入淡出切换，
///   底部栏恒两键；设置根页作为一级视图、无返回箭头。
/// - 关：恢复为 2.1.1 单页结构，设置从右上角菜单 Push 进入（300ms 右滑、有返回箭头）。
///
/// 2.1.5（WB_SPEC_216 第 1 节）：开栏时底部栏是图标+文字标签栏——整宽贴住
/// 屏幕底边、顶部一条细分割线，两格等宽（图标在上、文字在下），选中态图标与
/// 文字同为琥珀黄；贴底不悬浮（无悬浮间距、无悬浮阴影）。
///
/// 2.1.6（WB_SPEC_217）：
/// - 第 1 节：标签栏加 50% 宽滑动指示器 + 弹簧曲线 + 按压回弹，布局、文案、
///   功能一律不变；
/// - 第 2 节：壳内两个一级视图的切换改为 260ms（反向 200ms）、进入减速 /
///   退出加速、淡入 + 0.985→1.0 微缩放，消除纯淡入的重影感；防困死与系统
///   返回逻辑不动。
///
/// 2.1.7 同版本修复：胶囊形态整体删除（用户定：只要新标签栏），底部栏只有
/// 标签栏一种；毛玻璃层整体删除（`BackdropFilter` 真机整屏漫溢，整片课表
/// 蒙雾），栏体只留半透明底色。
///
/// 保留 [ConsumerStatefulWidget]：启动联动（提醒重排 / 常驻通知 / 小组件 /
/// 快捷入口 / 自动备份）需要 ref，且壳内一级视图切换要用 setState。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// 壳内当前一级视图（WB_SPEC_213 第 2 节），默认课表。
  HomeShellTab _tab = HomeShellTab.schedule;

  @override
  void initState() {
    super.initState();
    // 1.3.2 启动提速：启动联动全部挪到首帧之后。
    // 提醒重排 / 常驻通知 / 小组件都要读库或走平台通道，快捷入口注册也是通道调用，
    // 放在 initState 里会和课表首帧渲染抢 isolate；首帧后并发触发，课表先出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runStartupTasks());
    });
  }

  /// 首帧后的启动联动：四项互不依赖并发跑完，常驻通知顺序殿后（见下方 C5 注）。
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
      ]);
      // 今日课程常驻通知必须排在 rescheduleAll 之后：rescheduleAll 的 cancelAll
      // 会连常驻通知（id 1001）一起清掉，并发执行时谁后到谁说了算，常驻通知会被误清
      // （复审 C5）。顺序执行保证它是在 cancelAll 之后重建的。
      // 2.2.0（WB_SPEC_229）起 refresh() 还负责重排「单闹钟接力」的链：
      // 前台 Service 已退役，App 被杀后由精确闹钟唤醒原生 Receiver 自己翻页，
      // 所以这里一次 refresh 就同时完成了「重建通知」与「把链接上」。
      await OngoingNoticeService.instance.refresh();
    } catch (e) {
      debugPrint('启动联动刷新失败：$e');
    }
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

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();

    // 防困死（WB_SPEC_213 追加第 3 条）：在外观页关掉底部栏的瞬间，把壳内
    // Tab 静默重置回课表（不 setState、不播淡入淡出动画）。此刻 build 已经
    // 返回裸 WeekViewPage、壳整体卸载，趁外观页还在顶层遮挡时静默完成；
    // 从外观页返回后落在课表视图。下一次再开底部栏时 `_tab` 已是课表。
    ref.listen(uiSettingsProvider, (prev, next) {
      final wasOn = prev?.value?.showBottomBar ?? true;
      final isOn = next.value?.showBottomBar ?? true;
      if (wasOn && !isOn) {
        _tab = HomeShellTab.schedule;
      }
    });

    if (!ui.showBottomBar) {
      // 2.1.1 结构：关底栏时恢复为单页，设置从右上角菜单 Push 进入（300ms 右滑）
      return const WeekViewPage();
    }

    // 2.1.2（WB_SPEC_213 第 2 节）：开底栏时升级为单层壳结构
    // 2.1.5（WB_SPEC_216 第 1 节）：默认形态为图标+文字标签栏，通栏形态已删除
    return PopScope(
      // 壳内非课表视图时，系统返回先切回课表，再按一次才退出 App
      canPop: _tab == HomeShellTab.schedule,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != HomeShellTab.schedule) {
          setState(() => _tab = HomeShellTab.schedule);
        }
      },
      child: _buildShell(ui.shellTransitionStyle),
    );
  }

  /// 壳层主体：只有新标签栏一种形态。
  ///
  /// 标签栏是悬浮 overlay——[Stack] 里栏浮在视图之上，网格底部按栏高留白
  /// （见 [bottomBarGridBottomInset]），最后一节不会被栏压住。
  ///
  /// 视图区切换动效三选一（2026-11-05 用户定：三种都做，做成开关让用户自己选，
  /// 默认柔和）：见 [ShellTransitionView]——旧 AnimatedSwitcher（260ms
  /// 淡入＋0.985 微缩放）已删除，它每次切换都同步销毁重建整棵 Widget 树
  /// （设置页首次 build/layout 掉帧），且两页交叉淡入淡出、中段各占 50%
  /// 透明度叠出重影（Argon 诊断）。
  Widget _buildShell(ShellTransitionStyle style) {
    final view = ShellTransitionView(currentTab: _tab, style: style);

    return Stack(
      children: [
        Positioned.fill(child: view),
        // 顶层：标签栏（恒两键［课表｜设置］），悬浮贴底
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: HomeTabBar(
            activeTab: _tab,
            // WB_SPEC_223：跳转条展开时点底部栏只收起，不切页／不回本周。
            // WeekViewPage  watch 着这个 provider，置 false 后它自己收起。
            onSelectTab: (tab) {
              if (ref.read(weekJumperOpenProvider)) {
                ref.read(weekJumperOpenProvider.notifier).setOpen(false);
                return;
              }
              setState(() => _tab = tab);
            },
            onTapSchedule: () {
              if (ref.read(weekJumperOpenProvider)) {
                ref.read(weekJumperOpenProvider.notifier).setOpen(false);
                return;
              }
              _onTapScheduleKey();
            },
          ),
        ),
      ],
    );
  }

  /// 课表键双职责（第 2 节）：非课表视图点击仅切回课表（保持原周次）；
  /// 已在课表视图点击触发「回到本周」（displayWeekProvider 驱动周视图跳页）。
  void _onTapScheduleKey() {
    if (_tab != HomeShellTab.schedule) {
      setState(() => _tab = HomeShellTab.schedule);
    } else {
      ref.read(displayWeekProvider.notifier).goToday();
    }
  }
}
