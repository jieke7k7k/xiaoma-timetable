import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/dao.dart';
import '../models/course.dart';
import '../utils/bridge_codec.dart';
import 'command_executor.dart';

/// AI 桥同步服务：把 GitHub 私有仓当命令信箱（**只负责 IO 编排**）
///
/// 协议、拆分策略、状态判定全在 `utils/bridge_codec.dart`（纯函数），本文件把
/// 它们串起来：`syncNow()` 拉指令 → 交给 [CommandExecutor] 执行 → 写回 results
/// → 上传快照 → 把「处理过」这件事记进 app_settings。
///
/// **调用方约定（与 [CommandExecutor] 同一口径）**：本服务不依赖 Riverpod /
/// BuildContext，不做任何刷新动作。是否产生了数据变更由 [BridgeSyncOutcome.changed]
/// 告知调用方，provider 重查、提醒重排、备注通知、小部件刷新一律由页面层负责
/// （见 ARCHITECTURE.md「1.3.6·AI 桥」，这样一批 10 条指令只联动刷新一遍）。
///
/// **令牌安全**：`Authorization` 请求头是本文件唯一可以出现令牌的地方。所有
/// 日志、结果摘要、快照里都不会带它；网络错误只带 HTTP 状态码与异常描述，
/// 也不打印完整 URL。
///
/// 容错口径：单个文件失败、单批失败、快照失败都不中断整轮，只进错误列表并由
/// [BridgeSyncOutcome.summary] 汇总成一句中文，写进 app_settings 的
/// `last_bridge_sync`。
class BridgeService {
  BridgeService._();

  static final BridgeService instance = BridgeService._();

  // ---------- app_settings 键 ----------

  static const String ownerKey = 'bridge_owner';
  static const String repoKey = 'bridge_repo';
  static const String tokenKey = 'bridge_token';
  static const String processedKey = 'processed_command_ids';
  static const String pendingKey = 'bridge_pending';
  static const String lastSyncKey = 'last_bridge_sync';

  /// GitHub OAuth App 的 Client ID（公开标识符，设备码流程用，直接写死即可，
  /// 无需保密——它只用于「申请一个设备码」，真正敏感的是换回来的 access_token）。
  static const String githubClientId = 'Ov23liosvFFdJSTw827b';

  // ---------- 仓库内的固定路径 ----------

  static const String commandsDir = 'commands';
  static const String snapshotPath = 'state/snapshot.json';

  final CommandExecutor _executor = CommandExecutor();

  static const Duration _responseTimeout = Duration(seconds: 15);
  static const Duration _connectTimeout = Duration(seconds: 10);

  /// 正在进行的同步（保证同一时刻只有一轮：Page 与启动任务可能同时触发）
  Future<BridgeSyncOutcome>? _running;

  // ---------- 配置 ----------

  Future<BridgeSettings> loadSettings() async {
    final owner = await Dao.instance.getSetting(ownerKey) ?? '';
    final repo = await Dao.instance.getSetting(repoKey) ?? '';
    final token = await Dao.instance.getSetting(tokenKey) ?? '';
    return BridgeSettings.clean(owner: owner, repo: repo, token: token);
  }

