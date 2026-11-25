import 'package:flutter/material.dart';

import '../models/school_entry.dart';
import '../services/school_catalog_service.dart';
import '../utils/school_sections.dart';
import '../utils/term_start_date_helper.dart';
import '../utils/web_schedule_parser.dart';
import '../widgets/app_dialog.dart';
import 'web_import_page.dart';

/// 选校器 → WebImportPage 链式回传给 ImportPage 的聚合结果
/// 携带网页抓取结果、选中的学校条目（供 §8 作息兜底）与用户确认的开学日期（供 §9 周数比对）
class SchoolWebImportResult {
  final WebScheduleResult scheduleResult;
  final SchoolEntry? school;
  final DateTime? confirmedStartDate;

  const SchoolWebImportResult({
    required this.scheduleResult,
    this.school,
    this.confirmedStartDate,
  });
}

/// 选校器页面（WB_SPEC_249 §1）
/// 路由方案 A：ImportPage → SchoolPickerPage → WebImportPage
/// 接住 WebScheduleResult 后封装为 [SchoolWebImportResult] 转发 pop 给 ImportPage
///
/// 落盘注：[semesterId] 是必填——WebImportPage 构造要求学期 id，选校器只是中转，
/// 从 _importWeb 的 target 原样传进来。
class SchoolPickerPage extends StatefulWidget {
  final int semesterId;
  final SchoolCatalogService? catalogService;

  /// 可注入的 WebImportPage 构建器（便于 widget 测试，默认打开真实 WebImportPage）
  final Widget Function(String? initialUrl)? webImportPageBuilder;

  /// 是否在进入登录页前弹出开学日期确认（§9，默认开启；测试时可关闭以聚焦选校流程）
  final bool enableStartDateConfirm;

  const SchoolPickerPage({
    super.key,
    required this.semesterId,
    this.catalogService,
    this.webImportPageBuilder,
    this.enableStartDateConfirm = true,
  });

  @override
  State<SchoolPickerPage> createState() => _SchoolPickerPageState();
}

class _SchoolPickerPageState extends State<SchoolPickerPage> {
  late final SchoolCatalogService _catalogService;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<SchoolEntry> _schools = const [];
  SchoolEntry? _lastUsedSchool;
  String _query = '';
  bool _loading = true;
  /// 当前拖动到的字母（null = 没在拖），驱动索引栏高亮与大字母气泡
  String? _dragLetter;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? SchoolCatalogService();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final schools = await _catalogService.loadSchools();
    final lastUrl = await _catalogService.loadLastUsedUrl();

    SchoolEntry? lastSchool;
    if (lastUrl != null) {
      for (final s in schools) {
        if (s.url == lastUrl) {
          lastSchool = s;
          break;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _schools = schools;
      _lastUsedSchool = lastSchool;
      _loading = false;
    });
  }

  /// 按学校名（含 note）子串过滤，保持 schools.json 原始顺序，不做拼音也不重排
  List<SchoolEntry> get _filteredSchools {
    final q = _query.trim();
    if (q.isEmpty) return _schools;
    final lower = q.toLowerCase();
    return _schools.where((s) {
      return s.name.toLowerCase().contains(lower) ||
          (s.note != null && s.note!.toLowerCase().contains(lower));
    }).toList();
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  /// 选中一所学校：记录最近使用 →（§9）确认开学日期 → 链式 push WebImportPage
  Future<void> _onSelectSchool(SchoolEntry school) async {
    await _catalogService.saveLastUsedUrl(school.url);
    if (mounted) {
      setState(() => _lastUsedSchool = school);
    }
    await _openWebImport(school: school, initialUrl: school.url);
  }

  /// 手动输入教务网址：不写最近使用 → 进 WebImportPage(initialUrl: null)
  Future<void> _onManualInput() async {
    await _openWebImport(school: null, initialUrl: null);
  }

  Future<void> _openWebImport({
    required SchoolEntry? school,
    required String? initialUrl,
  }) async {
    DateTime? confirmedStartDate;
    if (widget.enableStartDateConfirm) {
      confirmedStartDate = await _showConfirmStartDateDialog();
      // 用户在开学日期确认弹窗点了取消，停留在选校器
      if (confirmedStartDate == null) return;
    }

    if (!mounted) return;

    final page = widget.webImportPageBuilder != null
        ? widget.webImportPageBuilder!(initialUrl)
        : WebImportPage(
            semesterId: widget.semesterId,
            initialUrl: initialUrl,
          );

    final result = await Navigator.of(context).push<WebScheduleResult>(
      MaterialPageRoute(builder: (_) => page),
    );

    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(
        SchoolWebImportResult(
          scheduleResult: result,
          school: school,
          confirmedStartDate: confirmedStartDate,
        ),
      );
    }
  }

