import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/dao.dart';
import '../models/course.dart';
import '../models/note.dart';
import '../utils/supabase_codec.dart';

/// Supabase 云同步服务（2.1.0，WB_SPEC_211）。
///
/// Gmail 式直连：App 联网自动同步，小马用 API Key 直接读写云端三张表。
/// 配置来自编译期 `--dart-define`（SUPABASE_URL / SUPABASE_ANON_KEY），
/// **占位符或未配置时同步功能关闭、设置页显示「未配置」，绝不闪退**。
///
/// 协议要点（第 3 节）：
/// - 本地存 last_sync_at（毫秒）水位，首次同步前为 0；
/// - 上传：本地行 updatedAt 大于水位 → upsert（首次迁移全量）；
/// - 下载：只拉云端 updated_at 大于水位的行，冲突取新；
/// - 删除不同步：云端孤儿行保留，下载水位规则天然跳过，不得复活本地已删内容；
/// - 离线静默失败（记日志不弹窗不丢本地数据），下次联网重试。
class SupabaseSyncService {
  SupabaseSyncService._();
  static final SupabaseSyncService instance = SupabaseSyncService._();

  /// 水位键：上次同步时间（毫秒），app_settings 表。
  static const String lastSyncAtKey = 'supabase_last_sync_at';

  /// 上次同步摘要键（含失败原因文案），设置页「云同步」行展示用。
  static const String lastSyncSummaryKey = 'supabase_last_sync_summary';

  /// 编译期配置（真实 key 只经 --dart-define 注入，代码里不留任何真实值）。
  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// 云端读写（默认 Supabase 实现；测试注入 fake，不真连 Supabase）。
  CloudStore? _store;
  Timer? _debounce;
  Future<SupabaseSyncOutcome>? _running;

  /// 是否已配置（URL 与 anon key 都是非占位符实值）。
  bool get configured => _isReal(_url) && _isReal(_anonKey);

  static bool _isReal(String v) => v.isNotEmpty && !v.contains('YOUR_');

  /// 懒初始化云端读写；未配置抛 [StateError]，调用方应先用 [configured] 判断。
  CloudStore _ensureStore() {
    final existing = _store;
    if (existing != null) return existing;
    if (!configured) {
      throw StateError('云同步未配置');
    }
    final store = SupabaseCloudStore(SupabaseClient(_url, _anonKey));
    _store = store;
    return store;
  }

  /// 测试用：注入 fake 云端读写，避免真连 Supabase。
  @visibleForTesting
  void overrideStoreForTest(CloudStore store) => _store = store;

  /// 测试用：清掉注入的 fake 与进行中的同步，避免单例状态跨用例污染。
  @visibleForTesting
  void resetForTest() {
    _store = null;
    _running = null;
  }

  /// 注册到 DAO 的本地变更钩子（启动时调用一次），实现「变动后防抖同步」。
  ///
  /// 挂上后，课程/备注的增改（含 AI 与桥写入本地）都会经 DAO 触发一次防抖同步；
  /// 未配置时 [scheduleSync] 内部直接返回，无副作用。
  static void attachToDao() {
    Dao.onLocalChange = instance.scheduleSync;
  }

  /// 上次同步水位（毫秒），从 app_settings 读。
  Future<int> lastSyncAt() => Dao.instance.getSettingInt(lastSyncAtKey, 0);

  /// 上次同步摘要（时间 + 文案）；没同步过返回 null。
  Future<String?> lastSyncSummary() async {
    final raw = await Dao.instance.getSetting(lastSyncSummaryKey);
    return (raw == null || raw.trim().isEmpty) ? null : raw;
  }

