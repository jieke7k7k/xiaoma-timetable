import 'package:flutter/material.dart';

import '../models/school_entry.dart';
import '../services/school_catalog_service.dart';
import '../utils/term_start_date_helper.dart';
import '../utils/web_schedule_parser.dart';
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

  List<SchoolEntry> _schools = const [];
  SchoolEntry? _lastUsedSchool;
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? SchoolCatalogService();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
  Future<DateTime?> _showConfirmStartDateDialog() async {
    DateTime selected = TermStartDateHelper.defaultStartDateFor(DateTime.now());

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateText =
                '${selected.year}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';

            return AlertDialog(
              title: const Text('确认本学期开学日期'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('将以此日期作为第 1 周周一，导入后会与教务系统当前周数核对。'),
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
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: const Text('下一步'),
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
    final showRecent = !_isSearching && _lastUsedSchool != null;

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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),

          // 2 & 3. 主列表区
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildListBody(filtered: filtered, showRecent: showRecent),
          ),

          // 4. 底部手动输入入口（始终保留）
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.language),
              title: const Text('不在列表里？手动输入教务网址'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _onManualInput,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListBody({
    required List<SchoolEntry> filtered,
    required bool showRecent,
  }) {
    // 搜索无结果空态
    if (_isSearching && filtered.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.edit_location_alt_outlined),
            title: const Text('没找到这所学校，试试手动输入网址'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _onManualInput,
          ),
        ],
      );
    }

    return ListView(
      children: [
        if (showRecent) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '★ 最近使用',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          _buildSchoolTile(_lastUsedSchool!, keyPrefix: 'recent'),
          const Divider(height: 16),
        ],
        if (!_isSearching && _schools.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              '全部学校',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        for (final school in filtered)
          _buildSchoolTile(school, keyPrefix: 'list'),
      ],
    );
  }

  Widget _buildSchoolTile(SchoolEntry school, {required String keyPrefix}) {
    return ListTile(
      key: ValueKey('${keyPrefix}_${school.url}'),
      title: Text(school.displayName),
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
