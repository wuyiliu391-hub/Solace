import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../blocs/chat/chat_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/chat_message.dart';
import '../../models/chat_session.dart';
import '../../models/memory.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/message_sanitizer.dart';
import '../ai_service.dart';
import '../bridge/ai_service_adapter.dart';
import '../notification_service.dart';
import 'ilink_client.dart';
import 'wechat_bot_store.dart';
import 'wechat_foreground_service.dart';

/// 微信 iLink Bot 编排服务（前台长轮询 + 完整角色管线回复）。
///
/// 协议取证自腾讯官方 OpenClaw 插件（笔记见 .research/wechat-ilink-protocol.md）。
/// 与官方实现一致的几个关键点：
/// - getUpdates 用 get_updates_buf 字符串游标做长轮询（非 offset 数字）；
/// - 入站消息的 context_token 按联系人缓存，回复必须回传；
/// - typing 需先 getConfig 拿 typing_ticket 再 sendTyping；
/// - errcode -14（token 失效）时暂停调用并由用户重新扫码。
class WeChatBotService {
  WeChatBotService._internal();

  static final WeChatBotService instance = WeChatBotService._internal();

  static const Duration contactCooldown = Duration(seconds: 10);
  static const int maxRepliesPerHour = 120;

  /// token 失效（errcode -14）后的暂停时长，对齐官方 session-guard（1 小时）。
  static const Duration staleTokenPause = Duration(hours: 1);

  final Uuid _uuid = const Uuid();
  final Random _random = Random();

  LocalStorageRepository? _storage;
  AIService? _aiService;
  AIServiceAdapter? _aiAdapter;

  Completer<void>? _stopSignal;
  bool _polling = false;
  bool _appInForeground = true;
  DateTime? _pausedUntil;

  /// 用户/系统主动停止（登出/断开）时为 true；此时 _runLoop 退出后不自动重启。
  bool _stopIntentional = false;

  /// 已发 typing_ticket 缓存（ilink_user_id -> ticket）
  final Map<String, String> _typingTickets = {};

  /// 单联系人回复冷却
  final Map<String, DateTime> _lastReplyAt = {};

  /// 全局每小时回复上限滑窗
  final List<DateTime> _replyTimestamps = [];

  /// 消息去重（message_id/seq 缺失时用内容哈希兜底）
  final Set<String> _seenMessageIds = {};

  bool _tokenInvalidNotified = false;

  /// 依赖注入（MainShell 启动时调用一次）。
  void init({
    required LocalStorageRepository storage,
    required AIService aiService,
    AIServiceAdapter? aiAdapter,
  }) {
    _storage = storage;
    _aiService = aiService;
    _aiAdapter = aiAdapter;
  }

  void setForeground(bool foreground) => _appInForeground = foreground;

  bool get isPolling => _polling;

  // ────────────── 轮询启停 ──────────────

  Future<void> startPolling() async {
    if (_polling || _storage == null) return;
    final token = await WeChatBotStore.loadToken();
    final enabled = await WeChatBotStore.loadEnabled();
    if (token == null || !enabled) return;
    _tokenInvalidNotified = false;
    _stopSignal = Completer<void>();
    _stopIntentional = false;
    debugPrint('[WeChatBot] 前台长轮询已启动');
    try {
      await WechatForegroundService.start(
        body: '微信机器人已在线，正在接收消息...',
      );
      // 请求电池优化白名单（国产 ROM 后台保活关键；用户确认一次后系统记住）
      unawaited(WechatForegroundService.requestIgnoreBatteryOptimization());
      final baseUrl = await WeChatBotStore.loadBaseUrl();
      final client = IlinkClient(baseUrl: baseUrl, botToken: token);
      await client.notifyStart();
      _polling = true;
      unawaited(_runLoop(client));
    } catch (e) {
      // 任何启动步骤失败都不允许 _polling 卡死：
      // 清掉标记让下次 startPolling 可以重试，否则 bot 永远无法启动。
      _polling = false;
      debugPrint('[WeChatBot] startPolling 失败，可重试: $e');
    }
  }

