import 'dart:convert';

import '../models/course.dart';
import '../models/note.dart';
import '../models/semester.dart';
import '../services/command_executor.dart';
import 'command_describe.dart';
import 'week_calc.dart';

/// AI 桥协议编解码 + 拆分/合并/去重策略（**纯函数区**，外部 AI 也可照此对接）
///
/// 桥把 GitHub 私有仓当信箱，仓库里只有三类文件，全部 UTF-8 JSON：
///
/// | 路径 | 谁写 | 结构 |
/// |---|---|---|
/// | `commands/<id>.json` | 外部 AI | `{id, createdAt, note?, commands:[…执行器指令…]}` |
/// | `results/<id>.json` | App | `{id, executedAt, status, results:[{index, type, success, message, state}]}` |
/// | `state/snapshot.json` | App | 课表快照（学期 + 课程 + 备注 + 考试），见 [buildSnapshotJson] |
///
/// 本文件只做「字符串 ↔ 对象 ↔ 字符串」与各项策略判定，**不碰网络、不碰数据库**：
/// external 侧只要照这张表产出文件即可；App 侧的 destructive 拆分、状态判定、
/// 去重裁剪都能在这里单测，服务层只负责 IO 编排。
///
/// 安全口径：**令牌不属于本文件**。搭施加密的请求头之外无处可去，快照函数也
/// 只吃「学期 + 课程 + 备注」三类入参，结构上就不可能把设置或令牌带出去。

// ---------- 指令批 ----------

/// 指令批 id 的合法字符集（同时也是 `commands/` 下的文件名主体）。
///
/// 收紧字符集是一道安全下限：id 会被拼进 API 路径去写 `results/<id>.json`，
/// 一旦允许 `/` 或 `..`，写信箱的人就能改写仓库里的任意路径。非法 id 一律
/// 跳过（记一条失败），绝不拼接 URL。
final RegExp commandIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// 规范化指令批 id：合法则返回，非法（空、超长、含斜杠等）返回 null。
String? sanitizeCommandId(String raw) {
  final id = raw.trim();
  if (id.isEmpty || id.length > 64) return null;
  return commandIdPattern.hasMatch(id) ? id : null;
}

/// 外部 AI 写的一批指令（对应 `commands/<id>.json`）
class BridgeCommandBatch {
  const BridgeCommandBatch({
    required this.id,
    required this.createdAtRaw,
    required this.note,
    required this.commands,
  });

  final String id;

  /// createdAt 的原始值（存在仓库里的文本；格式由写信箱的一侧决定）
  final String createdAtRaw;

  /// 写信箱的人留给自己看的备注（不参与任何逻辑）
  final String? note;

  /// 指令原文，逐条喂给 [CommandExecutor]
  final List<Map<String, dynamic>> commands;

  /// 该批的排序键：createdAt 解析不出时按 0 处理（排最前，先到先处理）
  int get sortKey => DateTime.tryParse(createdAtRaw)?.millisecondsSinceEpoch ?? 0;
}

/// 解析指令批文件；任何结构问题（非法 JSON / 无 id / 无指令）都返回 null，
/// 由调用方记一条中文失败后跳过——桥的两侧都可能写错，错了也不能炸 App。
BridgeCommandBatch? parseCommandBatch(String raw, {String? fallbackId}) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final rawId = decoded['id'] ?? fallbackId;
  if (rawId == null) return null;
  final id = sanitizeCommandId(rawId.toString());
  if (id == null) return null;
  final rawCommands = decoded['commands'];
  if (rawCommands is! List) return null;
  final commands = <Map<String, dynamic>>[
    // 非对象元素直接丢弃（执行器有自己的校验，这里只保证类型安全）
    for (final c in rawCommands)
      if (c is Map<String, dynamic>) Map<String, dynamic>.of(c),
  ];
  if (commands.isEmpty) return null;
  final note = decoded['note']?.toString().trim();
  return BridgeCommandBatch(
    id: id,
    createdAtRaw: decoded['createdAt']?.toString() ?? '',
    note: note == null || note.isEmpty ? null : note,
    commands: commands,
  );
}

