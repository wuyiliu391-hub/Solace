// 【对标来源：KouriChat-1.4.3.2 — src/services/ai/llm_service.py chat_contexts】
// 1:1 转译自 KouriChat 上下文窗口管理
// 参考文件：src/services/ai/llm_service.py:_manage_context()、get_recent_chat_memory()

/// 聊天上下文（对标 KouriChat chat_contexts[user_id]）
class ChatContext {
  /// 角色 ID
  final String characterId;

  /// 用户 ID
  final String userId;

  /// 消息历史列表（对标 chat_contexts: List[{role, content}]）
  final List<ContextMessage> messages;

  /// 最大消息数（对标 max_groups * 2）
  final int maxMessages;

  /// 最后交互时间（对标 last_chat_time）
  final DateTime? lastInteractionTime;

  const ChatContext({
    required this.characterId,
    required this.userId,
    this.messages = const [],
    this.maxMessages = 50,
    this.lastInteractionTime,
  });

  /// 添加消息并维护窗口大小（对标 _manage_context）
  ChatContext addMessage(String role, String content) {
    final updated = List<ContextMessage>.from(messages)
      ..add(ContextMessage(role: role, content: content));
    // 超出窗口时截断保留最近（对标 while len > max_groups*2: 截断）
    while (updated.length > maxMessages) {
      updated.removeAt(0);
    }
    return ChatContext(
      characterId: characterId,
      userId: userId,
      messages: updated,
      maxMessages: maxMessages,
      lastInteractionTime: DateTime.now(),
    );
  }

  /// 构建时间上下文描述（对标 _build_time_context）
  String buildTimeContext() {
    if (lastInteractionTime == null) return '';
    final diff = DateTime.now().difference(lastInteractionTime!);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  Map<String, dynamic> toJson() => {
        'characterId': characterId,
        'userId': userId,
        'messages': messages.map((e) => e.toJson()).toList(),
        'maxMessages': maxMessages,
        'lastInteractionTime': lastInteractionTime?.toIso8601String(),
      };

  factory ChatContext.fromJson(Map<String, dynamic> json) {
    return ChatContext(
      characterId: json['characterId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) =>
                  ContextMessage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      maxMessages: json['maxMessages'] as int? ?? 50,
      lastInteractionTime: json['lastInteractionTime'] != null
          ? DateTime.parse(json['lastInteractionTime'] as String)
          : null,
    );
  }
}

/// 上下文消息（对标 KouriChat {role, content}）
class ContextMessage {
  final String role;
  final String content;
  final DateTime? timestamp;

  const ContextMessage({required this.role, required this.content, this.timestamp});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };

  factory ContextMessage.fromJson(Map<String, dynamic> json) {
    return ContextMessage(
      role: json['role'] as String? ?? '',
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }
}
