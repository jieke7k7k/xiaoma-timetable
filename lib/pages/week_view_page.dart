import 'dart:async';

import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/course.dart';
import '../models/course_override.dart';
import '../models/time_slot.dart';
import '../models/ui_settings.dart';
import '../providers/providers.dart';
import '../services/channel_service.dart';
import '../services/ongoing_notice_service.dart';
import '../utils/color_schemes.dart';
import '../utils/deliberate_page_physics.dart';
import '../utils/next_class.dart';
import '../utils/override_effect.dart';
import '../utils/slot_layout.dart';
import '../utils/week_calc.dart';
import '../ui/app_styles.dart';
import '../ui/grid_metrics.dart';
import '../widgets/course_card.dart';
import '../widgets/course_detail_sheet.dart';
import '../widgets/empty_state.dart';

/// 周视图主页
///
/// 经典 7 列 × N 节次网格（周末无课时自动收起为 5 列）：
/// - 顶部栏：第 X 周 · 单/双周、当前月份、回到本周；点击展开周次快速跳转条
/// - 表头：月份列 + 周一~周日（几月几日，今天高亮）
/// - 网格：左侧节次号与上下课时间，右侧日期列，跨节次课程合并为圆角卡片
/// - 午休 / 晚间分隔带：位置由「作息分段设置」驱动（默认第 5 / 9 节后），各一条 20px 通栏分隔带（高度守恒）
/// - 格子三态布局（见 slot_layout.dart）：本周课优先，非本周课置灰且不遮挡本周课；
///   同格多课收敛为一张卡片 + 「+N」角标，点击先选课程再进详情
/// - PageView 左右滑动切换周次；严格按 weeksJson 与单双周过滤
class WeekViewPage extends ConsumerStatefulWidget {
  const WeekViewPage({super.key});

  @override
  ConsumerState<WeekViewPage> createState() => _WeekViewPageState();
}

/// 第 [section] 节卡片顶部的纵向偏移（含之前分隔带的累计高度）
double yOffsetTop(int section, double rowHeight, int bandCountBefore) =>
    (section - 1) * rowHeight + bandCountBefore * kBandHeight;

/// 第 [section] 节之前有几条分隔带
int bandsBefore(int section, List<GridBand> activeBands) {
  var n = 0;
  for (final b in activeBands) {
    if (section > b.after) n++;
  }
  return n;
}

class _WeekViewPageState extends ConsumerState<WeekViewPage> {
  PageController? _pageController;
  bool _showJumper = false;

  /// 编辑模式：开启后才能点空白新建课程、长按课程编辑/删除；
  /// 关闭时点空白无反应、点课程只看详情，防止误触（用户真机反馈）
  bool _editMode = false;

  /// 网格纵向滚动锁：长按空白格拖动扩展节次期间锁定纵向滚动，避免手势打架
  bool _gridScrollLocked = false;

  /// 状态条分钟级刷新计时器（下一节课倒计时/上下课切换靠它推进）
  Timer? _focusTimer;

  /// 上次下发常驻通知时的焦点签名；焦点（当前课/下一节）变了才刷新通知
  String _focusSig = '';

  /// 时间轴宽度
  static const double _timeAxisWidth = kTimeAxisWidth;

  // 公开通道（1.2.4）：静默检查更新 + 公告横幅/重要公告弹窗
  ChannelInfo? _channel;
  Set<String> _seenAnn = {};
  Set<String> _dismissedAnn = {};
  int _currentCode = 0;
  int _dismissedCode = 0;
  bool _importantShown = false;

  Future<void> _loadChannel() async {
    // 五项读取互不依赖（1.3.2 启动提速）：一次性发起再逐个收，
    // 原本串行 await 五次（每次都要走一遍 path_provider 通道读状态文件）。
    final cachedFuture = ChannelService.cached();
    final seenFuture = ChannelService.seenIds();
    final dismissedFuture = ChannelService.dismissedIds();
    final dismissedCodeFuture = ChannelService.dismissedVersionCode();
    final pkgFuture = PackageInfo.fromPlatform();
    final cached = await cachedFuture;
    final seen = await seenFuture;
    final dismissed = await dismissedFuture;
    final dismissedCode = await dismissedCodeFuture;
    final pkg = await pkgFuture;
    if (!mounted) return;
    setState(() {
      _channel = cached;
      _seenAnn = seen;
      _dismissedAnn = dismissed;
      _dismissedCode = dismissedCode;
      _currentCode = int.tryParse(pkg.buildNumber) ?? 0;
    });
    _maybeShowImportant();
    if (await ChannelService.shouldSilentCheck()) {
      final fresh = await ChannelService.fetch();
      if (!mounted || fresh == null) return;
      setState(() => _channel = fresh);
      _maybeShowImportant();
    }
  }