/// 按 createdAt 升序排批（不修改入参）
List<BridgeCommandBatch> sortByCreatedAt(List<BridgeCommandBatch> batches) =>
    [...batches]..sort((a, b) => a.sortKey.compareTo(b.sortKey));

/// 以文件名派生的规范 id 解析指令批的结果（2.0.0 复审 B3）
typedef CanonicalBatchResult = ({
  BridgeCommandBatch? batch,
  bool mismatched,
});

/// 解析指令批并**强制以 [canonicalId]（文件名派生的 id）为准**（2.0.0 复审 B3）。
///
/// [mismatched] 为 true 表示文件正文里的 id 与文件名不一致（或正文 id 非法），
/// 由调用方在同步摘要里记一笔——否则外部 AI 会以为自己写的 id 生效了，而 App
/// 实际是按文件名去 processed 去重、按文件名拼 results 路径的，两边会各说各话。
///
/// 为什么文件名说了算：文件名是 App 唯一能反复拿到、且必然与仓库里那份文件
/// 一一对应的标识；若以正文 id 为准，同一个文件改一下 id 就能绕过去重被再执行
/// 一遍，破坏指令会被重复入队。正文 id 非法（含斜杠等）导致整批解析失败时，
/// 剔除该字段再试一次，让文件名兜底生效，而不是整份指令被丢掉。
CanonicalBatchResult parseCanonicalCommandBatch(
  String raw, {
  required String canonicalId,
}) {
  final parsed = parseCommandBatch(raw, fallbackId: canonicalId);
  if (parsed != null) {
    if (parsed.id == canonicalId) return (batch: parsed, mismatched: false);
    return (
      batch: BridgeCommandBatch(
        id: canonicalId,
        createdAtRaw: parsed.createdAtRaw,
        note: parsed.note,
        commands: parsed.commands,
      ),
      mismatched: true,
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return (batch: null, mismatched: false);
  }
  if (decoded is! Map<String, dynamic>) return (batch: null, mismatched: false);
  final retried = parseCommandBatch(
    jsonEncode(Map<String, dynamic>.of(decoded)..remove('id')),
    fallbackId: canonicalId,
  );
  if (retried == null) return (batch: null, mismatched: false);
  return (batch: retried, mismatched: true);
}

// ---------- destructive 拆分 ----------

/// 带原始下标的指令（下标是回来组装 results 的唯一凭据）
class IndexedCommand {
  const IndexedCommand({required this.index, required this.command});

  /// 该指令在指令批里的下标（从 0 起）
  final int index;
  final Map<String, dynamic> command;

  String get type => command['type']?.toString().trim() ?? '';
}

/// 一批指令按「是否有破坏性」拆分的结果
class CommandSplit {
  const CommandSplit({required this.safe, required this.destructive});

  /// 非破坏指令：桥可以立即执行
  final List<IndexedCommand> safe;

  /// 破坏指令（一期只有 delete_note）：必须等人确认
  final List<IndexedCommand> destructive;

  bool get hasDestructive => destructive.isNotEmpty;
}

/// 按 [CommandRegistry.destructiveOf] 拆分指令批。
///
/// 判定**只读注册表**，不在这里另写一份 `if (type == 'xxx')`——将来新增
/// 破坏性指令时改注册表一处即可。未知类型按非破坏处理：执行器会把它们判成
/// 「不支持的指令类型」并返回失败，语义上比静默丢弃更诚实。
CommandSplit splitByDestructive(List<Map<String, dynamic>> commands) {
  final safe = <IndexedCommand>[];
  final destructive = <IndexedCommand>[];
  for (var i = 0; i < commands.length; i++) {
    final item = IndexedCommand(index: i, command: commands[i]);
    if (CommandRegistry.destructiveOf(item.type)) {
      destructive.add(item);
    } else {
      safe.add(item);
    }
  }
  return CommandSplit(safe: safe, destructive: destructive);
}

// ---------- 结果文件 ----------

/// results 里每条指令的状态
enum BridgeResultState {
  /// 已真正落库（可能成功也可能失败，看 success）
  executed,

  /// 破坏指令：已放进本地待确认队列，还没执行
  pending,

  /// 用户在 App 里点了「拒绝」
  rejected,
}

/// results 文件里的一条记录
class BridgeResultEntry {
  const BridgeResultEntry({
    required this.index,
    required this.type,
    required this.success,
    required this.message,
    this.state = BridgeResultState.executed,
  });

  final int index;
  final String type;
  final bool success;
  final String message;
  final BridgeResultState state;

  Map<String, dynamic> toJson() => {
        'index': index,
        'type': type,
        'success': success,
        'message': message,
        'state': state.name,
      };

  static BridgeResultEntry? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final index = raw['index'];
    if (index is! int) return null;
    return BridgeResultEntry(
      index: index,
      type: raw['type']?.toString() ?? '',
      success: raw['success'] == true,
      message: raw['message']?.toString() ?? '',
      state: _stateFromName(raw['state']?.toString()),
    );
  }

  static BridgeResultState _stateFromName(String? name) => switch (name) {
        'pending' => BridgeResultState.pending,
        'rejected' => BridgeResultState.rejected,
        _ => BridgeResultState.executed,
      };
}

