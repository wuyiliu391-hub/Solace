// 【对标来源：KouriChat-1.4.3.2 — src/handlers/message.py 消息队列处理】
// 1:1 转译自 KouriChat MessageHandler 类的消息队列与合并逻辑
// 参考文件：src/handlers/message.py:_add_to_message_queue()、_process_queue()

import "dart:async";
import "../models/chat_message.dart";
import "../models/app_config_data.dart";
import "llm_service.dart";

/// 消息处理器（对标 KouriChat MessageHandler）
/// 完整保留 KouriChat 的消息队列、合并、延迟处理逻辑
class MessageHandler {
  final LlmService llmService;
  final BehaviorSettings behaviorSettings;

  /// 消息队列（对标 KouriChat self.message_queues）
  final Map<String, List<_QueuedMessage>> _messageQueues = {};

  /// 队列定时器（对标 KouriChat self.queue_timers）
  final Map<String, Timer> _queueTimers = {};

  /// 队列锁（对标 KouriChat self.queue_lock）
  bool _locked = false;

  MessageHandler({
    required this.llmService,
    required this.behaviorSettings,
  });

  /// 添加消息到队列（对标 KouriChat _add_to_message_queue）
  Future<void> addToQueue({
    required String chatId,
    required String content,
    required String senderName,
    required String username,
    bool isGroup = false,
  }) async {
    // 等待锁释放
    while (_locked) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _locked = true;

    try {
      final queueKey = chatId;

      _messageQueues[queueKey] ??= [];
      _messageQueues[queueKey]!.add(_QueuedMessage(
        content: content,
        senderName: senderName,
        username: username,
        timestamp: DateTime.now(),
        isGroup: isGroup,
      ));

      // 重置定时器（对标 KouriChat queue_timer 重置逻辑）
      _queueTimers[queueKey]?.cancel();
      _queueTimers[queueKey] = Timer(
        Duration(seconds: behaviorSettings.messageQueue.timeout),
        () => _processQueue(chatId),
      );
    } finally {
      _locked = false;
    }
  }

  /// 处理消息队列（对标 KouriChat _process_queue）
  Future<void> _processQueue(String chatId) async {
    final queueKey = chatId;
    final messages = _messageQueues[queueKey];
    if (messages == null || messages.isEmpty) return;

    // 清空队列
    _messageQueues[queueKey] = [];
    _queueTimers[queueKey]?.cancel();
    _queueTimers.remove(queueKey);

    // 合并消息（对标 KouriChat 消息合并逻辑）
    final mergedContent = _mergeMessages(messages);
    final senderName = messages.last.senderName;
    final username = messages.last.username;

    // 调用 LLM 获取回复
    await _handleMessage(
      chatId: chatId,
      content: mergedContent,
      senderName: senderName,
      username: username,
      isGroup: messages.last.isGroup,
    );
  }

  /// 合并多条消息（对标 KouriChat 消息合并逻辑）
  String _mergeMessages(List<_QueuedMessage> messages) {
    if (messages.length == 1) return messages.first.content;

    // 按时间排序
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final buffer = StringBuffer();
    for (int i = 0; i < messages.length; i++) {
      if (i > 0) buffer.write('\n');
      buffer.write(messages[i].content);
    }
    return buffer.toString();
  }

  /// 处理单条消息（对标 KouriChat handle_message）
  Future<String> _handleMessage({
    required String chatId,
    required String content,
    required String senderName,
    required String username,
    bool isGroup = false,
  }) async {
    final response = await llmService.chat(
      userId: chatId,
      message: content,
      systemPrompt: '你正在和$username对话。',
    );

    if (response.error != null) {
      return '抱歉，我现在无法回复。';
    }

    return response.content;
  }

  /// 立即处理消息（不经过队列）
  Future<String> handleMessageImmediate({
    required String chatId,
    required String content,
    required String senderName,
    required String username,
    String? systemPrompt,
  }) async {
    final response = await llmService.chat(
      userId: chatId,
      message: content,
      systemPrompt: systemPrompt,
    );

    if (response.error != null) {
      return '抱歉，我现在无法回复。';
    }

    return response.content;
  }

  /// 清空聊天上下文
  void clearChatContext(String chatId) {
    llmService.clearContext(chatId);
    _messageQueues.remove(chatId);
    _queueTimers[chatId]?.cancel();
    _queueTimers.remove(chatId);
  }

  /// 获取队列中的消息数
  int getQueueLength(String chatId) {
    return _messageQueues[chatId]?.length ?? 0;
  }

  /// 销毁处理器
  void dispose() {
    for (final timer in _queueTimers.values) {
      timer.cancel();
    }
    _queueTimers.clear();
    _messageQueues.clear();
  }
}

/// 队列中的消息（对标 KouriChat queue_data）
class _QueuedMessage {
  final String content;
  final String senderName;
  final String username;
  final DateTime timestamp;
  final bool isGroup;

  const _QueuedMessage({
    required this.content,
    required this.senderName,
    required this.username,
    required this.timestamp,
    required this.isGroup,
  });
}