  /// 保存配置。令牌留空表示「沿用已保存的令牌」（输入框是遮挡显示的，
  /// 看不见内容就不该在保存时被不小心清掉）。
  Future<void> saveSettings({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final old = await loadSettings();
    final next = BridgeSettings.clean(
      owner: owner,
      repo: repo,
      token: token,
    ).withTokenFallback(old.token);
    await Dao.instance.setSetting(ownerKey, next.owner);
    await Dao.instance.setSetting(repoKey, next.repo);
    await Dao.instance.setSetting(tokenKey, next.token);
  }

  /// 上次同步摘要（时间 + 文案），没同步过返回 null
  Future<String?> lastSyncSummary() async {
    final raw = await Dao.instance.getSetting(lastSyncKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  // ---------- 设备码登录（GitHub Device Flow）----------
  //
  // 普通用户走这条「一步登录」：App 向 GitHub 申请设备码 → 用户在浏览器输码授权 →
  // App 轮询拿到 access_token → 自动取 login 填 bridge_owner。信箱协议 / 同步逻辑 /
  // 执行器一律不动，只换「令牌从哪来」。

  /// 申请设备码（第一步）：POST https://github.com/login/device/code。
  /// 成功返回 user_code 等信息；失败时 [DeviceCodeResponse.error] 为中文原因。
  Future<DeviceCodeResponse> requestDeviceCode() async {
    final res = await _deviceFlowPost(
      'https://github.com/login/device/code',
      const {'client_id': githubClientId, 'scope': 'repo'},
    );
    final map = res.json;
    if (res.status < 200 || res.status >= 300 || map is! Map<String, dynamic>) {
      return DeviceCodeResponse(
        deviceCode: '',
        userCode: '',
        verificationUri: '',
        intervalSeconds: 5,
        error: res.error ?? _deviceErrorText(res.status, map),
      );
    }
    final deviceCode = map['device_code'];
    final userCode = map['user_code'];
    final verificationUri = map['verification_uri'];
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        verificationUri is! String) {
      return const DeviceCodeResponse(
        deviceCode: '',
        userCode: '',
        verificationUri: '',
        intervalSeconds: 5,
        error: 'GitHub 返回的内容无法识别，请稍后重试',
      );
    }
    final interval = map['interval'];
    return DeviceCodeResponse(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri,
      intervalSeconds: interval is int && interval > 0 ? interval : 5,
    );
  }

  /// 轮询令牌（第二步）：POST https://github.com/login/oauth/access_token。
  /// [deviceCode] 为第一步拿到的 device_code。
  Future<DeviceTokenResponse> pollDeviceToken(String deviceCode) async {
    final res = await _deviceFlowPost(
      'https://github.com/login/oauth/access_token',
      {
        'client_id': githubClientId,
        'device_code': deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      },
    );
    final map = res.json;
    if (res.status < 200 || res.status >= 300 || map is! Map<String, dynamic>) {
      return DeviceTokenResponse(
        status: DeviceTokenStatus.error,
        error: res.error ?? '授权请求失败（HTTP ${res.status}）',
      );
    }
    final token = map['access_token'];
    if (token is String && token.isNotEmpty) {
      return DeviceTokenResponse(
        status: DeviceTokenStatus.success,
        accessToken: token,
      );
    }
    switch (map['error']?.toString()) {
      case 'authorization_pending':
        return const DeviceTokenResponse(status: DeviceTokenStatus.pending);
      case 'slow_down':
        return const DeviceTokenResponse(status: DeviceTokenStatus.slowDown);
      case 'expired_token':
        return const DeviceTokenResponse(
          status: DeviceTokenStatus.expired,
          error: '设备码已过期，请重新申请',
        );
      case 'access_denied':
        return const DeviceTokenResponse(
          status: DeviceTokenStatus.denied,
          error: '你拒绝了授权，可以重新申请',
        );
      default:
        return DeviceTokenResponse(
          status: DeviceTokenStatus.error,
          error: '授权失败：${map['error'] ?? '未知错误'}',
        );
    }
  }

  /// 用 access_token 取当前登录用户的 login（`GET /user`）。失败返回 null。
  Future<String?> fetchGithubLogin(String token) async {
    final res = await _githubApiRequest('GET', '/user', token: token);
    final map = res.json;
    if (res.status < 200 || res.status >= 300 || map is! Map<String, dynamic>) {
      return null;
    }
    final login = map['login'];
    return login is String && login.isNotEmpty ? login : null;
  }

  /// 检查信箱仓是否存在：true 存在、false 不存在（404）、null 不确定（网络/权限等）。
  Future<bool?> checkMailboxRepo({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final res = await _githubApiRequest(
      'GET',
      '/repos/$owner/$repo',
      token: token,
    );
    if (res.status == 404) return false;
    if (res.status >= 200 && res.status < 300) return true;
    return null;
  }

  /// 一键创建信箱仓：POST /user/repos（private + auto_init），再用 Contents API
  /// 建 commands/.gitkeep、results/.gitkeep、state/.gitkeep 三个占位文件。
  /// 返回 null 表示成功，否则为中文错误原因。
  Future<String?> createMailboxRepo({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final create = await _githubApiRequest(
      'POST',
      '/user/repos',
      token: token,
      body: {'name': repo, 'private': true, 'auto_init': true},
    );
    if (create.status < 200 || create.status >= 300) {
      return create.error ?? '创建仓库失败（HTTP ${create.status}）';
    }
    final cfg = BridgeSettings.clean(owner: owner, repo: repo, token: token);
    for (final dir in const ['commands', 'results', 'state']) {
      final err = await writeRemoteFile(cfg, '$dir/.gitkeep', 'bridge');
      if (err != null) return err;
    }
    return null;
  }

  /// 设备码登录成功后落库：写令牌 / 归属名（login）/ 默认仓库名。
  Future<void> saveDeviceLogin({
    required String token,
    required String owner,
    required String repo,
  }) async {
    await Dao.instance.setSetting(tokenKey, token);
    await Dao.instance.setSetting(ownerKey, owner);
    await Dao.instance.setSetting(repoKey, repo);
  }

  /// 断开连接：清令牌与归属名（仓库名保留默认值，下次连接再覆盖）。
  Future<void> disconnect() async {
    await Dao.instance.setSetting(tokenKey, '');
    await Dao.instance.setSetting(ownerKey, '');
  }

  /// 测试连接（高级手动方式）：只读列 commands/ 目录，验证 owner/repo/令牌能访问。
  /// 成功返回目录里的文件名列表（404 也算连接成功，只是目录还空着）；失败抛中文异常。
  Future<List<String>> testConnection({
    required String owner,
    required String repo,
    required String token,
  }) async {
    final cfg = BridgeSettings.clean(owner: owner, repo: repo, token: token);
    final errors = <String>[];
    final names = await _listCommandFiles(cfg, errors);
    if (errors.isNotEmpty) {
      throw Exception(errors.first);
    }
    return names;
  }

  /// GitHub 设备码流程的 form 表单 POST（auth 域名，非 api 域名；表单编码，
  /// Accept: application/json）。返回与 [_request] 同构的 HttpResult。
  Future<HttpResult> _deviceFlowPost(
    String url,
    Map<String, String> form,
  ) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'xiaoma-timetable');
      req.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      req.write(Uri(queryParameters: form).query);
      final resp = await req.close().timeout(_responseTimeout);
      final raw = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_responseTimeout);
      Object? decoded;
      if (raw.isNotEmpty) {
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          decoded = null;
        }
      }
      return (status: resp.statusCode, json: decoded, error: null);
    } on TimeoutException catch (_) {
      return (status: -1, json: null, error: '请求超时');
    } on SocketException catch (_) {
      return (status: -1, json: null, error: '网络不可用');
    } catch (e) {
      final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return (
        status: -1,
        json: null,
        error: '请求失败：${text.length > 120 ? text.substring(0, 120) : text}',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// GitHub API 通用请求（Bearer 令牌 + JSON），供设备码流程取用户信息 / 查仓 /
  /// 建仓用。与 [_request] 的区别：[_request] 绑定「仓库 Contents 路径 + 桥配置」，
  /// 这里是 /user、/repos/{owner}/{repo}、/user/repos 等非 Contents 接口。
  Future<HttpResult> _githubApiRequest(
    String method,
    String path, {
    required String token,
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final uri = Uri.https('api.github.com', path, query);
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.userAgentHeader, 'xiaoma-timetable');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final resp = await req.close().timeout(_responseTimeout);
      final raw = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_responseTimeout);
      Object? decoded;
      if (raw.isNotEmpty) {
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          decoded = null;
        }
      }
      return (status: resp.statusCode, json: decoded, error: null);
    } on TimeoutException catch (_) {
      return (status: -1, json: null, error: '请求超时');
    } on SocketException catch (_) {
      return (status: -1, json: null, error: '网络不可用');
    } on FormatException catch (_) {
      return (status: -1, json: null, error: '返回内容不是合法 JSON');
    } catch (e) {
      final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return (
        status: -1,
        json: null,
        error: '请求失败：${text.length > 120 ? text.substring(0, 120) : text}',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 设备码申请失败时，从错误响应里尽量抠一句人话（认 error / error_description）。
  String _deviceErrorText(int status, Object? json) {
    if (json is Map<String, dynamic>) {
      final desc = json['error_description']?.toString();
      if (desc != null && desc.isNotEmpty) return desc;
      final err = json['error']?.toString();
      if (err != null && err.isNotEmpty) return err;
    }
    return '申请设备码失败（HTTP $status）';
  }

  // ---------- 待确认队列 ----------

  Future<List<BridgePendingItem>> pendingItems() async {
    final raw = await Dao.instance.getSetting(pendingKey);
    return parsePendingList(raw);
  }

  // ---------- 主流程 ----------

  /// 同步一次。已经有同步在跑时复用它的 Future（与通知初始化的共享 Future
  /// 同一思路），避免「页面点了同步」和「启动静默同步」各跑一遍重复写库。
  Future<BridgeSyncOutcome> syncNow() {
    final running = _running;
    if (running != null) return running;
    final future = _syncOnce().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  Future<BridgeSyncOutcome> _syncOnce() async {
    final started = DateTime.now();
    final cfg = await loadSettings();
    if (!cfg.configured) {
      return BridgeSyncOutcome(
        status: BridgeSyncStatus.unconfigured,
        changed: false,
        summary: '还没配置 AI 桥，先填好 owner / repo / 令牌',
        time: started,
      );
    }

    final errors = <String>[];
    var executed = 0;
    var failed = 0;
    var awaiting = 0;
    var changed = false;

    // 1) 列目录 → 读未处理过的指令批 → 按 createdAt 升序
    final processed = parseProcessedIds(
      await Dao.instance.getSetting(processedKey),
    );
    final added = <String>[];
    final batches = await _fetchPendingBatches(cfg, processed, errors);

    // 2) 逐批处理
    for (final batch in batches) {
      try {
        final outcome = await _processBatch(cfg, batch);
        executed += outcome.executed;
        failed += outcome.failed;
        awaiting += outcome.awaiting;
        changed = changed || outcome.changed;
        added.add(batch.id);
      } catch (e) {
        // 单批炸了不影响后面几批，也不向上抛（启动静默同步全靠这一层兜底）
        errors.add('指令批 ${batch.id} 处理失败：$e');
      }
    }

    // 3) 上传最新快照（放在处理之后：让外部 AI 下一次看到的快照是执行后的）
    try {
      await _uploadSnapshot(cfg);
    } catch (e) {
      errors.add('课表快照上传失败：$e');
    }

    // 4) 落本地状态
    if (added.isNotEmpty) {
      await Dao.instance.setSetting(
        processedKey,
        jsonEncode(keepRecentProcessed(processed, added)),
      );
    }
    final pendingCount = (await pendingItems()).length;
    final summary = _buildSummary(
      batches: batches.length,
      executed: executed,
      failed: failed,
      awaiting: awaiting,
      pendingCount: pendingCount,
      errors: errors,
    );
    await Dao.instance.setSetting(
      lastSyncKey,
      '${_formatTime(started)} · $summary',
    );

    // 状态口径：整批都没跑起来（连目录都列不出来）才算 failed；跑过批但夹带
    // 小错误（某个文件读不动、某个批写回失败）记 partial——剩余那些批其实都
    // 处理完了，报 failed 会让人以为整轮白跑。错误数由摘要里那句「N 个小错误」如实带出
    final BridgeSyncStatus status;
    if (errors.isEmpty) {
      status = BridgeSyncStatus.completed;
    } else if (batches.isEmpty) {
      status = BridgeSyncStatus.failed;
    } else {
      status = BridgeSyncStatus.partial;
    }

    return BridgeSyncOutcome(
      status: status,
      changed: changed,
      summary: summary,
      errors: errors,
      time: started,
      awaitingCount: awaiting,
    );
  }

  /// 列 `commands/` 目录，逐个读没处理过的批；返回已按 createdAt 升序排好。
  Future<List<BridgeCommandBatch>> _fetchPendingBatches(
    BridgeSettings cfg,
    List<String> processed,
    List<String> errors,
  ) async {
    final names = await _listCommandFiles(cfg, errors);
    if (names.isEmpty) return const [];
    final batches = <BridgeCommandBatch>[];
    for (final name in names) {
      final id = sanitizeCommandId(
        name.endsWith('.json') ? name.substring(0, name.length - 5) : name,
      );
      if (id == null) {
        // 文件名非法（含斜杠/路径穿越字符）不拼 URL，直接跳过
        errors.add('跳过非法指令批文件名：$name');
        continue;
      }
      if (processed.contains(id)) continue;
      final file = await readRemoteFile(cfg, '$commandsDir/$id.json');
      if (file == null) {
        errors.add('读取指令批 $id 失败');
        continue;
      }
      // 文件名派生的 id 是唯一规范 id：去重、写 results 都认它，
      // 正文里的 id 只作参考（不一致时以文件名为准并记一笔，见 codec 注释）
      final parsed = parseCanonicalCommandBatch(file.text, canonicalId: id);
      final batch = parsed.batch;
      if (batch == null) {
        errors.add('指令批 $id 内容格式不对，已跳过');
        continue;
      }
      if (parsed.mismatched) {
        errors.add('指令批 $id 文件里的 id 与文件名不一致，已按文件名处理');
      }
      batches.add(batch);
    }
    return sortByCreatedAt(batches);
  }

  /// 处理一个指令批：非破坏指令立即执行，破坏指令进待确认队列，最后写回 results
  Future<_BatchOutcome> _processBatch(
    BridgeSettings cfg,
    BridgeCommandBatch batch,
  ) async {
    final split = splitByDestructive(batch.commands);
    final results = await _executor.executeAll(
      [for (final s in split.safe) s.command],
      source: CommandSource.bridge,
    );
    final entries = <BridgeResultEntry>[];
    var executedOk = 0;
    var executedFailed = 0;
    for (var i = 0; i < split.safe.length; i++) {
      final result = results[i];
      entries.add(
        BridgeResultEntry(
          index: split.safe[i].index,
          type: result.type,
          success: result.success,
          message: result.message,
        ),
      );
      if (result.success) {
        executedOk++;
      } else {
        executedFailed++;
      }
    }

    var awaiting = 0;
    if (split.destructive.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final incoming = <BridgePendingItem>[];
      for (final item in split.destructive) {
        incoming.add(
          BridgePendingItem(
            batchId: batch.id,
            index: item.index,
            type: item.type,
            command: item.command,
            arrivedAt: now,
            detail: await _destructiveDetail(item),
          ),
        );
      }
      // 按「批 id + 下标」去重后入队：同一批重复处理时不产生两张一样的卡片
      // （awaiting 记真正新入队的条数，被去重跳过的本来就在队列里等着）
      final queue = await pendingItems();
      final merged = appendPendingItems(queue, incoming);
      await _savePending(merged);
      awaiting = merged.length - queue.length;
      entries.addAll([
        for (final item in split.destructive)
          BridgeResultEntry(
            index: item.index,
            type: item.type,
            success: false,
            message: '破坏性指令已放入本地待确认队列，等用户在 App 里点「执行」或「拒绝」',
            state: BridgeResultState.pending,
          ),
      ]);
    }

    await _writeResults(cfg, batch.id, entries);
    return _BatchOutcome(
      changed: executedOk > 0,
      executed: executedOk + executedFailed,
      failed: executedFailed,
      awaiting: awaiting,
    );
  }

  /// 待确认队列里那句人话的补充信息：delete_note 去库里查一下这条备注写了啥。
  /// 查不到（可能已经被删）返回 null，交给描述函数退化成「删除备注 id=N」。
  Future<String?> _destructiveDetail(IndexedCommand item) async {
    if (item.type != 'delete_note') return null;
    final id = item.command['id'] ?? item.command['noteId'];
    if (id is! int) return null;
    try {
      final notes = await Dao.instance.getAllNotes();
      for (final n in notes) {
        if (n.id == id) return '${n.date} ${n.content}';
      }
    } catch (_) {
      // 读库失败不影响入队，只是描述朴素一点
    }
    return null;
  }

  // ---------- 确认 / 拒绝 ----------

  /// 处理一条待确认指令：[approve] 为 true 时原样喂给执行器，否则直接标拒绝。
  ///
  /// 无论批准还是拒绝，都会再走一次写回（合并回该批的 results 文件），并把
  /// 这一条从本地队列里摘掉。返回是否有数据变更，供调用方决定要不要刷新。
  Future<BridgeResolveOutcome> resolvePending(
    BridgePendingItem item, {
    required bool approve,
  }) async {
    String message;
    var success = false;
    var changed = false;
    if (!approve) {
      message = '用户拒绝了这条指令';
    } else {
      final result = await _executor.execute(item.command,
          source: CommandSource.bridge);
      // 批准了但执行失败（比如那条备注已经被删过）也要如实写回 success=false
      success = result.success;
      changed = success;
      message = result.message;
    }
    final entry = BridgeResultEntry(
      index: item.index,
      type: item.type,
      success: success,
      message: message,
      state: approve ? BridgeResultState.executed : BridgeResultState.rejected,
    );

    // 出队：无论网络写回是否成功都要出队，否则用户会永远重复看到这一条
    await _dequeue(item);

    final cfg = await loadSettings();
    if (!cfg.configured) {
      return BridgeResolveOutcome(
        changed: changed,
        message: '$message（桥未配置，未写回 results）',
      );
    }
    final error = await _writeResults(cfg, item.batchId, [entry]);
    return BridgeResolveOutcome(
      changed: changed,
      message: error == null ? message : '$message（写回 results 失败：$error）',
    );
  }

  Future<void> _dequeue(BridgePendingItem item) async {
    final queue = await pendingItems();
    await _savePending([
      for (final q in queue)
        if (!(q.batchId == item.batchId && q.index == item.index)) q,
    ]);
  }

  // ---------- 本地持久化辅助 ----------

  Future<void> _savePending(List<BridgePendingItem> items) async {
    await Dao.instance.setSetting(pendingKey, encodePendingList(items));
  }

  /// 写回 results：先 GET 拿 sha（已存在的文件 PUT 必须带）+ 旧条目，合并后 PUT
  Future<String?> _writeResults(
    BridgeSettings cfg,
    String batchId,
    List<BridgeResultEntry> updates,
  ) async {
    final path = 'results/$batchId.json';
    final old = await readRemoteFile(cfg, path);
    Object? existingDoc;
    if (old != null) {
      try {
        existingDoc = jsonDecode(old.text);
      } catch (_) {
        existingDoc = null;
      }
    }
    final merged = mergeResultEntries(
      existingDoc: existingDoc,
      updates: updates,
    );
    final doc = buildResultsJson(
      batchId: batchId,
      executedAt: DateTime.now(),
      entries: merged,
    );
    return writeRemoteFile(
      cfg,
      path,
      const JsonEncoder.withIndent('  ').convert(doc),
      sha: old?.sha,
    );
  }

  Future<void> _uploadSnapshot(BridgeSettings cfg) async {
    final semester = await Dao.instance.getCurrentSemester();
    final courses = semester == null || semester.id == null
        ? const <Course>[]
        : await Dao.instance.getCoursesBySemester(semester.id!);
    final notes = await Dao.instance.getAllNotes();
    final json = buildSnapshotJson(
      semester: semester,
      courses: courses,
      notes: notes,
      now: DateTime.now(),
    );
    final old = await readRemoteFile(cfg, snapshotPath);
    // 缩进美化：外部 AI 在聊天里可能直接翻这个文件，可读性的收益大于体积代价
    final error = await writeRemoteFile(
      cfg,
      snapshotPath,
      const JsonEncoder.withIndent('  ').convert(json),
      sha: old?.sha,
    );
    if (error != null) throw Exception(error);
  }

  // ---------- GitHub Contents API ----------

  Future<List<String>> _listCommandFiles(
    BridgeSettings cfg,
    List<String> errors,
  ) async {
    // per_page：Contents API 默认一页只给 30 条，攒了一堆指令时会静默漏掉后面的。
    // 一次拉 100 条覆盖「很久没同步」的场景，信箱不需要分页游标这么重的机制
    final res = await _request(
      cfg,
      'GET',
      commandsDir,
      query: const {'per_page': '100'},
    );
    if (res.status >= 400) {
      // 404 = 信箱里还没建 commands/ 目录：等价于「没指令」，不算错误
      if (res.status != 404) {
        errors.add(res.error ?? '列 commands/ 目录失败（HTTP ${res.status}）');
      }
      return const [];
    }
    final out = <String>[];
    if (res.json is List) {
      for (final entry in res.json as List) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['type'] != 'file') continue;
        final name = entry['name'];
        if (name is String && name.endsWith('.json')) out.add(name);
      }
    } else if (res.json is Map<String, dynamic>) {
      // 极少数情况下 Contents API 直接返回单个文件对象（路径命中文件时）
      final name = (res.json as Map<String, dynamic>)['name'];
      if (name is String && name.endsWith('.json')) out.add(name);
    }
    return out;
  }

  /// 读仓库里的一个文件（base64 → UTF-8）。不存在或读失败返回 null。
  Future<RemoteFile?> readRemoteFile(BridgeSettings cfg, String path) async {
    final res = await _request(cfg, 'GET', path);
    if (res.status != 200 || res.json is! Map<String, dynamic>) return null;
    final encoded = (res.json as Map<String, dynamic>)['content'];
    if (encoded is! String) return null;
    try {
      // GitHub 返回的 base64 里带换行，先压掉再解
      final text = utf8.decode(
        base64Decode(encoded.replaceAll(_whitespace, '')),
        allowMalformed: true,
      );
      final sha = (res.json as Map<String, dynamic>)['sha'];
      return RemoteFile(sha: sha is String ? sha : null, text: text);
    } catch (_) {
      return null;
    }
  }

  /// 新建/更新一个文件。返回 null 表示成功，否则返回中文错误原因。
  Future<String?> writeRemoteFile(
    BridgeSettings cfg,
    String path,
    String content, {
    String? sha,
  }) async {
    final res = await _request(cfg, 'PUT', path, body: {
      'message': '小马课表 AI 桥：$path',
      'content': base64Encode(utf8.encode(content)),
      // 已有文件必须带 sha 才是「更新」，否则 API 报 422 而不是覆盖
      if (sha != null) 'sha': sha,
    });
    if (res.status >= 200 && res.status < 300) return null;
    return res.error ?? '写入 $path 失败（HTTP ${res.status}）';
  }

  Future<HttpResult> _request(
    BridgeSettings cfg,
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/${cfg.owner}/${cfg.repo}/contents/$path',
        query,
      );
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      // 令牌唯一的去处：请求头。绝不进日志、结果文件、快照。
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${cfg.token}');
      req.headers.set(HttpHeaders.userAgentHeader, 'xiaoma-timetable');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final resp = await req.close().timeout(_responseTimeout);
      final raw = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_responseTimeout);
      Object? decoded;
      if (raw.isNotEmpty) {
        try {
          decoded = jsonDecode(raw);
        } catch (_) {
          decoded = null;
        }
      }
      return (status: resp.statusCode, json: decoded, error: null);
    } on TimeoutException catch (_) {
      return (status: -1, json: null, error: '请求超时');
    } on SocketException catch (_) {
      return (status: -1, json: null, error: '网络不可用');
    } on FormatException catch (_) {
      return (status: -1, json: null, error: '返回内容不是合法 JSON');
    } catch (e) {
      // 只带异常描述，不带请求头
      final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return (
        status: -1,
        json: null,
        error: '请求失败：${text.length > 120 ? text.substring(0, 120) : text}',
      );
    } finally {
      client.close(force: true);
    }
  }

  // ---------- 文案辅助 ----------

  String _buildSummary({
    required int batches,
    required int executed,
    required int failed,
    required int awaiting,
    required int pendingCount,
    required List<String> errors,
  }) {
    final parts = <String>[];
    if (batches == 0) {
      parts.add('没有新指令');
    } else {
      parts.add('处理 $batches 个指令批');
    }
    if (executed > 0) {
      parts.add(failed > 0 ? '执行 $executed 条（失败 $failed 条）' : '执行 $executed 条');
    }
    if (awaiting > 0) parts.add('$awaiting 条待确认');
    if (pendingCount > 0) parts.add('队列还有 $pendingCount 条待确认');
    if (errors.isNotEmpty) parts.add('${errors.length} 个小错误');
    return parts.join('，');
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}

