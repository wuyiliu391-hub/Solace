// 性能优化 -- 耗电与老手机兼容
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/ai_character.dart';
import '../models/ai_letter.dart';
import '../models/chat_session.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import '../utils/message_sanitizer.dart';
import 'ai_letter_prompt_builder.dart';
import 'ai_service.dart';
import 'emotion_engine.dart';
import 'memory_engine.dart';
import 'reflection_engine.dart';
import 'ai_proactive_service.dart';
import 'inner_thought_service.dart';
import 'forum_service.dart';
import 'weather_service.dart';
import 'day_night_service.dart';
import 'social_scheduler_service.dart';
import 'world_engine.dart';
import 'wellbeing_service.dart';

/// 心跳服务 — AI 的"生命脉搏"
///
/// 借鉴 Shikigami Protocol 的 ASE（Autonomous Speech Engine）：
/// - 每 30-60 分钟执行一次"心跳"
/// - 心跳时调用反思引擎生成内心独白
/// - 如果紧迫度超过阈值，通过主动消息服务找用户
///
/// 与旧的定时消息系统的区别：
/// - 旧系统：cron 定时 → 到点就发 → 不管AI想不想
/// - 新系统：反思 → 评估紧迫度 → AI"自己决定"要不要说话
///
/// 生命周期：
/// - App 前台时：Timer 定期心跳
/// - App 后台时：依赖 WorkManager（如果可用）
/// - App 恢复前台时：立即执行一次心跳
class HeartbeatService {
  final LocalStorageRepository _storage;
  final EmotionEngine _emotionEngine;
  final MemoryEngine _memoryEngine;
  final ReflectionEngine _reflectionEngine;
  final AIProactiveService _proactiveService;
  // v10.0 新增
  InnerThoughtService? _innerThoughtService;
  ForumService? _forumService;
  WeatherService? _weatherService;
  DayNightService? _dayNightService;
  // 全生命周期数字生命世界 — WorldEngine 中枢
  WorldEngine? _worldEngine;

  /// 公开 WorldEngine 访问（UI 层通过此属性读取世界状态）
  WorldEngine? get worldEngine => _worldEngine;

  // v15.0 新增：新世界社交调度
  SocialSchedulerService? _socialScheduler;

  // 性能优化：合并为单个 Timer
  Timer? _heartbeatTimer;
  bool _isRunning = false;
  DateTime? _lastHeartbeat;
  DateTime? _lastUserInteraction; // 性能优化：追踪用户最后交互时间
  final _random = Random();

  // 每个角色的下次反思时间
  final Map<String, DateTime> _nextReflectionTime = {};

  // 防止多次心跳并发执行：WorldEngine tick / 社交调度等重型任务叠加
  // 会导致 SQLite 锁竞争、内存上涨，最终 UI 卡死。
  bool _heartbeatInProgress = false;

  // 性能优化：自适应心跳间隔
  // 活跃时 2 分钟，非活跃时 5 分钟
  static const Duration _activeInterval = Duration(minutes: 2);
  static const Duration _idleInterval = Duration(minutes: 5);
  static const Duration _idleThreshold = Duration(minutes: 10);

  /// 性能优化：用户交互时调用，标记活跃状态
  void notifyUserInteraction() {
    _lastUserInteraction = DateTime.now();
  }

  HeartbeatService(
    this._storage,
    this._emotionEngine,
    this._memoryEngine,
    this._reflectionEngine,
    this._proactiveService,
  );

  /// 注入 v10.0 新增服务
  void setV10Services({
    InnerThoughtService? innerThoughtService,
    ForumService? forumService,
    WeatherService? weatherService,
    DayNightService? dayNightService,
  }) {
    _innerThoughtService = innerThoughtService;
    _forumService = forumService;
    _weatherService = weatherService;
    _dayNightService = dayNightService;
  }