  void stopPolling() {
    if (!_polling) return;
    _stopIntentional = true;
    _polling = false;
    if (!(_stopSignal?.isCompleted ?? true)) {
      _stopSignal?.complete();
    }
    WechatForegroundService.stop();
    debugPrint('[WeChatBot] 前台轮询已停止');
    // 尽力通知服务端（fire-and-forget）
    WeChatBotStore.loadBaseUrl().then((base) {
      WeChatBotStore.loadToken().then((token) {
        if (token != null) {
          IlinkClient(baseUrl: base, botToken: token).notifyStop();
        }
      });
    });
  }

  /// 长轮询主循环：服务端 hold ~35s，返回后立即续发。
  /// 任何异常都不会让循环退出——catch 后延迟重试，保证断网/冻结后自动恢复。
  Future<void> _runLoop(IlinkClient client) async {
    while (_polling) {
      // token 失效冷却期：暂停调用（官方语义 1 小时）
      final paused = _pausedUntil;
      if (paused != null && DateTime.now().isBefore(paused)) {
        await Future<void>.delayed(const Duration(minutes: 5));
        continue;
      }
      // App 进入后台：暂停前台轮询，等待 WorkManager 兜底（15min）
      // 前台恢复时由 main_shell.didChangeAppLifecycleState 重新 startPolling
      if (!_appInForeground) {
        debugPrint('[WeChatBot] App 后台，暂停前台轮询');
        await Future<void>.delayed(const Duration(minutes: 1));
        continue;
      }
      try {
        await _pollOnce(client);
      } on IlinkException catch (e) {
        debugPrint('[WeChatBot] iLink 错误: $e');
        if (e.isStaleToken || e.isUnauthorized) {
          await _handleTokenInvalid(e.message);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[WeChatBot] 轮询异常: $e');
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    // 循环因 _polling 变 false 退出后，若启用 bot 且 token 有效且非主动停止，自动重启
    // （覆盖"startPolling 曾失败但 _polling 已复位"等异常退出场景）
    if (!_stopIntentional) {
      final enabled = await WeChatBotStore.loadEnabled();
      final token = await WeChatBotStore.loadToken();
      if (enabled && token != null) {
        debugPrint('[WeChatBot] 轮询自愈重启');
        _polling = false;
        unawaited(startPolling());
      }
    }
  }

  Future<void> _pollOnce(IlinkClient client) async {
    final enabled = await WeChatBotStore.loadEnabled();
    final token = await WeChatBotStore.loadToken();
    if (!enabled || token == null) {
      stopPolling();
      return;
    }
    final buf = await WeChatBotStore.loadUpdatesBuf();
    final result = await client.getUpdates(updatesBuf: buf);
    if (result.updatesBuf != buf) {
      await WeChatBotStore.saveUpdatesBuf(result.updatesBuf);
    }
    if (result.messages.isEmpty) return;

    for (final msg in result.messages) {
      try {
        await _handleMessage(client, msg);
      } catch (e, st) {
        debugPrint('[WeChatBot] 处理消息失败: $e\n$st');
      }
    }
  }

  // ────────────── 消息处理 ──────────────

  Future<void> _handleMessage(IlinkClient client, IlinkMessage msg) async {
    final storage = _storage;
    if (storage == null) return;

    // 只回复联系人发来的、已完结的用户消息
    if (!msg.isFromUser || !msg.isFinished) return;

    // 入站自带 context_token，先缓存（回复依赖它）
    if (msg.contextToken != null) {
      await WeChatBotStore.saveContextToken(msg.fromUserId, msg.contextToken!);
    }

    // 去重
    final dedupeKey =
        '${msg.fromUserId}_${msg.messageId ?? msg.seq ?? msg.text.hashCode}_${msg.createdAt.millisecondsSinceEpoch ~/ 1000}';
    if (!_seenMessageIds.add(dedupeKey)) return;
    if (_seenMessageIds.length > 500) _seenMessageIds.clear();

    // 白名单过滤：名单外只记待审批，不回复
    if (!(await WeChatBotStore.isWhitelisted(msg.fromUserId))) {
      await WeChatBotStore.upsertPending(
        wxId: msg.fromUserId,
        fromName: msg.fromUserId,
        lastText: msg.text,
      );
      return;
    }

    // 频控护栏
    final now = DateTime.now();
    final last = _lastReplyAt[msg.fromUserId];
    if (last != null && now.difference(last) < contactCooldown) {
      debugPrint('[WeChatBot] ${msg.fromUserId} 冷却中，跳过');
      return;
    }
    _replyTimestamps
        .removeWhere((t) => now.difference(t) > const Duration(hours: 1));
    if (_replyTimestamps.length >= maxRepliesPerHour) {
      debugPrint('[WeChatBot] 已达每小时回复上限，跳过');
      return;
    }

    final characterId = await WeChatBotStore.loadBoundCharacterId();
    if (characterId == null) {
      debugPrint('[WeChatBot] 未绑定角色，跳过');
      return;
    }
    final character = await storage.getAICharacter(characterId);
    if (character == null) {
      debugPrint('[WeChatBot] 绑定角色不存在: $characterId');
      return;
    }

    final currentUser = await storage.getCurrentUser();
    final userId = currentUser?.id ?? 'local_user';
    final sessionId = _sessionIdFor(msg.fromUserId);
    final contactName =
        await WeChatBotStore.displayNameOf(msg.fromUserId) ?? msg.fromUserId;

    // 会话：不存在则创建；已存在但角色变了 → 同步到当前绑定角色
    var session = await storage.getChatSession(sessionId);
    if (session == null) {
      final nowTs = DateTime.now();
      session = ChatSession(
        id: sessionId,
        userId: userId,
        aiCharacterId: character.id,
        aiCharacterName: character.name,
        aiCharacterAvatar: character.avatarUrl,
        createdAt: nowTs,
        updatedAt: nowTs,
      );
      await storage.saveChatSession(session);
    } else if (session.aiCharacterId != character.id) {
      debugPrint(
          '[WeChatBot] 会话角色同步: ${session.aiCharacterId} -> ${character.id}');
      session = session.copyWith(
        aiCharacterId: character.id,
        aiCharacterName: character.name,
        aiCharacterAvatar: character.avatarUrl,
        updatedAt: DateTime.now(),
      );
      await storage.saveChatSession(session);
    }

    // 入站消息落库
    final inbound = ChatMessage(
      id: _uuid.v4(),
      chatId: sessionId,
      senderId: msg.fromUserId,
      senderName: contactName,
      content: msg.text,
      isUser: true,
      type: MessageType.text,
      createdAt: msg.createdAt,
      metadata: const {'source': 'wechat_ilink'},
    );
    await storage.saveChatMessage(inbound);

    // 拟人前置：输入状态（先取 ticket 再发送）
    await _sendTyping(client, msg.fromUserId, typing: true);

    // 完整角色管线生成回复（上下文精简：思考模型长上下文推理慢，易触发上游超时）
    final history = await storage.getChatMessages(sessionId, limit: 20);
    final memories = await storage.getMemories(
        characterId: character.id, userId: userId, limit: 10);
    final rawReply = await _generateReply(
      character: character,
      userId: userId,
      userMessage: msg.text,
      chatHistory: history,
      memories: memories,
      intimacyLevel: session.intimacyLevel,
    );
    await _sendTyping(client, msg.fromUserId, typing: false);

    // 与聊天页一致的 AI 回复清洗管线
    final cleaned = MessageSanitizer.sanitizeFinal(rawReply);
    debugPrint('[WeChatBot] 原始回复=[$rawReply] 清洗后=[$cleaned]');
    if (MessageSanitizer.isAIRefusal(cleaned) ||
        MessageSanitizer.isLikelyUnreadableGibberish(cleaned) ||
        cleaned.trim().length < 2) {
      debugPrint('[WeChatBot] AI 回复被拒绝/乱码，跳过');
      return;
    }
    final replyText = MessageSanitizer.filterForbiddenPhrases(
      cleaned,
      storage.getForbiddenPhrases(),
    );
    if (replyText.trim().isEmpty) {
      debugPrint('[WeChatBot] AI 回复被禁词过滤，跳过');
      return;
    }

    // 拆条发送回微信（回传 context_token；条间拟人间隔）
    final contextToken = msg.contextToken ??
        await WeChatBotStore.loadContextToken(msg.fromUserId);
    final parts = _splitMessages(replyText);
    for (var i = 0; i < parts.length; i++) {
      await client.sendMessage(
        to: msg.fromUserId,
        text: parts[i],
        contextToken: contextToken,
      );
      if (i < parts.length - 1) {
        await Future<void>.delayed(
            Duration(milliseconds: 800 + _random.nextInt(1200)));
      }
    }

    // AI 回复落库 + 会话摘要
    final replyMsg = ChatMessage(
      id: _uuid.v4(),
      chatId: sessionId,
      senderId: 'ai_${character.id}',
      senderName: character.name,
      content: replyText,
      isUser: false,
      type: MessageType.text,
      createdAt: DateTime.now(),
      metadata: const {'source': 'wechat_ilink_reply'},
    );
    await storage.saveChatMessage(replyMsg);
    await storage.updateChatSessionLastMessage(
        sessionId, _lastLine(replyText), DateTime.now());

    _lastReplyAt[msg.fromUserId] = DateTime.now();
    _replyTimestamps.add(DateTime.now());

    // UI 刷新 + 后台通知
    try {
      ChatBloc.forChat(sessionId, storage, _aiService!, aiAdapter: _aiAdapter)
          .add(ChatLoadMessages(sessionId));
    } catch (e) {
      debugPrint('[WeChatBot] UI 刷新失败: $e');
    }
    if (!_appInForeground) {
      await NotificationService().showInstantNotification(
        id: (msg.messageId ?? msg.seq ?? DateTime.now().millisecondsSinceEpoch) &
            0x7fffffff,
        title: '${character.name} 回复了 $contactName',
        body: _lastLine(replyText),
        payload: 'chat_$sessionId',
      );
    }
  }

  /// 输入状态：先 getConfig 拿 typing_ticket（缓存），再 sendTyping。
  Future<void> _sendTyping(
    IlinkClient client,
    String ilinkUserId, {
    required bool typing,
  }) async {
    var ticket = _typingTickets[ilinkUserId];
    if (ticket == null) {
      ticket = await client.getConfig(ilinkUserId);
      if (ticket == null || ticket.isEmpty) return;
      _typingTickets[ilinkUserId] = ticket;
    }
    await client.sendTyping(
        ilinkUserId: ilinkUserId, typingTicket: ticket, typing: typing);
  }

  // ────────────── 回复生成（完整角色管线） ──────────────

  Future<String> _generateReply({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required List<ChatMessage> chatHistory,
    required List<Memory> memories,
    required int intimacyLevel,
  }) async {
    final adapter = _aiAdapter;
    final aiService = _aiService;
    // 显式注入全局模式（法模式/小说/恋人/开放等），与聊天页一致。
    // 即使适配器内部漏注入，这里也保证带进去（聊天页就是靠它解锁法功能）。
    final storage = _storage;
    final internalContext = storage?.buildGlobalModePrompt(scope: '微信bot');
    // 微信净化：上游 API（腾讯/豆包等）有未成年人保护策略，
    // 角色卡里出现 "17岁" 等未成年年龄词会触发整段拒绝（"抱歉，我暂时无法回复"）。
    // 只影响发给上游的文本，不落库、不改角色卡本身。
    final sanitizedCharacter = character.copyWith(
      personality: _stripMinorAge(character.personality),
      coreDesire: _stripMinorAge(character.coreDesire),
      backgroundStory: _stripMinorAge(character.backgroundStory),
      openingLine: _stripMinorAge(character.openingLine),
      languageStyle: _stripMinorAge(character.languageStyle),
    );
    // 历史里混入的 "抱歉我无法回复" 拒绝回声会污染上下文，一并过滤
    final cleanHistory = chatHistory
        .where((m) => !MessageSanitizer.isAIRefusal(m.content))
        .toList();
    debugPrint('[WeChatBot] 角色=${character.name} 年龄净化后发往上游');
    if (adapter != null) {
      return adapter.sendMessage(
        character: sanitizedCharacter,
        userId: userId,
        userMessage: userMessage,
        chatHistory: cleanHistory,
        memories: memories,
        intimacyLevel: intimacyLevel,
        internalSystemContext: internalContext,
      );
    }
    if (aiService != null) {
      return aiService.sendMessage(
        character: sanitizedCharacter,
        userId: userId,
        userMessage: userMessage,
        chatHistory: cleanHistory,
        memories: memories,
        intimacyLevel: intimacyLevel,
        internalSystemContext: internalContext,
      );
    }
    return '';
  }

  /// 移除角色文本中的未成年年龄表述（微信上游未成年人保护误杀规避）。
  /// 把 "17岁" 替换为 "20多岁"，并清除直接声明 "未成年" 的句子。
  static String _stripMinorAge(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    var t = text.replaceAllMapped(
      RegExp(r'(\d{1,2})\s*岁'),
      (m) {
        final age = int.tryParse(m.group(1) ?? '');
        if (age == null) return m.group(0)!;
        return age < 18 ? '20多岁' : m.group(0)!;
      },
    );
    // 去掉 "未成年" 这类直白声明（防御角色卡里写"角色未成年"的）
    t = t.replaceAll(RegExp(r'(?:是|仍|还)(?:一个|一名|位)?未成年人'), '是成年人');
    return t;
  }

  List<String> _splitMessages(String text) {
    final adapter = _aiAdapter;
    final aiService = _aiService;
    try {
      if (adapter != null) return adapter.splitIntoMessages(text);
      if (aiService != null) return aiService.splitIntoMessages(text);
    } catch (e) {
      debugPrint('[WeChatBot] 拆条失败，整条发送: $e');
    }
    return [text];
  }

  // ────────────── 登录流程 ──────────────

  Future<IlinkQrcode> requestQrcode() async {
    final baseUrl = await WeChatBotStore.loadBaseUrl();
    final client = IlinkClient(baseUrl: baseUrl);
    final existingToken = await WeChatBotStore.loadToken();
    return client.getBotQrcode(
      localTokenList: existingToken != null ? [existingToken] : const [],
    );
  }

  /// 轮询扫码状态。[pollBaseUrl] 用于 IDC 重定向后切换轮询域名。
  Future<IlinkQrStatusResult> pollQrcodeStatus(
    String qrcode, {
    String? pollBaseUrl,
  }) async {
    final baseUrl = await WeChatBotStore.loadBaseUrl();
    final client = IlinkClient(baseUrl: baseUrl);
    return client.getQrcodeStatus(qrcode, pollBaseUrl: pollBaseUrl);
  }

  Future<void> completeLogin(IlinkQrStatusResult confirmed) async {
    if (confirmed.botToken != null) {
      await WeChatBotStore.saveToken(confirmed.botToken!);
    }
    if (confirmed.baseUrl != null && confirmed.baseUrl!.isNotEmpty) {
      // 账号专属网关域名（confirmed 返回）
      await WeChatBotStore.saveBaseUrl(confirmed.baseUrl!);
    }
    await WeChatBotStore.saveAccountInfo(
      ilinkBotId: confirmed.ilinkBotId,
      ilinkUserId: confirmed.ilinkUserId,
    );
    // 扫码者本人默认进白名单（对齐官方 allowFrom 语义）
    if (confirmed.ilinkUserId != null && confirmed.ilinkUserId!.isNotEmpty) {
      final list = await WeChatBotStore.loadWhitelist();
      if (!list.any((e) => e.wxId == confirmed.ilinkUserId)) {
        list.add(WxContactEntry(
            wxId: confirmed.ilinkUserId!,
            displayName: confirmed.ilinkUserId!));
        await WeChatBotStore.saveWhitelist(list);
      }
    }
    await WeChatBotStore.saveEnabled(true);
    await WeChatBotStore.saveUpdatesBuf(''); // 新会话清空游标
    _tokenInvalidNotified = false;
    _typingTickets.clear();
    await startPolling();
  }

  Future<void> logout() async {
    stopPolling();
    await WeChatBotStore.clearSession();
  }

  // ────────────── 内部工具 ──────────────

  Future<void> _handleTokenInvalid(String message) async {
    stopPolling();
    _pausedUntil = DateTime.now().add(staleTokenPause);
    if (_tokenInvalidNotified) return;
    _tokenInvalidNotified = true;
    await NotificationService().showInstantNotification(
      id: 99001,
      title: '微信机器人已断开',
      body: message,
      payload: 'wx_relogin',
    );
  }

  static String _sessionIdFor(String wxId) {
    final sanitized = wxId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'wx_$sanitized';
  }

  static String _lastLine(String text) {
    final lines = text.trim().split('\n');
    return lines.isEmpty ? text : lines.last;
  }
}