final RegExp _whitespace = RegExp(r'\s');

/// 仓库里的一个文件（sha 用于「更新已有文件」）
class RemoteFile {
  const RemoteFile({required this.sha, required this.text});

  final String? sha;
  final String text;
}

/// HTTP 调用的原始结果（status = -1 表示连请求都没发出去/没回来）
typedef HttpResult = ({int status, Object? json, String? error});

/// 一轮同步的结果
class BridgeSyncOutcome {
  const BridgeSyncOutcome({
    required this.status,
    required this.changed,
    required this.summary,
    required this.time,
    this.errors = const [],
    this.awaitingCount = 0,
  });

  final BridgeSyncStatus status;

  /// 本轮是否真的改了课表/备注数据（true 时调用方要联动刷新那一套）
  final bool changed;

  /// 中文摘要，也给 `last_bridge_sync` 用
  final String summary;

  /// 本轮同步的时刻
  final DateTime time;

  /// 过程中攒下的错误（单个文件/单批失败都不中断整轮）
  final List<String> errors;

  /// 本轮新进待确认队列的条数
  final int awaitingCount;
}

enum BridgeSyncStatus {
  /// 三项配置没填全：合法状态，不弹错
  unconfigured,

  /// 一轮跑完，没有错误
  completed,

  /// 处理过批、但夹着小错误（个别文件读不动/写回失败）；错误数见同步摘要
  partial,

