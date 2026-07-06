// 【对标来源：KouriChat-1.4.3.2 — src/services/database.py ChatMessage 持久化】
// 1:1 转译自 KouriChat 聊天记录存储逻辑
// 参考文件：src/services/database.py:ChatMessage、src/handlers/message.py

import 'dart:convert';
import '../models/chat_message.dart';
import '../models/chat_context.dart';
import 'database_service.dart';

/// 聊天仓库（对标 KouriChat database.py ChatMessage 持久化）
class ChatRepository {
  final DatabaseService _db = DatabaseService.instance;

  /// 保存消息（对标 KouriChat ChatMessage 写入）
  Future<void> saveMessage(ChatMessage message) async {
    final db = await _db.database;
    await db.insert('chat_messages', {
      'id': message.id,
      'chatId': message.chatId,
      'senderId': message.senderId,
      'senderName': message.senderName,
      'content': message.content,
      'isUser': message.isUser ? 1 : 0,
      'isSystem': message.isSystem ? 1 : 0,
      'isHidden': message.isHidden ? 1 : 0,
      'isGhost': message.isGhost ? 1 : 0,
      'type': message.type.name,
      'timestamp': message.timestamp.toIso8601String(),
      'generationTime': message.generationTime,
      'tokenCount': message.tokenCount,
      'attachmentPath': message.attachmentPath,
      'swipeHistory': jsonEncode(message.swipeHistory),
      'swipeIndex': message.swipeIndex,
      'isBookmark': message.isBookmark ? 1 : 0,
      'reasoning': message.reasoning,
    });
  }

  /// 获取会话消息（对标 KouriChat get_recent_chat_memory）
  Future<List<ChatMessage>> getMessages(
    String chatId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'chat_messages',
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_rowToMessage).toList();
  }

  /// 获取最近 N 条消息（对标 KouriChat max_groups * 2 窗口）
  Future<List<ChatMessage>> getRecentMessages(
    String chatId, {
    int count = 50,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'chat_messages',
      where: 'chatId = ? AND isHidden = 0 AND isGhost = 0',
      whereArgs: [chatId],
      orderBy: 'timestamp DESC',
      limit: count,
    );
    return rows.map(_rowToMessage).toList().reversed.toList();
  }

  /// 构建上下文（对标 KouriChat chat_contexts）
  Future<ChatContext> buildContext(
    String characterId,
    String userId, {
    int maxMessages = 50,
  }) async {
    final chatId = '${characterId}_$userId';
    final messages = await getRecentMessages(chatId, count: maxMessages);

    return ChatContext(
      characterId: characterId,
      userId: userId,
      messages: messages
          .map((m) => ContextMessage(
                role: m.isUser ? 'user' : 'assistant',
                content: m.content,
              ))
          .toList(),
      maxMessages: maxMessages,
      lastInteractionTime:
          messages.isNotEmpty ? messages.last.timestamp : null,
    );
  }

  /// 更新消息（对标 SillyTavern 编辑消息）
  Future<void> updateMessage(String id, String newContent) async {
    final db = await _db.database;
    await db.update(
      'chat_messages',
      {'content': newContent},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除消息（对标 SillyTavern 删除消息）
  Future<void> deleteMessage(String id) async {
    final db = await _db.database;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }

  /// 隐藏消息（对标 SillyTavern .mes_hide）
  Future<void> hideMessage(String id) async {
    final db = await _db.database;
    await db.update(
      'chat_messages',
      {'isHidden': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 取消隐藏（对标 SillyTavern .mes_unhide）
  Future<void> unhideMessage(String id) async {
    final db = await _db.database;
    await db.update(
      'chat_messages',
      {'isHidden': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 清空会话
  Future<void> clearChat(String chatId) async {
    final db = await _db.database;
    await db.delete(
      'chat_messages',
      where: 'chatId = ?',
      whereArgs: [chatId],
    );
  }

  /// 数据库行转消息对象
  ChatMessage _rowToMessage(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String? ?? '',
      chatId: row['chatId'] as String? ?? '',
      senderId: row['senderId'] as String? ?? '',
      senderName: row['senderName'] as String? ?? '',
      content: row['content'] as String? ?? '',
      isUser: (row['isUser'] as int?) == 1,
      isSystem: (row['isSystem'] as int?) == 1,
      isHidden: (row['isHidden'] as int?) == 1,
      isGhost: (row['isGhost'] as int?) == 1,
      type: row['type'] != null
          ? MessageType.values.firstWhere(
              (e) => e.name == row['type'],
              orElse: () => MessageType.text,
            )
          : MessageType.text,
      timestamp: row['timestamp'] != null
          ? DateTime.parse(row['timestamp'] as String)
          : DateTime.now(),
      generationTime: row['generationTime'] as int?,
      tokenCount: row['tokenCount'] as int?,
      attachmentPath: row['attachmentPath'] as String?,
      swipeHistory: (jsonDecode(row['swipeHistory'] as String? ?? '[]')
              as List<dynamic>)
          .cast<String>(),
      swipeIndex: row['swipeIndex'] as int? ?? 0,
      isBookmark: (row['isBookmark'] as int?) == 1,
      reasoning: row['reasoning'] as String?,
    );
  }
}