  /// 重要公告：未读的第一条弹窗一次，看过不再打扰
  void _maybeShowImportant() {
    if (_importantShown || _channel == null) return;
    final pending = _channel!.announcements
        .where((a) => a.isImportant && !_seenAnn.contains(a.id))
        .toList();
    if (pending.isEmpty) return;
    _importantShown = true;
    final a = pending.first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(a.title),
          content: Text(a.body),
          actions: [
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await ChannelService.markSeen([a.id]);
                if (mounted) setState(() => _seenAnn.add(a.id));
              },
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    });
  }

  /// 横幅展示的公告：最新一条未读、未关过、非重要（重要的走弹窗）
  Announcement? get _bannerAnnouncement {
    final ch = _channel;
    if (ch == null) return null;
    for (final a in ch.announcements) {
      if (!a.isImportant &&
          !_seenAnn.contains(a.id) &&
          !_dismissedAnn.contains(a.id)) {
        return a;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _focusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    final todayWeek = ref.read(todayWeekProvider);
    final totalWeeks = ref.read(currentSemesterProvider).value?.totalWeeks ?? 0;
    // 页码按钳制后的周次算：今天超出总周数时（学期已结束）落在最后一周，
    // 否则 PageController 的 initialPage 越界直接崩
    final page = WeekCalc.clampForPage(todayWeek, totalWeeks) - 1;
    _pageController = PageController(initialPage: page < 0 ? 0 : page);
    // 1.3.2 启动提速：公告/更新检查要读本地状态文件 + 取包名（平台通道），
    // 挪到首帧之后再跑，别和课表首帧抢时间；横幅晚一帧出现对体验无影响。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadChannel());
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _jumpToWeek(int week) {
    final total = ref.read(currentSemesterProvider).value?.totalWeeks ?? 20;
    if (week < 1 || week > total) return;
    ref.read(displayWeekProvider.notifier).setWeek(week);
    _pageController?.animateToPage(
      week - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToday() {
    final todayWeek = ref.read(todayWeekProvider);
    if (todayWeek <= 0) return;
    // 今天超出总周数时钳到最后一周，避免「回到本周」点了没反应
    final totalWeeks = ref.read(currentSemesterProvider).value?.totalWeeks ?? 0;
    _jumpToWeek(WeekCalc.clampForPage(todayWeek, totalWeeks));
  }

  /// 新建方式选择：手动新建课程 / 导入课表（ICS / 图片 OCR / PDF）
  ///
  /// 2.0.0：原先是底栏中间的「新建」页签，底栏改成「AI / 主页 / 设置」三键后
  /// 挪到主页右上角（+ 按钮），内容与原来逐字一致。
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

  /// 表头某天有考试时点开看详情（考试红点配套）
  void _showDayExams(
    BuildContext context,
    DateTime date,
    List<Course> dayCourses,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${date.month}月${date.day}日的考试'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in dayCourses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(c.colorValue),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('《${c.name}》')),
                    Text(
                      _examTimeText(c.examDate!),
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pushNamed(context, '/exam-countdown').then((_) {
                  if (ctx.mounted) Navigator.pop(ctx);
                }),
            child: const Text('全部考试倒计时'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  /// 考试时间文本：只设了日期（0 点）时不显示时间，否则带 HH:mm
  String _examTimeText(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    if (d.hour == 0 && d.minute == 0) return '全天';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(currentSemesterProvider).value;
    if (semester == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final displayWeek = ref.watch(displayWeekProvider);
    final todayWeek = ref.watch(todayWeekProvider);
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    final courses = ref.watch(coursesProvider).value ?? [];
    final overrides = ref.watch(courseOverridesProvider).value ?? [];
    final showOther = ref.watch(showOtherWeeksProvider);
    final autoCollapse = ref.watch(autoCollapseWeekendProvider);
    // 周末自适应收起也要看调课结果：某节课被单次调到周六/周日时不能收起
    final displayWeekCourses = effectiveCoursesForWeek(
      courses: courses,
      overrides: overrides,
      week: displayWeek,
    );
    final displayDays = computeDisplayDays(
      displayWeekCourses,
      displayWeek,
      showOther,
      autoCollapse,
    );
    final dates = WeekCalc.weekDatesOf(
      semester.startDateParsed,
      displayWeek,
    );
    // 本周考试标记（1.2.0）：按日期聚合设置了考试日期的课程，表头打红点
    final examsByDay = <String, List<Course>>{};
    for (final c in courses) {
      if (c.examDate == null) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(c.examDate!);
      examsByDay.putIfAbsent('${d.year}-${d.month}-${d.day}', () => []).add(c);
    }
    // 顶部状态条焦点（与常驻通知共用同一套计算）；焦点变化时顺手刷新常驻通知，
    // 保证通知栏里的「下一节」跟主页状态条同步切换
    final now = DateTime.now();
    final focus = computeClassFocus(
      now: now,
      semester: semester,
      courses: courses,
      timeSlots: ref.watch(timeSlotsProvider).value ?? const [],
      overrides: overrides,
    );
    final focusSig =
        '${focus.current?.course.id}@${focus.current?.start}|${focus.next?.course.id}@${focus.next?.start}';
    if (focusSig != _focusSig) {
      _focusSig = focusSig;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => OngoingNoticeService.instance.refresh(),
      );
    }

    // 左上角单双周小标识：开关在「界面设置 → 左上角单双周小标识」（默认开）。
    // 用的是「今天是第几周」而不是正在浏览的周次，翻到别的周时它仍指当前周
    final parityText = ui.showWeekParity
        ? WeekCalc.parityLabel(todayWeek, totalWeeks: semester.totalWeeks)
        : null;

    // 学期切换联动：semester 变化时把 PageController 跳到新学期的「本周」，
    // 并 clamp 防止旧学期残留的页码超出新学期总周数导致越界
    ref.listen(currentSemesterProvider, (prev, next) {
      final prevId = prev?.value?.id;
      final nextSemester = next.value;
      if (prevId == null || nextSemester == null || prevId == nextSemester.id) {
        return;
      }
      final w = ref.read(todayWeekProvider);
      final maxPage = nextSemester.totalWeeks - 1;
      final page = (w > 0 ? w - 1 : 0).clamp(0, maxPage < 0 ? 0 : maxPage);
      _pageController?.jumpToPage(page);
    });

    // 外部改周联动（1.2.0）：课程搜索 / 空闲时段页跳周时只改 displayWeekProvider，
    // 这里把 PageView 同步过去；用户自己滑动时页码已一致，监听自动空转不干预
    ref.listen(displayWeekProvider, (prev, next) {
      final pc = _pageController;
      if (pc != null && pc.hasClients && (pc.page?.round() ?? -1) != next - 1) {
        pc.jumpToPage(next - 1);
      }
    });

    return Scaffold(
      appBar: AppBar(
        // 恒色（1.2.2）：默认 AppBar 在内容滚动/回弹时会自动切换表面着色，
        // 下拉瞬间顶部发白（用户实测对比图）。钉死背景色并关掉自动着色。
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // 周数标题靠左上角（用户要求）；主页是根页面，显式关掉系统自动
        // 生成的返回箭头（首次使用经导入流程进入时曾出现无用返回按钮）
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: InkWell(
          onTap: () => setState(() => _showJumper = !_showJumper),
          borderRadius: BorderRadius.circular(AppRadii.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ui.showParityLabel
                          ? WeekCalc.weekTitle(displayWeek)
                          : '第 $displayWeek 周',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${dates.first.month}月${dates.first.day}日 - '
                      '${dates.last.month}月${dates.last.day}日',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                // 当前周的单/双周小标识（2.0.0）：口径是 WeekCalc 的当前周，
                // 未开学（week ≤ 0）或学期已结束时 parityLabel 返回 null，整个不显示
                if (parityText != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                    ),
                    child: Text(
                      parityText,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
                Icon(_showJumper ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        actions: [
          // 编辑模式开关（右上角）：防误触——不开时点空白不新建、长按不出菜单
          if (_editMode)
            TextButton.icon(
              onPressed: () => setState(() => _editMode = false),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            )
          else
            IconButton(
              tooltip: '编辑模式（开启后可添加/修改课程）',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() => _editMode = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('编辑模式已开启：点击空白处新建课程，长按课程可编辑'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          // 「新建」入口（2.0.0）：底栏三键改版后，原来的「新建」页签挪到这里。
          // 点开就是原来那套新建方式选择（手动填 / 导入课表），与编辑模式无关——
          // 这两条都是完整的表单页流程，不需要先开编辑模式。
          IconButton(
            icon: const Icon(Icons.add_outlined),
            onPressed: _showCreateSheet,
          ),
          // 「更多」菜单（1.2.0）：顶栏只留铅笔（状态按钮）在外，
          // 其余入口收进菜单——学期管理首次上主页，另含搜索/空闲/导出图等
          PopupMenuButton<String>(
            tooltip: '更多',
            icon: const Icon(Icons.more_vert),
            onSelected: (route) => Navigator.pushNamed(context, route),
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: '/course-search',
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text('课程搜索'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/free-time',
                child: ListTile(
                  leading: Icon(Icons.free_breakfast_outlined),
                  title: Text('空闲时段'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/share-image',
                child: ListTile(
                  leading: Icon(Icons.image_outlined),
                  title: Text('导出课表图片'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/semester-manage',
                child: ListTile(
                  leading: Icon(Icons.school_outlined),
                  title: Text('学期管理'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/exam-countdown',
                child: ListTile(
                  leading: Icon(Icons.event_note_outlined),
                  title: Text('考试倒计时'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: '/import',
                child: ListTile(
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('导入课表'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (displayWeek != todayWeek)
            TextButton.icon(
              onPressed: _goToday,
              icon: const Icon(Icons.event_available, size: 18),
              label: const Text('回到本周'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 当前/下一节课状态条（1.2.0）：点一下回到本周
          _ClassFocusBar(focus: focus, now: now, onTap: _goToday),
          // 更新提示横幅（1.2.4）：有新版且这个版本没被关过
          if (_channel != null &&
              _currentCode > 0 &&
              hasNewerVersion(_channel!, _currentCode) &&
              _dismissedCode < _channel!.latest!.versionCode)
            _ChannelBanner(
              icon: Icons.system_update_outlined,
              text: '有新版本 ${_channel!.latest!.versionName} 可用',
              actionLabel: '去看看',
              onAction: () => Navigator.pushNamed(context, '/about'),
              onClose: () async {
                final code = _channel!.latest!.versionCode;
                await ChannelService.dismissVersion(code);
                if (mounted) setState(() => _dismissedCode = code);
              },
            ),
          // 公告横幅（1.2.4）：最新一条未读普通公告
          if (_bannerAnnouncement != null)
            _ChannelBanner(
              icon: Icons.campaign_outlined,
              text: '公告：${_bannerAnnouncement!.title}',
              actionLabel: '查看',
              onAction: () async {
                await Navigator.pushNamed(context, '/announcements');
                final seen = await ChannelService.seenIds();
                if (mounted) setState(() => _seenAnn = seen);
              },
              onClose: () async {
                final id = _bannerAnnouncement!.id;
                await ChannelService.dismiss(id);
                if (mounted) setState(() => _dismissedAnn.add(id));
              },
            ),
          // 周次快速跳转条
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _showJumper
                ? _WeekJumper(
                    totalWeeks: semester.totalWeeks,
                    currentWeek: displayWeek,
                    todayWeek: todayWeek,
                    onTap: (w) {
                      _jumpToWeek(w);
                      setState(() => _showJumper = false);
                    },
                  )
                : const SizedBox.shrink(),
          ),
          // 周日收尾提醒：今天是周日且正看着本周时，提醒本周已结束，
          // 避免把周日误看成下周的课；可一键跳到下周
          if (displayWeek == todayWeek &&
              DateTime.now().weekday == DateTime.sunday)
            _SundayEndBanner(
              onNextWeek: displayWeek < semester.totalWeeks
                  ? () => _jumpToWeek(displayWeek + 1)
                  : null,
            ),
          // 表头（列数由 displayDays 驱动）
          _HeaderRow(
            dates: dates,
            displayDays: displayDays,
            timeAxisWidth: _timeAxisWidth,
            today: DateTime.now(),
            examsByDay: examsByDay,
            onDayTap: (date, dayCourses) =>
                _showDayExams(context, date, dayCourses),
          ),
          const Divider(height: 1),
          // 网格区
          Expanded(
            child: _GridArea(
              pageController: _pageController!,
              displayWeek: displayWeek,
              displayDays: displayDays,
              timeAxisWidth: _timeAxisWidth,
              editMode: _editMode,
              scrollLocked: _gridScrollLocked,
              onScrollLockChanged: (locked) =>
                  setState(() => _gridScrollLocked = locked),
              onWeekChanged: (page) =>
                  ref.read(displayWeekProvider.notifier).setWeek(page + 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通道横幅（1.2.4）：更新提示与公告共用的细横幅（图标+文案+动作+关闭）
class _ChannelBanner extends StatelessWidget {
  const _ChannelBanner({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    required this.onClose,
  });

  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: scheme.onTertiaryContainer),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: '关闭',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 周日收尾提醒横幅：今天是周日时提示本周已结束，防止误看成下周课表
class _SundayEndBanner extends StatelessWidget {
  const _SundayEndBanner({this.onNextWeek});

  /// 跳到下周的回调；已是最后一周时为 null，不显示按钮
  final VoidCallback? onNextWeek;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.weekend_outlined,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '今天是周日，本周已结束',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          if (onNextWeek != null)
            TextButton(onPressed: onNextWeek, child: const Text('看下周')),
        ],
      ),
    );
  }
}

/// 表头行：月份列 + 日期列（列数由 displayDays 驱动）
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.dates,
    required this.displayDays,
    required this.timeAxisWidth,
    required this.today,
    required this.examsByDay,
    required this.onDayTap,
  });

  final List<DateTime> dates;
  final List<int> displayDays;
  final double timeAxisWidth;
  final DateTime today;

  /// 考试标记：'年-月-日' → 当天有考试的课程（1.2.0）
  final Map<String, List<Course>> examsByDay;

  /// 点某天表头（当天有考试时才触发）
  final void Function(DateTime date, List<Course> courses) onDayTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: kGridHeaderHeight,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 月份列
          SizedBox(
            width: timeAxisWidth,
            child: Center(
              child: Text(
                '${dates.first.month}月',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ),
          ),
          // 日期列
          Expanded(
            child: Row(
              children: [
                for (final d in displayDays)
                  Expanded(
                    child: _DayCell(
                      date: dates[d - 1],
                      isToday: _isSameDay(dates[d - 1], today),
                      examCourses:
                          examsByDay['${dates[d - 1].year}-${dates[d - 1].month}-${dates[d - 1].day}'],
                      onTap: (dayCourses) => onDayTap(dates[d - 1], dayCourses),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    this.examCourses,
    this.onTap,
  });

  final DateTime date;
  final bool isToday;

  /// 当天的考试课程（为空/ null 表示当天没考试，不打红点）
  final List<Course>? examCourses;

  /// 点击回调（仅当天有考试时传入有意义）
  final void Function(List<Course> courses)? onTap;

  static const _weekNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasExam = examCourses != null && examCourses!.isNotEmpty;
    final cell = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          // 表头只显示一~日，不带「周」字（用户要求）
          _weekNames[date.weekday - 1],
          style: TextStyle(
            fontSize: 10,
            color: isToday ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? colorScheme.primary : Colors.transparent,
                // 今天日期小圆点是正圆（半径=宽高一半），不属于 AppRadii 圆角体系
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: isToday
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // 考试红点（1.2.0）：贴在日期圆右上角，不占表头高度
            if (hasExam)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colorScheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surface, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    if (!hasExam || onTap == null) return cell;
    return InkWell(onTap: () => onTap!(examCourses!), child: cell);
  }
}

/// 周次快速跳转条
class _WeekJumper extends StatelessWidget {
  const _WeekJumper({
    required this.totalWeeks,
    required this.currentWeek,
    required this.todayWeek,
    required this.onTap,
  });

  final int totalWeeks;
  final int currentWeek;
  final int todayWeek;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var w = 1; w <= totalWeeks; w++)
            GestureDetector(
              onTap: () => onTap(w),
              child: Container(
                width: 38,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: w == currentWeek
                      ? colorScheme.primary
                      : (w == todayWeek
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
                child: Text(
                  '$w',
                  style: TextStyle(
                    fontSize: 12,
                    color: w == currentWeek
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 网格区：左侧时间轴 + PageView 承载每周网格
///
/// 1.1.1 布局变更：行高不再按屏均分，改用「界面设置」的固定格子高度（px）；
/// 总高超过可视区时整块（时间轴 + 网格）可纵向滚动，两者共用同一滚动体
/// 保证分隔带两侧严格对齐。高亮拖动建课期间经 [scrollLocked] 锁住纵向滚动。
/// 左右滑切周降灵敏（两层）：手势触发距离（touchSlop）30  管「拖动何时开始」；
/// 翻页结算由 DeliberatePagePhysics 管「松手后翻不翻页」——框架默认物理在
/// 松手速度超过约 7px/s 时就把目标页偏半页，是 1.1.1 只调 touchSlop 没治好的根因。
class _GridArea extends ConsumerWidget {
  const _GridArea({
    required this.pageController,
    required this.displayWeek,
    required this.displayDays,
    required this.timeAxisWidth,
    required this.onWeekChanged,
    required this.editMode,
    required this.scrollLocked,
    required this.onScrollLockChanged,
  });

  final PageController pageController;
  final int displayWeek;
  final List<int> displayDays;
  final double timeAxisWidth;
  final ValueChanged<int> onWeekChanged;
  final bool editMode;
  final bool scrollLocked;
  final ValueChanged<bool> onScrollLockChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semester = ref.watch(currentSemesterProvider).value;
    final slots = ref.watch(timeSlotsProvider).value ?? [];
    if (semester == null || slots.isEmpty) return const SizedBox.shrink();
    final sectionCount = slots.length;
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    // 分隔带位置由「作息分段设置」驱动；provider 未加载完成时回退默认值（午休 5 / 晚间 9）
    // 今天列高亮：正在看的就是本周且今天在显示列里时才算（开关 1.2.6）
    final nowDate = DateTime.now();
    final thisWeekNo = WeekCalc.currentWeek(
      semester.startDateParsed,
      nowDate,
    );
    final highlightDay =
        (ui.highlightTodayColumn &&
            displayWeek == thisWeekNo &&
            displayDays.contains(nowDate.weekday))
        ? nowDate.weekday
        : null;
    final seg = ref.watch(segmentSettingsProvider).value;
    final lunchAfter = seg?.lunchAfterSection ?? 5;
    final dinnerAfter = seg?.dinnerAfterSection ?? 9;
    // 分隔带的时间段文本：第 after 节下课 → 下一节上课（如 12:00–14:00）
    String bandInterval(int after) {
      TimeSlot? cur, nxt;
      for (final t in slots) {
        if (t.section == after) cur = t;
        if (t.section == after + 1) nxt = t;
      }
      if (cur == null || nxt == null) return '';
      return '${cur.endTime}–${nxt.startTime}';
    }

    // 生效的分隔带：只保留落在节次范围内的（after < sectionCount）
    final activeBands = [
      (after: lunchAfter, label: '午休', interval: bandInterval(lunchAfter)),
      (after: dinnerAfter, label: '晚间', interval: bandInterval(dinnerAfter)),
    ].where((b) => b.after < sectionCount).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = displayDays.length;
        final cellWidth =
            (constraints.maxWidth - timeAxisWidth - 1) / columnCount;
        // 行高：默认用界面设置的固定格子高度；开启「自适应一屏」（B1）时
        // 按可用高度均分（分隔带高度固定扣除），整表恰好一屏
        var rowHeight = ui.cellHeight;
        if (ui.autoFitHeight && constraints.maxHeight.isFinite) {
          final fit =
              (constraints.maxHeight - activeBands.length * kBandHeight) /
              sectionCount;
          rowHeight = fit < 24 ? 24 : fit;
        }
        final totalHeight =
            sectionCount * rowHeight + activeBands.length * kBandHeight;
        // 内容不足一屏时按可视高撑满（格子保持设定高度，空白留在底部）
        final contentHeight = totalHeight < constraints.maxHeight
            ? constraints.maxHeight
            : totalHeight;
        return MediaQuery(
          // 降灵敏：子树手势触发距离 18 → 30，静置手指不再拖动课表
          data: MediaQuery.of(context).copyWith(
            gestureSettings: const DeviceGestureSettings(touchSlop: 30),
          ),
          child: SingleChildScrollView(
            physics: scrollLocked
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: SizedBox(
              height: contentHeight,
              child: Stack(
                children: [
                  // 最下层：单条通栏分隔带（1.2.2 通栏化，1.2.3 沉底——
                  // 跨带长卡要完整压住带子，见 A2）
                  for (final b in activeBands)
                    Positioned(
                      top:
                          b.after * rowHeight +
                          activeBands.where((o) => o.after < b.after).length *
                              kBandHeight,
                      left: 0,
                      right: 0,
                      height: kBandHeight,
                      child: IgnorePointer(
                        child: _FullBand(band: b, axisWidth: timeAxisWidth),
                      ),
                    ),
                  // 中层：全宽横线（1.2.3 统一绘制，见 _FullWidthLinesPainter；
                  // 1.2.5 起受「显示网格线」开关控制，关掉后横线一起消失）
                  if (ui.showGridLines)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: totalHeight,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FullWidthLinesPainter(
                            rowHeight: rowHeight,
                            sectionCount: sectionCount,
                            activeBands: activeBands,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  // 最上层：时间轴 + 课表
                  Row(
                    children: [
                      // 左侧时间轴（与网格共用行高 + 分隔带占位，随网格一起滚动）
                      _TimeAxis(
                        slots: slots,
                        width: timeAxisWidth,
                        rowHeight: rowHeight,
                        activeBands: activeBands,
                        showTime: ui.axisShowTime,
                      ),
                      const VerticalDivider(width: 1),
                      // 右侧周网格（可左右滑动）
                      Expanded(
                        child: PageView.builder(
                          controller: pageController,
                          // 翻页判定（1.2.1）：默认物理在松手速度 >约7px/s 时就翻页，
                          // 改用明确滑动才翻周的自定义物理（见 deliberate_page_physics）
                          physics: const DeliberatePagePhysics(),
                          onPageChanged: (page) {
                            // 切周成功的轻触感反馈
                            HapticFeedback.lightImpact();
                            onWeekChanged(page);
                          },
                          itemCount: semester.totalWeeks,
                          itemBuilder: (context, index) {
                            final week = index + 1;
                            return _WeekGrid(
                              key: ValueKey(week),
                              week: week,
                              sectionCount: sectionCount,
                              displayDays: displayDays,
                              cellWidth: cellWidth,
                              rowHeight: rowHeight,
                              activeBands: activeBands,
                              editMode: editMode,
                              onScrollLockChanged: onScrollLockChanged,
                              highlightDay: week == thisWeekNo
                                  ? highlightDay
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 单条通栏分隔带（1.2.2）：左侧时间轴段写名称，右侧居中显示名称 + 时间段，
/// 整行同一个容器绘制，与网格/时间轴之间不存在接缝。
class _FullBand extends StatelessWidget {
  const _FullBand({required this.band, required this.axisWidth});

  final GridBand band;
  final double axisWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final divider = scheme.outlineVariant.withValues(alpha: 0.6);
    return Container(
      height: kBandHeight,
      color: bg,
      child: Row(
        children: [
          SizedBox(
            width: axisWidth,
            child: Center(
              child: Text(
                band.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: scheme.outline.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
          Container(width: 1, color: divider),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    band.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.outline.withValues(alpha: 0.8),
                      letterSpacing: 4,
                    ),
                  ),
                  if (band.interval.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      band.interval,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.outline.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 左侧时间轴：节次号 + 起止时间（固定高度，与右侧网格严格对齐）
class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.slots,
    required this.width,
    required this.rowHeight,
    required this.activeBands,
    required this.showTime,
  });

  final List<dynamic> slots;
  final double width;
  final double rowHeight;
  final List<GridBand> activeBands;

  /// 是否显示每节起止时间（界面设置）；关时只显示节次数字
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        children: [
          for (var i = 0; i < slots.length; i++) ...[
            SizedBox(
              height: rowHeight,
              child: Container(
                alignment: Alignment.center,
                // 底边横线由全宽线网层统一绘制（1.2.3），单元格不再自带边框
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${slots[i].section}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (showTime) ...[
                      Text(
                        slots[i].startTime,
                        style: TextStyle(
                          fontSize: 8,
                          color: colorScheme.outline,
                        ),
                      ),
                      Text(
                        slots[i].endTime,
                        style: TextStyle(
                          fontSize: 8,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 分隔带占位（高度与网格一致即可）：带子本体由 _GridArea 顶层
            // 以「单条通栏」绘制（1.2.2）——左右各画一半会在接缝处错位
            for (final b in activeBands)
              if (b.after == slots[i].section)
                const SizedBox(height: kBandHeight),
          ],
        ],
      ),
    );
  }
}

/// 某一周的网格：N 列 × M 节次，课程按三态布局段绝对定位
///
/// 1.1.1 新增「长按空白格高亮建课」：未点铅笔时（编辑模式亦可）长按空白格，
/// 该格高亮并出现加号；保持长按上下拖动可按整节扩展/收缩节次（吸附节次、
/// 遇已有课程止步）；松手后高亮保留，再单击高亮区进新建页（预填起止节次），
/// 单击别处取消高亮。高亮状态保存在本页 State 里，PageView 滑走即自动消失。
class _WeekGrid extends ConsumerStatefulWidget {
  const _WeekGrid({
    super.key,
    required this.week,
    required this.sectionCount,
    required this.displayDays,
    required this.cellWidth,
    required this.rowHeight,
    required this.activeBands,
    required this.editMode,
    required this.onScrollLockChanged,
    required this.highlightDay,
  });

  final int week;
  final int sectionCount;
  final List<int> displayDays;
  final double cellWidth;
  final double rowHeight;
  final List<GridBand> activeBands;
  final bool editMode;
  final ValueChanged<bool> onScrollLockChanged;

  /// 今天所在的星期列（B2 整列淡色高亮）；非本周或今天不在显示列时为 null
  final int? highlightDay;

  @override
  ConsumerState<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends ConsumerState<_WeekGrid> {
  /// 长按高亮选区（星期 + 起止节次）；为空表示无高亮
  ({int day, int start, int end})? _highlight;

  /// 长按起始节次（拖动扩展以它为锚点上下伸缩）
  int? _anchorRow;

  double _topOf(int section) => yOffsetTop(
    section,
    widget.rowHeight,
    bandsBefore(section, widget.activeBands),
  );

  /// 段内第一门课在该周的单次调课记录。
  /// 草稿课（无 id）或该周本就不上课的课程（调课记录无效）返回 null。
  CourseOverride? _overrideForSlot(
    Map<int, CourseOverride> overrideMap,
    DisplaySlot slot,
    int week,
  ) {
    final first = slot.courses.first;
    if (first.id == null || !first.isActiveInWeek(week)) return null;
    return overrideMap[first.id];
  }

  /// 坐标 → （星期， 节次）；点在分隔带上或越界返回 null
  ({int day, int row})? _cellAt(
    Offset pos,
    Map<int, List<DisplaySlot>> daySlots,
  ) {
    final col = (pos.dx / widget.cellWidth).floor();
    if (col < 0 || col >= widget.displayDays.length) return null;
    for (var s = 1; s <= widget.sectionCount; s++) {
      final top = _topOf(s);
      if (pos.dy >= top && pos.dy < top + widget.rowHeight) {
        return (day: widget.displayDays[col], row: s);
      }
    }
    return null;
  }

  /// 某格是否无课（可高亮/新建）
  bool _isEmptyCell(Map<int, List<DisplaySlot>> daySlots, int day, int row) {
    for (final slot in daySlots[day] ?? const <DisplaySlot>[]) {
      if (!slot.isEmpty && row >= slot.startSection && row <= slot.endSection) {
        return false;
      }
    }
    return true;
  }

  /// 锚点所在「连续无课区间」：从锚点上下扩展，遇已有课程或边界止步
  ({int lo, int hi}) _freeRange(
    Map<int, List<DisplaySlot>> daySlots,
    int day,
    int anchor,
  ) {
    final occupied = <int>{};
    for (final slot in daySlots[day] ?? const <DisplaySlot>[]) {
      if (slot.isEmpty) continue;
      for (var s = slot.startSection; s <= slot.endSection; s++) {
        occupied.add(s);
      }
    }
    var lo = anchor;
    while (lo > 1 && !occupied.contains(lo - 1)) {
      lo--;
    }
    var hi = anchor;
    while (hi < widget.sectionCount && !occupied.contains(hi + 1)) {
      hi++;
    }
    return (lo: lo, hi: hi);
  }

  @override
  Widget build(BuildContext context) {
    final week = widget.week;
    final sectionCount = widget.sectionCount;
    final displayDays = widget.displayDays;
    final cellWidth = widget.cellWidth;
    final rowHeight = widget.rowHeight;
    final activeBands = widget.activeBands;
    final editMode = widget.editMode;
    final allCourses = ref.watch(coursesProvider).value ?? [];
    final overrides = ref.watch(courseOverridesProvider).value ?? [];
    final showOther = ref.watch(showOtherWeeksProvider);
    final ui = ref.watch(uiSettingsProvider).value ?? const UiSettings();
    // 应用单次调课（阶段五）：停课的本次不显示，调课的按新时间/教室显示。
    // 调课副本保留原 course id 与 weeks，三态布局与详情页无需感知差异。
    final effective = effectiveCoursesForWeek(
      courses: allCourses,
      overrides: overrides,
      week: week,
    );
    // 需显示的课程：本周课 +（开关开时）非本周课
    final visible = showOther
        ? effective
        : effective.where((c) => c.isActiveInWeek(week)).toList();
    // 该周每门课的单次调课记录（长按菜单 / 「调」角标用）
    final overrideMap = overridesForWeek(overrides, week);

    // 按天分组，每一天做三态布局
    final byDay = <int, List<Course>>{};
    for (final c in visible) {
      (byDay[c.dayOfWeek] ??= []).add(c);
    }
    final daySlots = <int, List<DisplaySlot>>{
      for (final d in displayDays)
        d: SlotLayout.layoutDay(
          dayCourses: byDay[d] ?? const [],
          week: week,
          showDimmed: showOther,
          maxSection: sectionCount,
        ),
    };

    // 分隔带顶部坐标

    final totalHeight =
        sectionCount * rowHeight + activeBands.length * kBandHeight;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      // 点击处理：高亮存在时优先处理高亮（单击确认/单击别处取消）；
      // 否则编辑模式下点空白格新建（自动带入星期与节次）；非编辑模式忽略，防误触
      onTapUp: (details) {
        final cell = _cellAt(details.localPosition, daySlots);
        if (cell == null) return;
        final hl = _highlight;
        if (hl != null) {
          if (cell.day == hl.day &&
              cell.row >= hl.start &&
              cell.row <= hl.end) {
            setState(() => _highlight = null);
            Navigator.pushNamed(
              context,
              '/course-edit',
              arguments: {
                'dayOfWeek': hl.day,
                'startSection': hl.start,
                'endSection': hl.end,
              },
            );
          } else {
            setState(() => _highlight = null);
          }
          return;
        }
        if (!editMode) return;
        if (!_isEmptyCell(daySlots, cell.day, cell.row)) return;
        Navigator.pushNamed(
          context,
          '/course-edit',
          arguments: {'dayOfWeek': cell.day, 'startSection': cell.row},
        );
      },
      // 长按空白格：起高亮（编辑模式开不开都行，这是防误触之外的第二入口）
      onLongPressStart: (details) {
        final cell = _cellAt(details.localPosition, daySlots);
        if (cell == null) return;
        if (!_isEmptyCell(daySlots, cell.day, cell.row)) return;
        HapticFeedback.mediumImpact();
        setState(() {
          _anchorRow = cell.row;
          _highlight = (day: cell.day, start: cell.row, end: cell.row);
        });
        widget.onScrollLockChanged(true);
      },
      // 保持长按上下拖：以锚点为中心、按整节吸附扩展/收缩，遇已有课程止步
      onLongPressMoveUpdate: (details) {
        final hl = _highlight;
        final anchor = _anchorRow;
        if (hl == null || anchor == null) return;
        final cell = _cellAt(details.localPosition, daySlots);
        if (cell == null || cell.day != hl.day) return;
        final range = _freeRange(daySlots, hl.day, anchor);
        final target = cell.row.clamp(range.lo, range.hi);
        final ns = target < anchor ? target : anchor;
        final ne = target > anchor ? target : anchor;
        if (ns != hl.start || ne != hl.end) {
          setState(() => _highlight = (day: hl.day, start: ns, end: ne));
        }
      },
      onLongPressEnd: (_) => widget.onScrollLockChanged(false),
      onLongPressCancel: () => widget.onScrollLockChanged(false),
      child: Stack(
        children: [
          // 网格背景线（界面设置可关）
          if (ui.showGridLines)
            _GridLines(
              cellWidth: cellWidth,
              rowHeight: rowHeight,
              sectionCount: sectionCount,
              columnCount: displayDays.length,
              activeBands: activeBands,
              totalHeight: totalHeight,
            ),
          // 长按高亮选区：主题色描边 + 浅填充 + 中央加号（再次单击进新建页）
          if (_highlight != null && displayDays.contains(_highlight!.day))
            Positioned(
              left: displayDays.indexOf(_highlight!.day) * cellWidth + 1.5,
              top: _topOf(_highlight!.start) + 1.5,
              width: cellWidth - 3,
              height: (_highlight!.end - _highlight!.start + 1) * rowHeight - 3,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.13),
                    border: Border.all(color: scheme.primary, width: 1.6),
                    borderRadius: BorderRadius.circular(ui.cornerRadius),
                  ),
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add, size: 16, color: scheme.onPrimary),
                    ),
                  ),
                ),
              ),
            ),
          // 课程卡片（按三态布局段绝对定位）
          for (var dayIndex = 0; dayIndex < displayDays.length; dayIndex++)
            for (final slot in daySlots[displayDays[dayIndex]]!)
              if (!slot.isEmpty)
                _PositionedCourseCard(
                  slot: slot,
                  week: week,
                  courseOverride: _overrideForSlot(overrideMap, slot, week),
                  left: dayIndex * cellWidth,
                  top: _topOf(slot.startSection),
                  width: cellWidth,
                  height: slot.span * rowHeight,
                  editMode: editMode,
                  ui: ui,
                ),
          // 空周占位提示（阶段五·视觉打磨）：网格全空时给中文引导，
          // IgnorePointer 保证点击穿透到空白格的新建手势
          if (visible.isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: EmptyState(
                  icon: Icons.wb_sunny_outlined,
                  title: '本周没有课程',
                  message: editMode
                      ? '点击空白格子新建，或从底部「新建」导入课表'
                      : '点右上角的编辑按钮开启编辑模式后，可添加课程',
                ),
              ),
            ),
          // 今天整列边框（1.2.5，替代 1.2.3 的淡色底——用户反馈太淡看不见）：
          // 给今天这一整天画一圈主题色框，压在最上层保证边框连续
          if (widget.highlightDay != null &&
              displayDays.contains(widget.highlightDay))
            Positioned(
              left: displayDays.indexOf(widget.highlightDay!) * cellWidth,
              top: 0,
              width: cellWidth,
              height: totalHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 网格线背景（横线跳过分隔带位置）
class _GridLines extends StatelessWidget {
  const _GridLines({
    required this.cellWidth,
    required this.rowHeight,
    required this.sectionCount,
    required this.columnCount,
    required this.activeBands,
    required this.totalHeight,
  });

  final double cellWidth;
  final double rowHeight;
  final int sectionCount;
  final int columnCount;
  final List<GridBand> activeBands;
  final double totalHeight;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return CustomPaint(
      size: Size(cellWidth * columnCount, totalHeight),
      painter: _GridPainter(
        cellWidth: cellWidth,
        rowHeight: rowHeight,
        sectionCount: sectionCount,
        columnCount: columnCount,
        activeBands: activeBands,
        color: color,
      ),
    );
  }
}

/// 全宽横线层（1.2.3）：整张课表的行界线（含分隔带上下边）由这一位画笔
/// 统一绘制——此前时间轴用控件边框（实心、偏粗偏深）、网格用画布描线
/// （抗锯齿、偏虚），标称同宽却看着粗细不一，接缝处像没对齐（用户反馈）。
/// 现在全表横线同宽、同色、同画法；竖线仍由 _GridPainter 绘制（同一参数）。
class _FullWidthLinesPainter extends CustomPainter {
  const _FullWidthLinesPainter({
    required this.rowHeight,
    required this.sectionCount,
    required this.activeBands,
    required this.color,
  });

  final double rowHeight;
  final int sectionCount;
  final List<GridBand> activeBands;
  final Color color;

  double _topOf(int section) =>
      yOffsetTop(section, rowHeight, bandsBefore(section, activeBands));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    // 每节底边（最后一节即整表底边）；第 after 节的底边正是分隔带顶边
    for (var r = 1; r <= sectionCount; r++) {
      final y = _topOf(r) + rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // 分隔带底边
    for (final b in activeBands) {
      final y = _topOf(b.after + 1);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_FullWidthLinesPainter old) =>
      old.rowHeight != rowHeight ||
      old.sectionCount != sectionCount ||
      old.activeBands != activeBands ||
      old.color != color;
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.cellWidth,
    required this.rowHeight,
    required this.sectionCount,
    required this.columnCount,
    required this.activeBands,
    required this.color,
  });

  final double cellWidth;
  final double rowHeight;
  final int sectionCount;
  final int columnCount;
  final List<GridBand> activeBands;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    // 横线已改由 _FullWidthLinesPainter 全宽统一绘制（1.2.3），此处只画竖线
    // 竖线（列分隔）
    for (var c = 1; c < columnCount; c++) {
      final x = c * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.cellWidth != cellWidth ||
      old.rowHeight != rowHeight ||
      old.sectionCount != sectionCount ||
      old.columnCount != columnCount ||
      old.color != color;
}

/// 绝对定位的课程卡片（一段 = 一张卡片）
///
/// multi（同格多课）时只渲染最上层一张 + 「+N」角标，
/// 点击先弹出该格子的课程选择列表，再进入所选课程详情。
/// 该课在该周有单次调整时右上角显示「调」角标（停课的课根本不会渲染到这里）。
class _PositionedCourseCard extends StatelessWidget {
  const _PositionedCourseCard({
    required this.slot,
    required this.week,
    required this.courseOverride,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.editMode,
    required this.ui,
  });

  final DisplaySlot slot;
  final int week;
  final bool editMode;

  /// 界面设置（配色方案/圆角/边框/字号/显示项），渲染卡片时用
  final UiSettings ui;

  /// 该课在该周的单次调课记录（无则 null）
  final CourseOverride? courseOverride;
  final double left;
  final double top;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    const pad = 1.5;
    final isMulti = slot.kind == SlotKind.multi;
    // 「调」角标：仅单课时段显示；multi 时让位给「+N」（调整信息在详情里仍可见）
    final isMoved = courseOverride != null && !courseOverride!.isCancellation;
    return Positioned(
      left: left + pad,
      top: top + pad,
      width: width - pad * 2,
      height: height - pad * 2,
      child: CourseCard(
        course: slot.courses.first,
        dimmed: slot.dimmed,
        badgeText: isMulti ? '+${slot.extraCount}' : (isMoved ? '调' : null),
        displayColorValue: mapCourseColor(
          slot.courses.first.colorValue,
          ui.colorScheme,
        ),
        cornerRadius: ui.cornerRadius,
        borderWidth: ui.borderWidth,
        textScale: ui.cardTextScale,
        showClassroom: ui.showClassroom,
        showTeacher: ui.showTeacher,
        showNote: ui.showNote,
        onTap: () => isMulti
            ? _showSlotPicker(context, slot)
            : CourseDetailSheet.show(context, slot.courses.first),
        // 非编辑模式长按无反应，防止误触进修改菜单
        onLongPress: () {
          if (editMode) {
            _showMenu(context, slot.courses.first, week, courseOverride);
          }
        },
      ),
    );
  }

  /// 同格多课时的迷你选择列表
  void _showSlotPicker(BuildContext context, DisplaySlot slot) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '该时段有 ${slot.courses.length} 门课程',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            for (final c in slot.courses)
              ListTile(
                leading: Container(
                  width: 14,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(c.colorValue),
                    // 色条是微小装饰元素，4px 微圆角不便归入 AppRadii 体系
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(c.name),
                subtitle: Text(
                  '第${c.startSection}'
                  '${c.endSection > c.startSection ? "-${c.endSection}" : ""}节'
                  ' · ${c.classroom?.isNotEmpty == true ? c.classroom : "未填教室"}'
                  '${slot.dimmed ? " · 非本周" : ""}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  CourseDetailSheet.show(context, c);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 长按菜单：单次调整（阶段五）+ 编辑 / 删除
  ///
  /// [courseOverride] 非空表示该课在 [week] 周已有单次调整，
  /// 菜单项变为「查看/撤销本次调整」；否则为「调整本次」。
  void _showMenu(
    BuildContext context,
    Course course,
    int week,
    CourseOverride? courseOverride,
  ) {
    // 长按弹出菜单的中触感反馈
    HapticFeedback.mediumImpact();
    // 草稿课程（id 为空）没有落库，无法建立调课关联
    final canOverride = course.id != null;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canOverride)
              ListTile(
                leading: Icon(
                  courseOverride == null
                      ? Icons.event_repeat_outlined
                      : Icons.visibility_outlined,
                ),
                title: Text(courseOverride == null ? '调整本次' : '查看/撤销本次调整'),
                subtitle: Text(
                  courseOverride == null
                      ? '只改这一节课的时间/教室，不影响其他周'
                      : describeOverride(courseOverride),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(
                    context,
                    '/course-override',
                    arguments: {'courseId': course.id, 'week': week},
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑课程'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(
                  context,
                  '/course-edit',
                  arguments: course.id,
                );
              },
            ),
            Consumer(
              builder: (ctx2, ref, _) => ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除课程'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('删除课程'),
                      content: Text('确定删除《${course.name}》吗？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(d, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) {
                    try {
                      await ref
                          .read(coursesProvider.notifier)
                          .deleteCourse(course.id!);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已删除《${course.name}》')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前 / 下一节课状态条（1.2.0）：数据与常驻通知共用 [computeClassFocus]，
/// 每 30 秒由页面计时器触发重算，倒计时与上下课切换自动推进。
/// - 上课中：「正在上课 · 摘要 ｜ 下一节 X HH:MM」（摘要自带时间段，不再重复下课时间）
/// - 课前/课间：「下一节 · 摘要 · 还有多久」（未来的课带日期标签）
/// - 无课：「近期暂无课程」
/// 点击回到本周。
class _ClassFocusBar extends StatelessWidget {
  const _ClassFocusBar({
    required this.focus,
    required this.now,
    required this.onTap,
  });

  final ClassFocus focus;
  final DateTime now;
  final VoidCallback onTap;

  String _untilText(DateTime start) {
    final diff = start.difference(now);
    if (diff.inMinutes < 1) return '马上开始';
    if (diff.inMinutes < 60) return '还有 ${diff.inMinutes} 分钟';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return m == 0 ? '还有 $h 小时' : '还有 $h 小时 $m 分钟';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cur = focus.current;
    final nxt = focus.next;
    final IconData icon;
    final String text;
    if (cur != null) {
      icon = Icons.play_circle_outline;
      var t = '正在上课 · ${cur.summary}';
      if (nxt != null) {
        final dl = dayLabel(nxt.date, now);
        t +=
            ' ｜ 下一节 ${nxt.course.name} '
            '${dl == '今天' ? '' : '$dl '}${fmtHhmm(nxt.start)}';
      }
      text = t;
    } else if (nxt != null) {
      icon = Icons.schedule_outlined;
      final dl = dayLabel(nxt.date, now);
      text = dl == '今天'
          ? '下一节 · ${nxt.summary} · ${_untilText(nxt.start)}'
          : '下一节 · $dl ${nxt.summary}';
    } else {
      icon = Icons.event_available_outlined;
      text = '近期暂无课程';
    }
    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