  /// 一个批都没跑起来（如目录列不出来）
  failed,
}

/// 处理一条待确认指令的结果
class BridgeResolveOutcome {
  const BridgeResolveOutcome({required this.changed, required this.message});

  final bool changed;
  final String message;
}

/// 一个指令批的处理结果（内部用）
class _BatchOutcome {
  const _BatchOutcome({
    required this.changed,
    required this.executed,
    required this.failed,
    required this.awaiting,
  });

  final bool changed;
  final int executed;
  final int failed;
  final int awaiting;
}

/// 设备码登录第一步（申请设备码）的结果
class DeviceCodeResponse {
  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.intervalSeconds,
    this.error,
  });

  /// 轮询用，不展示给用户
  final String deviceCode;

  /// 用户要在 GitHub 页面输入的那串码（大字展示）
  final String userCode;

  /// 输码网址（一般就是 https://github.com/login/device）
  final String verificationUri;

  /// 建议轮询间隔（秒）
  final int intervalSeconds;

  /// 失败原因（中文）；成功为 null
  final String? error;

  bool get ok => error == null;
}

/// 设备码轮询的结果状态
enum DeviceTokenStatus {
  /// 用户还没授权，继续等
  pending,

  /// 用户还没输码，服务器让放慢轮询
  slowDown,

  /// 拿到令牌
  success,

  /// 设备码过期
  expired,

  /// 用户拒绝了授权
  denied,

  /// 其它错误（网络 / 服务器）
  error,
}

/// 设备码轮询（第二步）的结果
class DeviceTokenResponse {
  const DeviceTokenResponse({required this.status, this.accessToken, this.error});

  final DeviceTokenStatus status;

  /// 成功时的 access_token
  final String? accessToken;

  /// 失败原因（中文）
  final String? error;
}