  /// 数据变动后的防抖同步（课程/备注/考试变动统一走这里）。
  ///
  /// 未配置时静默返回；连续多次变动合并成一次（防抖窗口 2 秒）。
  void scheduleSync() {
    if (!configured) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(syncNow()));
  }

  /// 立即同步一次。已有同步在跑时复用它的 Future（与通知初始化同一思路），
  /// 避免「设置页点了同步」和「变动防抖」各跑一遍重复写库。
  Future<SupabaseSyncOutcome> syncNow() {
    // 测试注入了 fake store 时（_store != null）放行进真实流程，绕过编译期配置检查
    if (!configured && _store == null) {
      return Future.value(
        const SupabaseSyncOutcome(
          status: SupabaseSyncStatus.unconfigured,
          summary: '未配置',
          changed: false,
        ),
      );
    }
    final running = _running;
    if (running != null) return running;
    final future = _syncOnce().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  Future<SupabaseSyncOutcome> _syncOnce() async {
    final started = DateTime.now();
    try {
      final store = _ensureStore();
      final watermark = await lastSyncAt();

      // 1) 上传本地变动（首次迁移全量 + 去重），记录本轮上传的远程 id
      final upload = await _upload(store, watermark, started);

      // 2) 下载云端变动（冲突取新，云端赢写本地；跳过本轮刚上传的行）
      final downloaded = await _download(store, watermark, upload.ids, started);

      // 3) 水位推进到本次同步开始时刻（与上传 updated_at 同一时刻，
      //    避免同步窗口内的本地改动被推进后的水位淹没、永久不再上传）
      await Dao.instance.setSetting(
        lastSyncAtKey,
        '${started.millisecondsSinceEpoch}',
      );

      final summary = _buildSummary(upload.count, downloaded);
      await Dao.instance.setSetting(lastSyncSummaryKey, _withTime(started, summary));
      return SupabaseSyncOutcome(
        status: SupabaseSyncStatus.completed,
        summary: summary,
        changed: upload.count > 0 || downloaded > 0,
      );
    } catch (e) {
      // 离线/网络/云端异常：静默记日志，不弹窗、不丢本地数据，下次联网重试
      debugPrint('云同步失败：$e');
      final summary = '同步失败：${_short(e)}';
      try {
        await Dao.instance.setSetting(lastSyncSummaryKey, _withTime(started, summary));
      } catch (_) {
        // 写摘要失败也不影响：最坏就是设置页没显示这次失败原因
      }
      return SupabaseSyncOutcome(
        status: SupabaseSyncStatus.failed,
        summary: summary,
        changed: false,
      );
    }
  }

  /// 上传本地变动。返回实际上传的条数与远程 id 集合（供下载阶段跳过本轮已上行）。
  ///
  /// [started] 是本次同步的开始时刻：云端 updated_at 统一写它（UTC），
  /// 与水位推进用同一时刻，保证「上传时间 = 水位」严格一致。
  Future<({int count, Set<String> ids})> _upload(
    CloudStore store,
    int watermark,
    DateTime started,
  ) async {
    final courseRows = await Dao.instance.getAllCourseRows();
    final noteRows = await Dao.instance.getAllNoteRows();

    final upsertCourses = <Map<String, dynamic>>[];
    final exams = <Map<String, dynamic>>[];
    for (final row in courseRows) {
      final id = row['id'];
      if (id is! int || !shouldUpload(row['updatedAt'] as int?, watermark)) {
        continue;
      }
      final course = Course.fromMap(row);
      upsertCourses.add(courseToRemoteRow(course));
      final mirror = examMirrorRow(course);
      if (mirror != null) exams.add(mirror);
    }

    // 备注：先按水位过滤，首次迁移（水位 0）再做 (date, content) 去重
    final notes = <Note>[
      for (final row in noteRows)
        if (row['id'] is int && shouldUpload(row['updatedAt'] as int?, watermark))
          Note.fromMap(row),
    ];
    final List<Note> notesToUpload;
    if (watermark <= 0) {
      final dedupe = dedupeNotes(notes);
      notesToUpload = dedupe.kept;
      if (dedupe.removed.isNotEmpty) {
        debugPrint(
          '云同步首次迁移备注去重 ${dedupe.removed.length} 条：${dedupe.removed.join('；')}',
        );
      }
    } else {
      notesToUpload = notes;
    }
    final upsertNotes = [for (final n in notesToUpload) noteToRemoteRow(n)];

    // 云端 updated_at 取本次同步开始时刻（upsert 更新时 default now() 不会自动刷新）
    final nowIso = started.toUtc().toIso8601String();
    for (final r in upsertCourses) {
      r['updated_at'] = nowIso;
    }
    for (final r in upsertNotes) {
      r['updated_at'] = nowIso;
    }
    for (final r in exams) {
      r['updated_at'] = nowIso;
    }

    if (upsertCourses.isNotEmpty) await store.upsertCourses(upsertCourses);
    if (upsertNotes.isNotEmpty) await store.upsertNotes(upsertNotes);
    if (exams.isNotEmpty) await store.upsertExams(exams);

    final ids = <String>{
      for (final r in upsertCourses) r['id'] as String,
      for (final r in upsertNotes) r['id'] as String,
      for (final r in exams) r['id'] as String,
    };
    return (
      count: upsertCourses.length + upsertNotes.length + exams.length,
      ids: ids,
    );
  }

  /// 下载云端变动。返回写回本地的条数（课程 + 备注）。
  ///
  /// [uploadedIds] 是本轮刚上传的远程 id：这些行云端 updated_at 已刷新成 now，
  /// 会落进「晚于水位」的下载集，若不跳过就会被误判成「云端更新」再覆盖回本地
  /// （内容虽同、语义却是自同步循环）。跳过它们，只处理真正的云端异动。
  ///
  /// [started] 是本次同步开始时刻：本地赢时的回传 updated_at 也统一写它，
  /// 与上传、水位三者同源，避免窗口内时间不一致。
  Future<int> _download(
    CloudStore store,
    int watermark,
    Set<String> uploadedIds,
    DateTime started,
  ) async {
    final cloudCourses = await store.fetchCoursesAfter(watermark);
    final cloudNotes = await store.fetchNotesAfter(watermark);

    var changed = 0;

    // 本地现有行按 id 建索引，用于冲突取新
    final localCourseRows = await Dao.instance.getAllCourseRows();
    final localCourseById = <int, Map<String, dynamic>>{
      for (final r in localCourseRows)
        if (r['id'] is int) r['id'] as int: r,
    };

    for (final row in cloudCourses) {
      final cloudUpdatedAt = parseCloudUpdatedAt(row['updated_at']);
      // 水位过滤：早于/等于水位的行不下载（孤儿行天然跳过，不复活已删内容）
      if (cloudUpdatedAt == null || cloudUpdatedAt <= watermark) continue;
      // 跳过本轮刚上传的行，避免自同步循环
      if (uploadedIds.contains(row['id'])) continue;
      final course = courseFromRemoteRow(row);
      if (course == null) continue;
      final local = localCourseById[course.id];
      final winner = resolveConflict(local?['updatedAt'] as int?, cloudUpdatedAt);
      if (winner == SyncWinner.local) {
        // 本地赢：立即上传覆盖云端（下一轮也会再传，这里顺手闭环）
        await store.upsertCourses([
          courseToRemoteRow(Course.fromMap(local!))
            ..['updated_at'] = started.toUtc().toIso8601String(),
        ]);
        continue;
      }
      if (winner == SyncWinner.none && local != null) continue;
      // 云端赢或本地无此行：写本地（保持 localId，updatedAt 对齐云端）
      await Dao.instance.putCourseSynced(course, cloudUpdatedAt);
      changed++;
    }

    final localNoteRows = await Dao.instance.getAllNoteRows();
    final localNoteById = <int, Map<String, dynamic>>{
      for (final r in localNoteRows)
        if (r['id'] is int) r['id'] as int: r,
    };

    for (final row in cloudNotes) {
      final cloudUpdatedAt = parseCloudUpdatedAt(row['updated_at']);
      if (cloudUpdatedAt == null || cloudUpdatedAt <= watermark) continue;
      if (uploadedIds.contains(row['id'])) continue;
      final note = noteFromRemoteRow(row);
      if (note == null) continue;
      final local = localNoteById[note.id];
      final winner = resolveConflict(local?['updatedAt'] as int?, cloudUpdatedAt);
      if (winner == SyncWinner.local) {
        await store.upsertNotes([
          noteToRemoteRow(Note.fromMap(local!))
            ..['updated_at'] = started.toUtc().toIso8601String(),
        ]);
        continue;
      }
      if (winner == SyncWinner.none && local != null) continue;
      await Dao.instance.putNoteSynced(note, cloudUpdatedAt);
      changed++;
    }

    return changed;
  }

  String _buildSummary(int uploaded, int downloaded) {
    final parts = <String>[];
    if (uploaded > 0) parts.add('上传 $uploaded 条');
    if (downloaded > 0) parts.add('同步 $downloaded 条');
    if (parts.isEmpty) return '数据已是最新';
    return parts.join('，');
  }

  static String _withTime(DateTime t, String summary) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)} · $summary';
  }

  static String _short(Object e) {
    final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 120 ? text.substring(0, 120) : text;
  }
}