  /// 注入 v15.0 新世界社交调度服务
  void setSocialScheduler(SocialSchedulerService scheduler) {
    _socialScheduler = scheduler;
  }

  /// 注入 WorldEngine（全生命周期数字生命世界中枢）
  void setWorldEngine(WorldEngine engine) {
    _worldEngine = engine;
  }

  /// 启动心跳（App 进入前台时调用）
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // 注入情绪引擎到主动消息服务
    _proactiveService.setEmotionEngine(_emotionEngine);

    // 性能优化：使用自适应间隔启动心跳
    // _scheduleNextHeartbeat 已会根据 idle/active 状态选择 5min/2min 的首次触发，
    // 避免启动时立即执行重型心跳；同时删除额外的 5min Delay 防止重复调度。
    _scheduleNextHeartbeat();

    debugPrint('HeartbeatService: started');
  }

  /// 性能优化：根据用户活跃度自适应调度下一次心跳
  void _scheduleNextHeartbeat() {
    _heartbeatTimer?.cancel();
    final now = DateTime.now();
    final lastInteraction = _lastUserInteraction;
    final isIdle = lastInteraction == null ||
        now.difference(lastInteraction) > _idleThreshold;
    final interval = isIdle ? _idleInterval : _activeInterval;
    _heartbeatTimer = Timer(interval, () {
      if (_isRunning) {
        _onHeartbeat().then((_) => _scheduleNextHeartbeat());
      }
    });
  }

  /// 停止心跳（App 进入后台时调用）
  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isRunning = false;
    debugPrint('HeartbeatService: stopped');
  }

  /// 性能优化：销毁时释放所有资源
  void dispose() {
    stop();
    _nextReflectionTime.clear();
  }

  /// App 恢复前台时调用
  void onResume() {
    notifyUserInteraction(); // 性能优化：标记为活跃
    if (!_isRunning) {
      // start() 内部已经会调度下一次心跳，不要在这里再排一次。
      start();
      return;
    }

    // 已有心跳正在进行中，直接复用；避免并发导致 WorldEngine tick 叠加。
    if (_heartbeatInProgress) return;

    // 恢复前台不立刻执行重型心跳；超过 30 分钟未跳则 20 秒后补一次。
    // 这里只做“补课”，不重新调度；正常周期仍由 _scheduleNextHeartbeat 维护。
    final last = _lastHeartbeat;
    if (last == null || DateTime.now().difference(last).inMinutes >= 30) {
      Future.delayed(const Duration(seconds: 20), () {
        if (_isRunning && !_heartbeatInProgress) _onHeartbeat();
      });
    }
  }

  /// 核心心跳逻辑
  Future<void> _onHeartbeat() async {
    // 如果上一轮心跳还没完成（例如 LLM/SQLite 卡住），本轮直接跳过。
    // 这样可以避免重型任务并发堆积，是防止长时间使用后卡死的关键兜底。
    if (_heartbeatInProgress) {
      debugPrint('HeartbeatService: skipped concurrent heartbeat');
      return;
    }
    _heartbeatInProgress = true;

    try {
      _lastHeartbeat = DateTime.now();
      final userId = _storage.getString(PrefKeys.currentUserId);
      if (userId == null || userId.isEmpty) return;

      // 性能优化：只在需要时查询角色列表，避免每次心跳全量查询
      final characters = await _storage.getAllAICharacters();
      if (characters.isEmpty) return;

      // 老设备保护：每轮最多处理最近一个在线角色，避免多角色串行 LLM/DB 任务卡死。
      final onlineCharacters =
          characters.where((c) => c.isOnline).take(1).toList(growable: false);
      for (final character in onlineCharacters) {
        await _processCharacterHeartbeat(character, userId);
        // 让出事件循环，降低 UI 抢占
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // 记忆每日维护每天最多一次，并后台异步执行，不阻塞心跳。
      final decayKey = 'heartbeat_memory_maintenance_$todayStr';
      if (_storage.getBool(decayKey) != true) {
        await _storage.setBool(decayKey, true);
        // 性能优化：异步执行，不阻塞心跳主流程
        _memoryEngine.runDailyMaintenance(
          characterId: characters.first.id,
          userId: userId,
        );
      }

      // v10.0: 天气更新每小时最多一次。
      final hourKey = 'heartbeat_weather_${todayStr}_${now.hour}';
      if (_storage.getBool(hourKey) != true) {
        await _storage.setBool(hourKey, true);
        // 性能优化：异步执行天气更新
        _weatherService?.getCurrentWeather().then((weather) async {
          if (weather != null) {
            await _weatherService?.updateWeather(
                userId: userId, weather: weather);
            await _weatherService?.applyWeatherEmotion(
              characterId: characters.first.id,
              userId: userId,
              weather: weather,
            );
          }
        }).catchError((e) {
          debugPrint('HeartbeatService: weather error: $e');
        });
      }

      // v10.0: 昼夜情绪调整每天夜间最多一次。
      final nightKey = 'heartbeat_night_mood_$todayStr';
      final period = _dayNightService?.getCurrentPeriod();
      if (period != null &&
          period.period == TimePeriod.night &&
          _storage.getBool(nightKey) != true) {
        await _storage.setBool(nightKey, true);
        await _emotionEngine.adjustValence(
          characterId: characters.first.id,
          userId: userId,
          delta: 0.05,
        );
      }

      // 全生命周期数字生命世界：WorldEngine tick
      // 以前未 await，多个 tick 并发叠加也是长时间使用后卡死的主因。
      await _worldEngine?.tick();

      // v15.0: 新世界社交调度
      await _socialScheduler?.runSocialCycle();

      // 作息陪伴：每轮心跳检查一次（纯本地闸，不调 LLM，不上传任何数据）
      // aiSuggests: false  → 仅靠时间/使用时长规则判定，不依赖 AI 建议
      try {
        await WellbeingService().maybeLock(aiSuggests: false);
      } catch (e) {
        debugPrint('HeartbeatService: wellbeing check error: $e');
      }
    } catch (e) {
      debugPrint('HeartbeatService: error: $e');
    } finally {
      // 无论如何都要释放锁，否则后续心跳永远进不来。
      _heartbeatInProgress = false;
    }
  }

  /// 处理单个角色的心跳
  Future<void> _processCharacterHeartbeat(
      AICharacter character, String userId) async {
    final charKey = '${character.id}_$userId';

    // 检查是否到了反思时间
    final nextTime = _nextReflectionTime[charKey];
    if (nextTime != null && DateTime.now().isBefore(nextTime)) {
      return; // 还没到时间
    }

    // 执行反思
    final state = await _reflectionEngine.reflectWithState(
      character: character,
      userId: userId,
    );

    if (state == null) {
      // 反思失败，30分钟后再试
      _nextReflectionTime[charKey] =
          DateTime.now().add(const Duration(minutes: 30));
      return;
    }

    // 设置下次反思时间（由 LLM 决定间隔）
    _nextReflectionTime[charKey] =
        DateTime.now().add(Duration(seconds: state.nextReflectionIn));

    // 如果 AI 想说话，检查 ASE 阀门
    if (state.wantsToSpeak) {
      await _trySendMessage(character, userId, state);
    }

    // 人设进化改为聊天前台触发；心跳中不再全量读取消息，避免老设备卡死。
    // v10.0: AI 内心独白自动生成（复用反思引擎结果，异步不阻塞）
    _innerThoughtService?.generateAIFromReflection(
      characterId: character.id,
      userId: userId,
    );

    // v10.0: AI 日记发帖（低频，约每3次心跳发一次帖子）
    if (_random.nextInt(3) == 0) {
      _forumService?.generateAIPost(character: character, userId: userId);
    }

    // v14.0: 里程碑自动来信（低频后台检查，避免每次心跳重型查询）
    final letterCheckKey =
        'heartbeat_letter_check_${character.id}_${DateTime.now().toIso8601String().substring(0, 10)}';
    if (_storage.getBool(letterCheckKey) != true && _random.nextInt(4) == 0) {
      await _storage.setBool(letterCheckKey, true);
      await _checkAndSendMilestoneLetter(character, userId);
    }
  }

  /// v14.0: 里程碑自动来信
  ///
  /// 触发条件：
  /// - 亲密度升级（delta > 0）
  /// - 纪念日（7/30/100/365天）
  /// - 3天以上未聊天
  /// - 用户上次聊天情绪低落
  Future<void> _checkAndSendMilestoneLetter(
      AICharacter character, String userId) async {
    try {
      // 获取最近聊天会话
      final sessions = await _storage.getChatSessions(userId);
      ChatSession? targetSession;
      DateTime? earliestDate;
      for (final s in sessions) {
        if (s.aiCharacterId != character.id) continue;
        final at = s.lastMessageTime ?? s.updatedAt ?? s.createdAt;
        if (targetSession == null) {
          targetSession = s;
        } else {
          final bt = targetSession.lastMessageTime ??
              targetSession.updatedAt ??
              targetSession.createdAt;
          if (at.isAfter(bt)) targetSession = s;
        }
        if (earliestDate == null || s.createdAt.isBefore(earliestDate)) {
          earliestDate = s.createdAt;
        }
      }
      if (targetSession == null || earliestDate == null) return;

      final daysSince = DateTime.now().difference(earliestDate).inDays;
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // ── 检查今日是否已发过自动来信 ──
      final sentKey = 'milestone_letter_sent_${character.id}_$todayStr';
      if (_storage.getBool(sentKey) == true) return;

      // ── 判断触发条件 ──
      String? triggerType;
      String promptSuffix = '';

      // 条件1：纪念日（7/30/100/365天）
      const milestones = [7, 30, 100, 365];
      for (final m in milestones) {
        if (daysSince == m) {
          triggerType = 'milestone_$m';
          promptSuffix = '今天是你们认识的第$m天，请写一封纪念这$m天的信。';
          break;
        }
      }

      // 条件2：3天以上未聊天
      if (triggerType == null) {
        final lastMsgTime = targetSession.lastMessageTime;
        if (lastMsgTime != null) {
          final hoursSince = now.difference(lastMsgTime).inHours;
          if (hoursSince >= 72) {
            triggerType = 'miss';
            promptSuffix = '你已经好几天没和用户聊天了，写一封想TA的信。';
          }
        }
      }

      // 条件3：亲密度今日有提升
      if (triggerType == null) {
        final todayDelta = await _storage.getTodayIntimacyDelta();
        if (todayDelta > 0) {
          triggerType = 'intimacy_up';
          promptSuffix = '今天你们的关系更近了一步，请写一封开心的信。';
        }
      }

      // 条件4：用户上次聊天情绪低落（从最近消息的sentiment判断）
      if (triggerType == null) {
        final recentMsgs =
            await _storage.getChatMessages(targetSession.id, limit: 5);
        if (recentMsgs.isNotEmpty) {
          final lastMsg = recentMsgs.first;
          if (!lastMsg.isFromAI) {
            // 用简单关键词检测低落情绪
            final content = lastMsg.content;
            final sadWords = [
              '难过',
              '伤心',
              '哭',
              '不开心',
              '烦',
              '累',
              '崩溃',
              '孤独',
              '寂寞',
              '压力',
              '焦虑',
              '害怕',
              '担心'
            ];
            if (sadWords.any((w) => content.contains(w))) {
              triggerType = 'comfort';
              promptSuffix = '用户上次聊天时情绪不太好，请写一封安慰的信。';
            }
          }
        }
      }

      // 没有触发条件，跳过
      if (triggerType == null) return;

      // ── 获取上下文 ──
      final config = await _storage.getActiveAIConfig();
      if (config == null || config.apiKey.trim().isEmpty) return;

      final chatHistory =
          await _storage.getChatMessages(targetSession.id, limit: 20);
      final memories = await _storage.getMemories(
        characterId: character.id,
        userId: userId,
        limit: 30,
      );

      // 获取用户昵称
      final user = await _storage.getCurrentUser();
      final recipientName = user?.nickname ?? '你';
      final prompt = AILetterPromptBuilder.buildIncomingLetterPrompt(
        character: character,
        recipientName: recipientName,
        memories: memories,
        chatHistory: chatHistory,
        triggerInstruction: promptSuffix,
      );

      // ── 调用 LLM 生成来信 ──
      final content = MessageSanitizer.sanitizeForContent(
        await AIService(_storage).sendMessage(
          character: character,
          userId: userId,
          userMessage: prompt,
          chatHistory: chatHistory,
          memories: memories,
          intimacyLevel: targetSession.intimacyLevel,
          overrideMaxTokens: 8192, // 写信不限制长度
        ),
      );

      if (content.trim().isEmpty) return;

      // ── 保存来信 ──
      final letter = AILetter(
        id: 'letter_auto_${now.millisecondsSinceEpoch}',
        userId: userId,
        characterId: character.id,
        characterName: character.name,
        characterAvatar: character.avatarUrl,
        recipientName: recipientName,
        title: '给$recipientName的一封信',
        content: content,
        sourceChatId: targetSession.id,
        createdAt: now,
      );
      await _storage.saveAILetter(letter);

      // 标记今日已发送，防止重复
      await _storage.setBool(sentKey, true);

      debugPrint(
          'HeartbeatService: ${character.name} sent milestone letter ($triggerType, day $daysSince)');
    } catch (e) {
      debugPrint('HeartbeatService: milestone letter error: $e');
    }
  }

  /// 尝试发送主动消息（ASE 六阀门检查）
  Future<void> _trySendMessage(
    AICharacter character,
    String userId,
    ReflectionState state,
  ) async {
    // 检查用户是否关闭了主动消息
    final config = character.interactionConfig;
    if (config != null && !config.enableMomentInteraction) {
      debugPrint('HeartbeatService: ${character.name} 主动消息已关闭，跳过');
      return;
    }

    // 查找聊天会话
    final sessions = await _storage.getChatSessions(userId);
    ChatSession? session;
    for (final s in sessions) {
      if (s.aiCharacterId == character.id) {
        session = s;
        break;
      }
    }
    if (session == null) return;

    // 使用 ASE 六阀门检查（传入反思引擎的 urgency 作为优先值）
    final shouldSend = await _proactiveService.shouldSendByUrgency(
      character: character,
      userId: userId,
      session: session,
      reflectionUrgency: state.urgency, // 优先使用 LLM 判断的紧迫度
    );

    if (shouldSend) {
      // 生成并发送主动消息
      await _proactiveService.sendProactiveMessage(
        character: character,
        session: session,
        type: ProactiveMessageType.careReminder,
      );

      // 注意：不调用 markUserResponded！
      // 只有用户真正回复时才更新 lastInteractionTime。
      // AI 发消息不等于用户回复，错误更新会导致孤独度骤降→紧迫度骤降→
      // 然后慢慢回升→又发消息→又骤降的震荡循环。

      debugPrint(
          'HeartbeatService: ${character.name} sent proactive message (urgency=${state.urgency.toStringAsFixed(2)}, reason=${state.speakReason})');
    }
  }

  /// 获取心跳状态（调试用）
  Map<String, dynamic> getStatus() {
    return {
      'isRunning': _isRunning,
      'lastHeartbeat': _lastHeartbeat?.toIso8601String(),
      'nextReflectionTimes': _nextReflectionTime.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
    };
  }
}