  /// §9：选学校后先确认开学日期（默认秋季取 9 月 1 日所在周周一，春季取 3 月 1 日所在周周一）
  /// WB_SPEC_256 §3.4 / §7：迁移至 AppDialog + AppDialogAction
  Future<DateTime?> _showConfirmStartDateDialog() async {
    DateTime selected = TermStartDateHelper.defaultStartDateFor(DateTime.now());

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateText =
                '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';

            return AppDialog(
              title: '确认本学期开学日期',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('将以此日期作为第 1 周周一，导入后将与教务系统当前周数核对。'),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selected,
                        firstDate: DateTime(selected.year - 1, 1, 1),
                        lastDate: DateTime(selected.year + 1, 12, 31),
                        helpText: '选择第 1 周开学日期',
                      );
                      if (picked != null) {
                        setDialogState(() {
                          selected = TermStartDateHelper.mondayOfWeek(picked);
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '$dateText（周一）',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const Spacer(),
                          Text(
                            '修改',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                AppDialogAction(
                  label: '取消',
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                ),
                AppDialogAction(
                  label: '下一步',
                  primary: true,
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSchools;

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择学校'),
      ),
      body: Column(
        children: [
          // 1. 顶部搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索学校',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                // WB_SPEC_261 §8：border 是死代码（主题五态全覆盖），删掉，不改显示。
                isDense: true,
              ),
            ),
          ),

          // 2 & 3. 主列表区：搜索态平面列表（不用 controller），非搜索态 A-Z 分组列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_isSearching
                    ? _buildSearchBody(filtered: filtered)
                    : _buildGroupedBody()),
          ),

          // 4. 底部手动输入入口（始终保留）
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('不在列表中？手动输入教务网址'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _onManualInput,
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索态：平面过滤列表（不用 ScrollController，与分组列表隔离）
  Widget _buildSearchBody({required List<SchoolEntry> filtered}) {
    // 搜索无结果空态（原样保留）
    if (filtered.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('未找到该学校，请手动输入网址'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _onManualInput,
          ),
        ],
      );
    }

    return ListView(
      children: [
        for (final school in filtered)
          _buildSchoolTile(school, keyPrefix: 'list'),
      ],
    );
  }

  /// 非搜索态：A-Z 分组列表 + 右侧索引栏（WB_SPEC_254 §3.2）
  Widget _buildGroupedBody() {
    final sections = groupSchoolsByInitial(_schools);
    final flatItems = flattenSchoolPickerItems(
      sections: sections,
      lastUsedSchool: _lastUsedSchool,
    );
    final offsets = indexOffsets(flatItems);
    final letters = sections.map((s) => s.letter).toList(growable: false);
    final isKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: flatItems.length,
                itemExtentBuilder: (index, _) => flatItems[index].height,
                itemBuilder: (context, index) {
                  final item = flatItems[index];
                  final Widget child;
                  switch (item.type) {
                    case SchoolPickerListItemType.recentHeader:
                      child = _buildSectionHeader('★ 最近使用', recent: true);
                    case SchoolPickerListItemType.recentSchool:
                      child =
                          _buildSchoolTile(item.school!, keyPrefix: 'recent');
                    case SchoolPickerListItemType.recentDivider:
                      child = const Divider(height: kRecentDividerHeight);
                    case SchoolPickerListItemType.letterHeader:
                      child = _buildSectionHeader(item.letter!);
                    case SchoolPickerListItemType.school:
                      child = _buildSchoolTile(item.school!, keyPrefix: 'list');
                  }
                  return SizedBox(height: item.height, child: child);
                },
              ),
            ),
            if (!isKeyboardVisible && letters.isNotEmpty)
              _buildIndexBar(letters, offsets),
          ],
        ),
        // 拖动时的大字母气泡：居中显示，不拦截触摸
        if (_dragLetter != null)
          IgnorePointer(
            child: Center(
              child: Container(
                key: const ValueKey('school_index_bubble'),
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _dragLetter!,
                  style: const TextStyle(
                    fontSize: 32,
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 固定高度 28.0 的节头（文字左对齐，padding left 16）；
  /// 最近使用沿用原样式（主色 + w600）
  Widget _buildSectionHeader(String text, {bool recent = false}) {
    return Container(
      height: kLetterHeaderHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16),
      child: Text(
        text,
        style: recent
            ? Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                )
            : Theme.of(context).textTheme.labelMedium,
      ),
    );
  }

  void _jumpToLetter(String letter, Map<String, double> offsets) {
    final rawOffset = offsets[letter];
    if (rawOffset == null || !_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final target = rawOffset.clamp(0.0, maxExtent);
    _scrollController.jumpTo(target);
  }

  /// 右侧索引栏：只显示有学校的字母；每字母高度按可用高度自适应（12.0–20.0）；
  /// 可用高度不足时整栏纵向滚动；键盘弹出时不渲染（调用方已判断）。
  /// 整栏一个 Listener：按下即跳，按住拖动到哪个字母就跳到哪组，松手结束。
  Widget _buildIndexBar(List<String> letters, Map<String, double> offsets) {
    return SizedBox(
      key: const ValueKey('school_index_bar'),
      width: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 下限 12.0 保证字号 12 的字母不被压扁重叠；可用高度不足时整栏可滚动，
          // 不在矮屏上报布局溢出。
          final itemHeight = letters.isEmpty
              ? 0.0
              : (constraints.maxHeight / letters.length).clamp(12.0, 20.0);

          // 按触点纵坐标换算字母下标，clamp 到有效范围
          String letterAt(double dy) {
            final raw = itemHeight <= 0 ? 0 : (dy / itemHeight).floor();
            final index = raw.clamp(0, letters.length - 1);
            return letters[index];
          }

          // 拖动中：字母变了才跳，防抖动
          void handleMove(double dy) {
            final letter = letterAt(dy);
            if (letter == _dragLetter) return;
            setState(() => _dragLetter = letter);
            _jumpToLetter(letter, offsets);
          }

          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              final letter = letterAt(event.localPosition.dy);
              setState(() => _dragLetter = letter);
              _jumpToLetter(letter, offsets);
            },
            onPointerMove: (event) => handleMove(event.localPosition.dy),
            onPointerUp: (_) {
              if (_dragLetter != null) setState(() => _dragLetter = null);
            },
            onPointerCancel: (_) {
              if (_dragLetter != null) setState(() => _dragLetter = null);
            },
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final letter in letters)
                    SizedBox(
                      height: itemHeight,
                      width: 24,
                      child: Center(
                        child: Text(
                          letter,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.0,
                            color: letter == _dragLetter
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            fontWeight: letter == _dragLetter
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSchoolTile(SchoolEntry school, {required String keyPrefix}) {
    return ListTile(
      key: ValueKey('${keyPrefix}_${school.url}'),
      title: Text(
        school.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: school.system == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                school.system!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
      onTap: () => _onSelectSchool(school),
    );
  }
}
