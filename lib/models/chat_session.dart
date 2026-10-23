import 'dart:convert';

/// 一条聊天消息（持久化用，与 ai_chat_page 里的运行时 `_ChatItem` 解耦）
///
/// 只存展示与「接着聊」所需的信息：角色、文本、时间，以及指令确认卡的
/// 指令原文 / 执行结果状态文本。不存任何敏感头信息（接口地址 / Key 都在
/// app_settings 里单独管，消息里从来没有出现过）。
class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  final int time; // 毫秒时间戳
  final List<Map<String, dynamic>> commands; // 该消息携带的指令原文（空=普通消息）
  final Map<String, bool> resolved; // 指令下标 → 是否已执行（JSON 里 key 转字符串）
  final List<String> results; // 执行结果中文摘要（回填展示）

  const ChatMessage({
    required this.role,
    required this.text,
    required this.time,
    this.commands = const [],
    this.resolved = const {},
    this.results = const [],
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'time': time,
        'commands': commands,
        'resolved': resolved,
        'results': results,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawCommands = json['commands'];
    final rawResolved = json['resolved'];
    final rawResults = json['results'];
    return ChatMessage(
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String? ?? '',
      time: json['time'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      commands: [
        if (rawCommands is List)
          for (final e in rawCommands)
            if (e is Map<String, dynamic>) Map<String, dynamic>.of(e),
      ],
      resolved: {
        if (rawResolved is Map)
          for (final e in rawResolved.entries)
            if (e.value is bool) '${e.key}': e.value as bool,
      },
      results: [
        if (rawResults is List)
          for (final e in rawResults)
            if (e is String) e,
      ],
    );
  }
}

/// 一段对话（智能助手历史记录，2.0.5 第 3 节）
///
/// 存标题（取首条用户消息前若干字）、创建/更新时间，以及全部消息。
/// 消息以 JSON 数组整体存在 `messagesJson` 一列里——一段对话的量级是
/// 「人手聊几句」的水平，整段读写比拆表 join 简单得多，也与 app_settings
/// 存 JSON 的既有做法一致。
class ChatSession {
  final int? id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final List<ChatMessage> messages;

  const ChatSession({
    this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'messagesJson': jsonEncode([for (final m in messages) m.toJson()]),
      };

  factory ChatSession.fromMap(Map<String, dynamic> map) {
    final raw = map['messagesJson'] as String? ?? '[]';
    List<ChatMessage> messages = const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        messages = [
          for (final e in decoded)
            if (e is Map<String, dynamic>) ChatMessage.fromJson(e),
        ];
      }
    } catch (_) {
      messages = const [];
    }
    return ChatSession(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      createdAt:
          map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt:
          map['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      messages: messages,
    );
  }
}