/// results 文件的 status 取值
class BridgeResultStatus {
  const BridgeResultStatus._();

  /// 全部成功
  static const String done = 'done';

  /// 部分失败（含被用户拒绝）
  static const String partial = 'partial';

  /// 有指令在等确认
  static const String awaitingConfirm = 'awaiting_confirm';
}

/// 整批状态：等确认 > 有失败 > 全成功。
/// 优先级如此是因为「还在等确认」是写信箱的人最该先知道的事——他得等用户在
/// App 里点完那条 destructive 指令，才谈得上后续。
String statusOfEntries(List<BridgeResultEntry> entries) {
  if (entries.isEmpty) return BridgeResultStatus.done;
  if (entries.any((e) => e.state == BridgeResultState.pending)) {
    return BridgeResultStatus.awaitingConfirm;
  }
  // 被拒绝的条目无论 success 字段如何都算未达成——拒绝即失败，不能报 done
  if (entries.any(
      (e) => !e.success || e.state == BridgeResultState.rejected)) {
    return BridgeResultStatus.partial;
  }
  return BridgeResultStatus.done;
}

/// 把新一轮的条目合并进已有的 results 文档（**按 index 覆盖**，其余原样保留）。
///
/// 写 results 有两种场景：整批首次写回、用户事后确认/拒绝了某几条。后者必须
/// 保留先前的条目——故统一走这一条合并路径：同下标以新条目为准，其余沿用旧值，
/// 最后按 index 升序输出。
List<BridgeResultEntry> mergeResultEntries({
  required Object? existingDoc,
  required List<BridgeResultEntry> updates,
}) {
  final byIndex = <int, BridgeResultEntry>{
    for (final e in updates) e.index: e,
  };
  if (existingDoc is Map<String, dynamic>) {
    final rawResults = existingDoc['results'];
    if (rawResults is List) {
      for (final r in rawResults) {
        final old = BridgeResultEntry.fromJson(r);
        if (old != null) byIndex.putIfAbsent(old.index, () => old);
      }
    }
  }
  return byIndex.values.toList()..sort((a, b) => a.index.compareTo(b.index));
}

/// 组装 `results/<id>.json` 的正文（status 由 [statusOfEntries] 统一算出，
/// 调用方不许自己拼字符串，避免两侧口径漂移）
Map<String, dynamic> buildResultsJson({
  required String batchId,
  required DateTime executedAt,
  required List<BridgeResultEntry> entries,
}) =>
    {
      'id': batchId,
      'executedAt': executedAt.toIso8601String(),
      'status': statusOfEntries(entries),
      'results': [for (final e in entries) e.toJson()],
    };

// ---------- 已处理指令批 ----------

/// 已处理指令批 id 的最大保留条数（本地去重用，不需要更长的历史）
const int kProcessedIdsLimit = 200;