/// 一轮云同步的结果。
class SupabaseSyncOutcome {
  const SupabaseSyncOutcome({
    required this.status,
    required this.summary,
    required this.changed,
  });

  final SupabaseSyncStatus status;

  /// 中文摘要（也写进 last_sync_summary，设置页展示）。
  final String summary;

  /// 本轮是否真的改了本地数据（true 时调用方要失效相关 Provider）。
  final bool changed;
}

enum SupabaseSyncStatus {
  /// 未配置（占位符/缺 key）：合法状态，不弹错。
  unconfigured,

  /// 一轮跑完，无错误。
  completed,

  /// 失败（离线/网络/云端异常）：静默记日志，下次重试。
  failed,
}

/// 云端读写抽象：同步服务只依赖这个接口，测试注入 fake 即可，不真连 Supabase。
abstract class CloudStore {
  Future<List<Map<String, dynamic>>> fetchCoursesAfter(int watermarkMs);
  Future<List<Map<String, dynamic>>> fetchNotesAfter(int watermarkMs);
  Future<void> upsertCourses(List<Map<String, dynamic>> rows);
  Future<void> upsertNotes(List<Map<String, dynamic>> rows);
  Future<void> upsertExams(List<Map<String, dynamic>> rows);
}

/// Supabase 真实实现（仅生产用；测试不得构造它去连网）。
class SupabaseCloudStore implements CloudStore {
  SupabaseCloudStore(this._client);

  final SupabaseClient _client;

  /// 毫秒 → ISO-8601 UTC 字符串（Supabase updated_at 过滤用）。
  static String _iso(int watermarkMs) =>
      DateTime.fromMillisecondsSinceEpoch(watermarkMs).toUtc().toIso8601String();

  static List<Map<String, dynamic>> _asList(Object? data) {
    if (data is List) {
      return [
        for (final e in data)
          if (e is Map<String, dynamic>) e,
      ];
    }
    if (data is Map<String, dynamic>) return [data];
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchCoursesAfter(int watermarkMs) async {
    final rows =
        await _client.from('courses').select().gt('updated_at', _iso(watermarkMs));
    return _asList(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNotesAfter(int watermarkMs) async {
    final rows =
        await _client.from('notes').select().gt('updated_at', _iso(watermarkMs));
    return _asList(rows);
  }

  @override
  Future<void> upsertCourses(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('courses').upsert(rows, onConflict: 'id');
  }

  @override
  Future<void> upsertNotes(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('notes').upsert(rows, onConflict: 'id');
  }

  @override
  Future<void> upsertExams(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from('exams').upsert(rows, onConflict: 'id');
  }
}
