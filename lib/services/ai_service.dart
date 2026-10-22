import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../database/dao.dart';

/// 内置 AI 助手的服务层（OpenAI 兼容 chat/completions 客户端）
///
/// **不新增 pub 依赖**：HTTP 复用 `dart:io` 的 HttpClient，与 ChannelService /
/// BridgeService 同一套写法（连接 10s、响应 30s、异常一律兜成中文）。
///
/// 配置（base_url / 模型 / API Key）存 app_settings 三个键，**只落本机**。
/// 令牌安全口径与 AI 桥一致：Key 只出现在 Authorization 请求头里，日志只带
/// HTTP 状态码与截断后的异常描述，**绝不打印 Key、请求体或完整 URL**。
class AiService {
  AiService._();

  static final AiService instance = AiService._();

  // ---------- app_settings 键 ----------

  static const String baseUrlKey = 'ai_base_url';
  static const String modelKey = 'ai_model';
  static const String apiKeyKey = 'ai_api_key';

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _responseTimeout = Duration(seconds: 30);

  // ---------- 配置 ----------

  Future<AiSettings> loadSettings() async {
    final baseUrl = await Dao.instance.getSetting(baseUrlKey) ?? '';
    final model = await Dao.instance.getSetting(modelKey) ?? '';
    final apiKey = await Dao.instance.getSetting(apiKeyKey) ?? '';
    return AiSettings.clean(baseUrl: baseUrl, model: model, apiKey: apiKey);
  }

  /// 保存配置。Key 留空表示「沿用已保存的 Key」——输入框是遮挡显示的，
  /// 看不见内容就不该在保存时不小心被清掉（与 AI 桥的令牌同款处理）。
  Future<void> saveSettings({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) async {
    final old = await loadSettings();
    final next = AiSettings.clean(
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    ).withKeyFallback(old.apiKey);
    await Dao.instance.setSetting(baseUrlKey, next.baseUrl);
    await Dao.instance.setSetting(modelKey, next.model);
    await Dao.instance.setSetting(apiKeyKey, next.apiKey);
  }

  // ---------- 对话 ----------

  /// 发一轮对话，返回模型回复的原始文本（失败时 [AiChatResult.error] 为中文原因）。
  ///
  /// [messages] 里应已包含 system（课表上下文由调用方用 buildSystemPrompt 组装）
  /// 与历史会话；本方法不改动内容，只负责往返。
  Future<AiChatResult> chat(List<AiMessage> messages) async {
    final settings = await loadSettings();
    if (!settings.configured) {
      return const AiChatResult(
        text: '',
        error: '还没配置 AI：需要接口地址、模型名和 API Key',
        unconfigured: true,
      );
    }
    final body = <String, dynamic>{
      'model': settings.model,
      'messages': [for (final m in messages) m.toJson()],
      'temperature': 0.3,
      'stream': false,
    };
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      final uri = Uri.parse('${settings.chatCompletionsUrl}');
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // Key 唯一的去处：请求头。
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.apiKey}');
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(_responseTimeout);
      final raw = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_responseTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return AiChatResult(
          text: '',
          error: describeHttpError(resp.statusCode, raw),
        );
      }
      final text = extractReplyText(raw);
      if (text == null) {
        return const AiChatResult(
          text: '',
          error: '接口返回的内容无法识别，请确认接口地址是 OpenAI 兼容的对话服务',
        );
      }
      return AiChatResult(text: text);
    } on TimeoutException catch (_) {
      return const AiChatResult(text: '', error: '请求超时，换个网络或稍后再试');
    } on SocketException catch (_) {
      return const AiChatResult(text: '', error: '网络不可用');
    } catch (e) {
      final text = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return AiChatResult(
        text: '',
        error: '请求失败：${text.length > 120 ? text.substring(0, 120) : text}',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 从 chat/completions 的响应体里取出助手文本（纯函数，方便单测）。
  ///
  /// 认标准字段 `choices[0].message.content`，也认部分兼容服务返回的
  /// `choices[0].text`；取不到返回 null（由调用方转成中文错误）。
  static String? extractReplyText(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return null;
    final message = first['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      // 部分服务把 content 写成数组（多模态片段），逐段拼接文本
      if (content is String) return content;
      if (content is List) {
        return content
            .whereType<Map<String, dynamic>>()
            .map((p) => p['text']?.toString() ?? '')
            .join()
            .trim();
      }
    }
    final text = first['text'];
    if (text is String) return text;
    return null;
  }

  /// HTTP 错误的可读说明（复审 C9）：只认 OpenAI 风格的 error.message 字段，
  /// 其余情况一律不回显响应原文——异常代理可能在响应体里回显请求（含
  /// Authorization 头），原文进了聊天记录就等于把 Key 贴出来。
  static String describeHttpError(int statusCode, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] is String) {
          final msg = (err['message'] as String)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          if (msg.isNotEmpty) {
            return '接口返回 HTTP $statusCode：'
                '${msg.length > 120 ? msg.substring(0, 120) : msg}';
          }
        }
      }
    } catch (_) {
      // 不是 JSON 就走通用文案
    }
    return '接口返回 HTTP $statusCode，请检查接口地址与 API Key 是否填对';
  }

  /// 接口地址校验（保存时用）：必须是 https，本机调试地址（localhost /
  /// 127.0.0.1）例外——Key 走 Authorization 头，明文 http 等于裸奔。
  static String? validateBaseUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return '接口地址格式不对';
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1')) {
      return null;
    }
    return '接口地址要用 https 开头（Key 会随请求发出，http 是明文）';
  }
}

/// 内置 AI 的三项配置
class AiSettings {
  const AiSettings({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  /// 智谱（bigmodel）的 OpenAI 兼容地址：免费领 Key 就能用
  static const String defaultBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';

  /// 默认模型：智谱的 Flash 系列（便宜、够快），用户可在设置里改成更新的型号
  static const String defaultModel = 'glm-4-flash';

  /// 接口地址（形如 https://host/v4，后面自动补 /chat/completions）
  final String baseUrl;

  /// 模型名
  final String model;

  /// API Key：**只存本机、只进请求头**
  final String apiKey;

  bool get configured =>
      baseUrl.isNotEmpty && model.isNotEmpty && apiKey.isNotEmpty;

  /// chat/completions 的完整地址（baseUrl 结尾的斜杠与已带后缀都做兼容）
  String get chatCompletionsUrl {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) return trimmed;
    return '$trimmed/chat/completions';
  }

  /// 清理用户输入：去首尾空白（接口地址里的空格是复制粘贴最常见的坑）
  static AiSettings clean({
    required String baseUrl,
    required String model,
    required String apiKey,
  }) =>
      AiSettings(
        baseUrl: baseUrl.trim(),
        model: model.trim(),
        apiKey: apiKey.trim(),
      );

  /// Key 留空时沿用旧 Key（设置页里 Key 是遮挡显示的）
  AiSettings withKeyFallback(String fallback) => AiSettings(
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey.isEmpty ? fallback : apiKey,
      );
}

/// 一条对话消息（role：system / user / assistant）
class AiMessage {
  const AiMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// 一轮对话的结果
class AiChatResult {
  const AiChatResult({
    required this.text,
    this.error,
    this.unconfigured = false,
  });

  /// 模型回复的原始文本（含可能的指令代码块，解析交给 utils/ai_context.dart
  /// 的 parseAiReply）
  final String text;

  /// 失败原因（中文，可直接展示）；成功时为 null
  final String? error;

  /// 是否因为「没配置」而没发出去（聊天页据此显示引导空状态）
  final bool unconfigured;

  bool get ok => error == null;
}