/// 追加已处理 id 并裁剪到最近 [limit] 条（旧的先丢，超出即删表头）。
/// 重复 id 去重后再追加，顺序保持「历史在前、新来的在后」。
List<String> keepRecentProcessed(
  List<String> history,
  Iterable<String> added, {
  int limit = kProcessedIdsLimit,
}) {
  final merged = <String>[];
  final seen = <String>{};
  for (final id in [...history, ...added]) {
    if (seen.add(id)) merged.add(id);
  }
  if (merged.length <= limit) return merged;
  return merged.sublist(merged.length - limit);
}

/// 解析 `processed_command_ids`（坏数据按空历史处理，不炸）
List<String> parseProcessedIds(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is String && e.isNotEmpty) e,
    ];
  } catch (_) {
    return const [];
  }
}

// ---------- 待确认队列 ----------

/// 本地待确认的一条破坏指令（存 app_settings 的 JSON 数组，一个元素一条）
class BridgePendingItem {
  const BridgePendingItem({
    required this.batchId,
    required this.index,
    required this.type,
    required this.command,
    required this.arrivedAt,
    this.detail,
  });

  /// 来自哪个指令批（决定了回来补写哪个 results 文件）
  final String batchId;

  /// 在该批里的下标
  final int index;
  final String type;

  /// 指令原文，用户在 App 里点「执行」时原样喂给执行器
  final Map<String, dynamic> command;

  /// 到达时间戳（毫秒）
  final int arrivedAt;

  /// 人话补充信息（如「2026-10-23 交作业」），由服务层入库时按需查库补上；
  /// 查不到就为 null，[describePendingCommand] 会退化成带 id 的兜底文案。
  final String? detail;

  Map<String, dynamic> toJson() => {
        'batchId': batchId,
        'index': index,
        'type': type,
        'command': command,
        'arrivedAt': arrivedAt,
        if (detail != null && detail!.isNotEmpty) 'detail': detail,
      };

  static BridgePendingItem? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final command = raw['command'];
    final batchId = sanitizeCommandId(raw['batchId']?.toString() ?? '');
    final index = raw['index'];
    if (batchId == null || index is! int || command is! Map<String, dynamic>) {
      return null;
    }
    return BridgePendingItem(
      batchId: batchId,
      index: index,
      type: raw['type']?.toString() ?? '',
      command: Map<String, dynamic>.of(command),
      arrivedAt: raw['arrivedAt'] is int ? raw['arrivedAt'] as int : 0,
      detail: raw['detail']?.toString(),
    );
  }
}

/// 解析待确认队列（元素坏掉跳过，整串坏掉返回空列表）
List<BridgePendingItem> parsePendingList(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [for (final e in decoded) if (e != null) BridgePendingItem.fromJson(e)]
        .whereType<BridgePendingItem>()
        .toList();
  } catch (_) {
    return const [];
  }
}

/// 序列化待确认队列
String encodePendingList(List<BridgePendingItem> items) =>
    jsonEncode([for (final i in items) i.toJson()]);

/// 待确认条目的身份键：一个指令批里的一个下标至多一条
String _pendingKey(String batchId, int index) => '$batchId#$index';

/// 往待确认队列里追加条目：同 (batchId, index) 已有条目的直接跳过（2.0.0 复审 B3）。
///
/// 幂等是必要的：processed 记录丢失、用户手动重放同一批、或者同步中途失败后
/// 重试，都会让同一批指令再走一遍入队。不去重的话队列里会出现两条一模一样的
/// 待确认项，用户点掉一条还剩一条，看着像「删不掉」。
/// 返回新列表，不修改入参。
List<BridgePendingItem> appendPendingItems(
  List<BridgePendingItem> queue,
  Iterable<BridgePendingItem> added,
) {
  final seen = <String>{
    for (final q in queue) _pendingKey(q.batchId, q.index),
  };
  final out = List<BridgePendingItem>.of(queue);
  for (final item in added) {
    if (seen.add(_pendingKey(item.batchId, item.index))) out.add(item);
  }
  return out;
}

/// 把一条待确认指令说成人话（给用户点「执行/拒绝」时看的标题）
///
/// 描述本身复用 [describeCommand]（与内置 AI 的确认卡片同源），这里只补上桥
/// 独有的 [BridgePendingItem.detail]（查库得到的「日期 + 内容」），让「删除备注」
/// 能带上具体内容而不是一个 id。
String describePendingCommand(BridgePendingItem item) => describeCommand(
      item.command,
      detail: item.detail,
    );

