import '../database/dao.dart';
import '../models/chat_session.dart';

/// 智能助手对话历史服务（2.0.5 第 3 节）
///
/// 纯数据层封装：列全部会话（按更新时间倒序）、保存（有 id 更新 / 无 id 插入）、
/// 删除单条。不依赖 Riverpod / BuildContext，方便服务层单测。
class ChatSessionService {
  ChatSessionService._();

  static final ChatSessionService instance = ChatSessionService._();

  /// 全部对话，按更新时间倒序（历史列表页顺序）。
  Future<List<ChatSession>> listSessions() => Dao.instance.getAllChatSessions();

  /// 保存一段对话，返回它的 id（新建时是新 id，更新时是原 id）。
  Future<int> saveSession(ChatSession session) =>
      Dao.instance.saveChatSession(session);

  /// 删除一段对话，返回是否真的删掉了（0 = id 不存在）。
  Future<bool> deleteSession(int id) async =>
      await Dao.instance.deleteChatSession(id) > 0;
}