// ---------- 桥配置 ----------

/// 桥的三项配置（owner / repo / token），存 app_settings 三个键
class BridgeSettings {
  const BridgeSettings({
    required this.owner,
    required this.repo,
    required this.token,
  });

  final String owner;
  final String repo;

  /// 细粒度令牌：只进 Authorization 请求头，**不落日志、不落结果文件、不落快照**
  final String token;

  bool get configured => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty;

  /// 清理用户输入：去首尾空白，并剔除 owner/repo 里可能被用来拼错 API 路径的
  /// 斜杠与反斜杠（这两个值只是「仓库归属名」与「仓库名」，不该含路径分隔符）
  static BridgeSettings clean({
    required String owner,
    required String repo,
    required String token,
  }) =>
      BridgeSettings(
        owner: owner.trim().replaceAll(_pathChars, ''),
        repo: repo.trim().replaceAll(_pathChars, ''),
        token: token.trim(),
      );

  /// 令牌留空时的兜底：沿用旧令牌（设置页里令牌是遮挡显示的，留空表示不改）
  BridgeSettings withTokenFallback(String fallback) => BridgeSettings(
        owner: owner,
        repo: repo,
        token: token.isEmpty ? fallback : token,
      );
}

final RegExp _pathChars = RegExp(r'[/\\]');

// ---------- 快照 ----------

/// 课表快照版本号（将来改结构时自增，供外部 AI 判断兼容性）
const int kSnapshotVersion = 1;

/// 组装 `state/snapshot.json`：当前学期信息 + 全部课程精简字段 + 按日期分组的
/// 备注 + 考试日期清单，回答「我明天有什么课/什么时候考试」这类问题够了。
///
/// **入参刻意只有课表数据**（没有 settings、没有 token）：快照会被上传到仓库，
/// 结构上就不允许把隐私数据带出去。
Map<String, dynamic> buildSnapshotJson({
  required Semester? semester,
  required List<Course> courses,
  required List<Note> notes,
  required DateTime now,
}) {
  final notesByDate = <String, List<String>>{};
  for (final n in notes) {
    final content = n.content.trim();
    if (content.isEmpty) continue;
    notesByDate.putIfAbsent(n.date, () => <String>[]).add(content);
  }
  return {
    'app': 'xiaoma_timetable',
    'snapshotVersion': kSnapshotVersion,
    'generatedAt': now.toIso8601String(),
    'semester': semester == null
        ? null
        : {
            'name': semester.name,
            'startDate': semester.startDate,
            'totalWeeks': semester.totalWeeks,
            // 今天处在本学期第几周（0 = 还没开学），模型不必自己算日期
            'todayWeek': WeekCalc.currentWeek(semester.startDateParsed, now),
          },
    'courses': [
      for (final c in courses)
        {
          if (c.id != null) 'id': c.id,
          'name': c.name,
          if (c.teacher != null) 'teacher': c.teacher,
          if (c.classroom != null) 'classroom': c.classroom,
          'dayOfWeek': c.dayOfWeek,
          'startSection': c.startSection,
          'endSection': c.endSection,
          'weeks': c.weeks,
          'weekType': c.weekType,
          if (c.note != null) 'note': c.note,
          'examDate': c.examDate == null ? null : _stampText(c.examDate!),
        },
    ],
    // 按日期分组的备注：'2026-10-23': ['交作业', '买面包']
    'notes': notesByDate,
    // 考试单独列一份，免得模型为了回答「什么时候考试」去遍历全部课程
    'exams': [
      for (final c in courses)
        if (c.examDate != null)
          {
            if (c.id != null) 'courseId': c.id,
            'courseName': c.name,
            'date': _stampText(c.examDate!),
          },
    ],
  };
}

/// 毫秒时间戳 → 「yyyy-MM-dd」；带时刻时补「 HH:mm」
String _stampText(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  final date = '${t.year}-${two(t.month)}-${two(t.day)}';
  if (t.hour == 0 && t.minute == 0) return date;
  return '$date ${two(t.hour)}:${two(t.minute)}';
}
