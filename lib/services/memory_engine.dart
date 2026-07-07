import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/bt_agent_action.dart';
import '../models/memory.dart';
import '../models/chat_message.dart';
import '../models/ai_character.dart';
import '../repositories/local_storage_repository.dart';
import '../repositories/database_service.dart';
import '../config/constants.dart';
import '../utils/message_sanitizer.dart';
import '../utils/response_decoder.dart';

/// 记忆引擎 — 解决AI"假人感"的核心组件
///
/// 负责：
/// 1. 从对话中自动提取关键记忆
/// 2. 维护结构化的"关系档案"
/// 3. 智能检索相关记忆融入对话
class MemoryRebuildResult {
  final int scannedSessions;
  final int scannedMessages;
  final int savedMemories;
  final int skippedBatches;
  final int failedBatches;
  final List<String> errors;

  const MemoryRebuildResult({
    required this.scannedSessions,
    required this.scannedMessages,
    required this.savedMemories,
    required this.skippedBatches,
    required this.failedBatches,
    this.errors = const [],
  });

  bool get hasHistory => scannedSessions > 0 && scannedMessages > 0;
  bool get isSuccess => hasHistory && failedBatches == 0;
  bool get hasNewMemories => savedMemories > 0;

  String get feedbackMessage {
    if (!hasHistory) {
      return '没有找到该角色的历史聊天记录，无法重建记忆。';
    }
    final buffer = StringBuffer()
      ..write('已扫描 $scannedSessions 个会话、$scannedMessages 条历史消息。');
    if (savedMemories > 0) {
      buffer.write('新增 $savedMemories 条记忆。');
    } else {
      buffer.write('未新增记忆，可能历史内容已在记忆库中或没有可提取信息。');
    }
    if (failedBatches > 0) {
      buffer.write('有 $failedBatches 批处理失败。');
    }
    // 展示所有提示（含批次上限等非失败信息）
    if (errors.isNotEmpty) {
      buffer.write(errors.first);
    }
    return buffer.toString();
  }
}

/// 重建断点数据 — 每批处理后回调，由调用方持久化
class RebuildCheckpointData {
  final String characterId;
  final String userId;
  final int sessionIndex;
  final List<String> sessionIds;
  final int dbOffset;
  final int processedMessages;
  final int scannedMessages;
  final int totalBatches;
  final int skippedBatches;
  final int failedBatches;
  final int beforeMemoryCount;

  const RebuildCheckpointData({
    required this.characterId,
    required this.userId,
    required this.sessionIndex,
    required this.sessionIds,
    required this.dbOffset,
    required this.processedMessages,
    required this.scannedMessages,
    required this.totalBatches,
    required this.skippedBatches,
    required this.failedBatches,
    required this.beforeMemoryCount,
  });
}

class MemoryEngine {
  final LocalStorageRepository _storage;

  MemoryEngine(this._storage);

  bool _isBtContextPolluted(String text) => looksLikeBtAgentPayload(text);

  String _stripBtContextPollution(String text) {
    return stripBtAgentPayloads(
      MessageSanitizer.sanitizeFinal(text),
      preserveVisibleText: true,
    ).trim();
  }

  // ===================== 统一记忆注入（核心重构） =====================

  /// 一体化构建记忆 prompt — 消除冗余，控制 token 预算
  ///
  /// 合并了原先 7 个独立段落为 3 个清晰层次：
  /// 1. 永久记忆档案（rolling summary）
  /// 2. 最近状态（防止重复询问）
  /// 3. 相关记忆（按当前消息相关性精选）
  ///
  /// 总预算约 500 tokens
  Future<String> buildConsolidatedMemoryPrompt({
    required AICharacter character,
    required String userId,
    required String currentMessage,
    bool pureAiMode = false,
    String memoryMode = 'full',
    bool includeSocial = false,
  }) async {
    if (memoryMode == 'off') return '';

    final isTokenSaver = memoryMode == 'token_saver';
    final buffer = StringBuffer();
    int tokenBudget = isTokenSaver ? 220 : 500;
    final maxRelevantMemories = isTokenSaver ? 3 : 8;
    final fallbackLimit = isTokenSaver ? 3 : Limit.memoriesFallback;
    final seen = <String>{}; // 内容去重集合

    // ① 永久记忆档案 — 最高优先级，不计入预算（因为它是压缩过的）
    try {
      final rollingSummary = await getRollingSummary(
        characterId: character.id,
        userId: userId,
      );
      if (rollingSummary != null &&
          rollingSummary.isNotEmpty &&
          !MessageSanitizer.isLikelyUnreadableGibberish(rollingSummary) &&
          !_isBtContextPolluted(rollingSummary)) {
        final sanitizedSummary = _stripBtContextPollution(rollingSummary);
        if (sanitizedSummary.isNotEmpty) {
          final summary = isTokenSaver && sanitizedSummary.length > 300
              ? '${sanitizedSummary.substring(0, 300)}……'
              : sanitizedSummary;
          buffer.writeln(pureAiMode ? '\n【背景事实摘要】' : '\n【永久记忆档案】');
          buffer.writeln(summary);
          buffer.writeln();
        }
      }
    } catch (e) {
      debugPrint('MemoryEngine: rolling summary failed: $e');
    }

    // ② 最近状态 — 防止重复询问，小预算
    try {
      final states = await _getRecentStatesCompact(
        characterId: character.id,
        userId: userId,
      );
      if (states.isNotEmpty) {
        buffer.writeln(pureAiMode ? '【近期客观状态】' : '【最近状态 — 请勿重复询问】');
        buffer.writeln(states);
        buffer.writeln();
        tokenBudget -= 60;
      }
    } catch (e) {
      debugPrint('MemoryEngine: recent states failed: $e');
    }

    // ③ 相关记忆 — 按热度加权精选，受预算控制
    //
    // v2 艾宾浩斯热度分层：
    // - 热记忆（weight > 1.0）：完整注入
    // - 温记忆（0.5 ≤ weight ≤ 1.0）：注入摘要
    // - 冷记忆（weight < 0.5）：不注入
    //
    // 被注入的记忆会被标记为"已回忆"，权重 +0.01（用进废退）
    try {
      final allMemories = await _storage.getPromptSafeMemories(
        characterId: character.id,
        userId: userId,
        limit: Limit.memoryPromptCap,
      );

      // 过滤掉滚动摘要、过时状态、已合并的记忆、乱码污染记忆、BT 指令污染记忆
      final filtered = allMemories.where((m) =>
          m.type != MemoryType.rollingSummary &&
          !m.keywords.contains('__merged') &&
          !MessageSanitizer.isLikelyUnreadableGibberish(m.content) &&
          !_isBtContextPolluted(m.content) &&
          !(m.type == MemoryType.state &&
              DateTime.now().difference(m.createdAt).inHours >= 12));

      if (filtered.isNotEmpty) {
        // 按热度加权评分
        final scored = _scoreMemories(filtered.toList(), currentMessage);
        scored.sort((a, b) => b.$2.compareTo(a.$2));

        final selected = <String>[];
        final recalledIds = <String>[]; // 跟踪被注入的记忆ID
        int usedTokens = 0;

        for (final (memory, score) in scored) {
          final keywordMatched = _memoryMatchesTopic(memory, currentMessage);
          // 冷记忆默认跳过；但如果本轮话题命中关键词/内容，必须允许唤醒。
          if (memory.weight < 0.5 && !memory.pinned && !keywordMatched) {
            continue;
          }

          final content = _formatMemoryLine(memory);
          if (content == null) continue;
          // 内容去重：检查是否和已选内容高度重叠
          if (_isContentDuplicate(content, seen)) continue;
          final estTokens = content.length ~/ 2; // 粗估中文 token
          if (usedTokens + estTokens > tokenBudget && selected.isNotEmpty) {
            if (!keywordMatched || score < 8) break;
          }
          selected.add(content);
          seen.add(content);
          usedTokens += estTokens;
          recalledIds.add(memory.id); // 标记为已回忆
          if (selected.length >= maxRelevantMemories && !keywordMatched) break;
        }

        if (selected.isNotEmpty) {
          buffer
              .writeln(pureAiMode ? '【客观参考信息】' : '【${character.name}记得关于你的事情】');
          for (final line in selected) {
            buffer.writeln(line);
          }
          buffer.writeln();
        }

        // 异步标记被回忆的记忆（不阻塞 prompt 构建）
        if (recalledIds.isNotEmpty) {
          markRecalled(
            characterId: character.id,
            userId: userId,
            recalledMemoryIds: recalledIds,
          );
        }
      }
    } catch (e) {
      debugPrint('MemoryEngine: relevant memories failed: $e');
      // fallback：直接罗列最近记忆
      try {
        final fallback = await _storage.getMemories(
          characterId: character.id,
          userId: userId,
          limit: fallbackLimit,
        );
        final safeFallback = fallback
            .where((m) =>
                !MessageSanitizer.isLikelyUnreadableGibberish(m.content) &&
                !_isBtContextPolluted(m.content))
            .toList();
        if (safeFallback.isNotEmpty) {
          buffer
              .writeln(pureAiMode ? '【客观参考信息】' : '【${character.name}记得关于你的事情】');
          for (final m in safeFallback) {
            buffer.writeln('- ${m.content}');
          }
        }
      } catch (e) {
        debugPrint('Error: $e');
      }
    }

    // ④ 社交记忆 — 仅在显式请求时注入
    if (includeSocial) {
      try {
        final socialMemories = await loadSocialMemories(character.id);
        if (socialMemories.isNotEmpty) {
          buffer.writeln('\n【社交记忆】');
          for (final m in socialMemories.take(20)) {
            buffer.writeln('- ${m.content}');
          }
        }
      } catch (e) {
        debugPrint('MemoryEngine: social memories failed: $e');
      }
    }

    return buffer.toString();
  }

  // ===================== 双区记忆（社交记忆） =====================

  /// Load private (user-character) memories for [characterId].
  /// These are the one-on-one interaction memories between the character and user.
  Future<List<Memory>> loadPrivateMemories(String characterId, String userId) async {
    final allMemories = await _storage.getMemories(characterId: characterId, userId: userId);
    // Filter to only conversation-type and reflection-type memories
    // (exclude any social-type if they exist in the main table)
    return allMemories.where((m) =>
      m.type == MemoryType.conversation ||
      m.type == MemoryType.reflection ||
      m.type == MemoryType.milestone ||
      m.type == MemoryType.emotion ||
      m.type == MemoryType.preference ||
      m.type == MemoryType.state ||
      m.type == MemoryType.rollingSummary
    ).toList();
  }

  /// Load social (AI-to-AI) memories for [characterId].
  /// These are interaction records between this character and other AI characters.
  Future<List<Memory>> loadSocialMemories(String characterId) async {
    try {
      final db = await DatabaseService.instance.database;

      // 确保表存在（兼容旧数据库）
      await _ensureSocialMemoriesTable(db);

      final rows = await db.query(
        'social_memories',
        where: 'characterId = ?',
        whereArgs: [characterId],
        orderBy: 'timestamp DESC',
        limit: 100,
      );
      return rows.map((row) => Memory(
        id: row['id'] as String,
        characterId: row['characterId'] as String,
        userId: row['targetCharacterId'] as String, // reuse userId field for target
        type: MemoryType.conversation,
        content: row['content'] as String? ?? '',
        keywords: (row['keywords'] as String?)?.isNotEmpty == true
            ? (row['keywords'] as String).split(',').where((k) => k.isNotEmpty).toList()
            : [],
        createdAt: DateTime.tryParse(row['timestamp'] as String? ?? '') ?? DateTime.now(),
        weight: (row['weight'] as num?)?.toDouble() ?? 1.0,
        pinned: (row['pinned'] as int?) == 1,
      )).toList();
    } catch (e) {
      debugPrint('MemoryEngine: loadSocialMemories failed — $e');
      return [];
    }
  }

  /// Save a social interaction memory.
  Future<void> saveSocialMemory({
    required String characterId,
    required String targetCharacterId,
    required String interactionType,
    required String content,
    String emotionTag = '',
    String importance = 'normal',
    List<String> keywords = const [],
  }) async {
    try {
      final db = await DatabaseService.instance.database;

      // 确保表存在（兼容旧数据库）
      await _ensureSocialMemoriesTable(db);

      await db.insert('social_memories', {
        'id': const Uuid().v4(),
        'characterId': characterId,
        'targetCharacterId': targetCharacterId,
        'interactionType': interactionType,
        'content': content,
        'emotionTag': emotionTag,
        'importance': importance,
        'keywords': jsonEncode(keywords),
        'timestamp': DateTime.now().toIso8601String(),
        'weight': 1.0,
        'pinned': 0,
      });
    } catch (e) {
      debugPrint('MemoryEngine: saveSocialMemory failed — $e');
    }
  }

  /// 确保 social_memories 表存在
  Future<void> _ensureSocialMemoriesTable(Database db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS social_memories (
          id TEXT PRIMARY KEY,
          characterId TEXT NOT NULL,
          targetCharacterId TEXT NOT NULL,
          interactionType TEXT DEFAULT 'chat',
          content TEXT DEFAULT '',
          emotionTag TEXT DEFAULT '',
          importance TEXT DEFAULT 'normal',
          keywords TEXT DEFAULT '[]',
          timestamp TEXT NOT NULL,
          weight REAL DEFAULT 1.0,
          pinned INTEGER DEFAULT 0,
          lastRecalledAt TEXT
        )
      ''');
    } catch (_) {}
  }

  /// 评分记忆与当前消息的相关性（v2 艾宾浩斯热度加权）
  ///
  /// 借鉴 Shikigami 的评分公式：
  /// heat = weight × 0.7 + recency × 0.3
  ///
  /// 其中：
  /// - weight: 记忆的热度权重（0.0~2.0），被回忆时增强，每天衰减
  /// - recency: 时效性（越近越重要），对数衰减
  ///
  /// 额外加分：
  /// - 状态记忆：12小时内额外加分
  /// - 关键词匹配：每匹配一个 +2
  /// - 重要性等级：按等级加分
  List<(Memory, double)> _scoreMemories(
      List<Memory> memories, String currentMessage) {
    final topicKeywords = _extractKeywords(currentMessage, maxKeywords: 24);
    final now = DateTime.now();

    return memories.map((memory) {
      // ── 热度核心：weight × 0.7 + recency × 0.3 ──

      // weight 分数（归一化到 0~10）
      final weightScore = (memory.weight / 2.0) * 10;

      // recency 分数：对数衰减，1/(1+ln(hours+1))
      final hoursAgo = now.difference(memory.createdAt).inHours;
      final recencyScore = 1.0 / (1.0 + log(hoursAgo + 1)) * 10;

      var score = weightScore * 0.7 + recencyScore * 0.3;

      // 重要性等级
      score += memory.importance.index.toDouble();

      // 状态记忆加分（12小时内）
      if (memory.type == MemoryType.state && hoursAgo < 12) {
        score += hoursAgo < 4 ? 5 : (hoursAgo < 8 ? 3 : 1.5);
      }

      // 当前消息关键词匹配
      for (final k in topicKeywords) {
        if (memory.content.contains(k)) score += 2;
        if (memory.keywords.any((mk) => mk.contains(k) || k.contains(mk))) {
          score += 2;
        }
      }

      return (memory, score);
    }).toList();
  }

  bool _memoryMatchesTopic(Memory memory, String currentMessage) {
    final topicKeywords = _extractKeywords(currentMessage, maxKeywords: 24);
    if (topicKeywords.isEmpty) return false;
    final content = memory.content.toLowerCase();
    final memoryKeywords = memory.keywords.map((k) => k.toLowerCase()).toList();
    for (final raw in topicKeywords) {
      final k = raw.toLowerCase();
      if (k.length < 2) continue;
      if (content.contains(k)) return true;
      if (memoryKeywords.any((mk) => mk.contains(k) || k.contains(mk))) {
        return true;
      }
    }
    return false;
  }

  /// 格式化单条记忆为 prompt 行
  String? _formatMemoryLine(Memory memory) {
    if (_isBtContextPolluted(memory.content)) return null;
    final prefix = switch (memory.type) {
      MemoryType.preference => '喜好',
      MemoryType.milestone => '经历',
      MemoryType.emotion => '心情',
      MemoryType.state => '状态',
      MemoryType.reflection => '回顾',
      MemoryType.conversation => '对话',
      MemoryType.rollingSummary => null,
    };
    if (prefix == null) return null;
    return '$prefix: ${memory.content}';
  }

  /// 检查内容是否与已选内容高度重复
  bool _isContentDuplicate(String content, Set<String> existing) {
    for (final e in existing) {
      // 简单重叠检测：一个包含另一个，或共享超过 60% 的字符
      if (e.contains(content) || content.contains(e)) return true;
      final overlap = _charOverlapRatio(content, e);
      if (overlap > 0.6) return true;
    }
    return false;
  }

  double _charOverlapRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final setA = a.split('').toSet();
    final setB = b.split('').toSet();
    final intersection = setA.intersection(setB).length;
    return intersection / max(setA.length, setB.length);
  }

  /// 获取最近状态（紧凑版，只返回一行）
  Future<String> _getRecentStatesCompact({
    required String characterId,
    required String userId,
  }) async {
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: 30,
    );

    final now = DateTime.now();
    final recentStates = memories
        .where((m) =>
            m.type == MemoryType.state &&
            now.difference(m.createdAt).inHours < 12)
        .toList();

    if (recentStates.isEmpty) return '';

    return recentStates.map((s) {
      final hours = now.difference(s.createdAt).inHours;
      final label = hours < 1
          ? '刚刚'
          : hours < 6
              ? '$hours小时前'
              : '今天';
      return '· [$label] ${s.content}';
    }).join('\n');
  }

  // ===================== 记忆老化清理 =====================

  /// 清理过时记忆，防止记忆表无限膨胀
  ///
  /// 规则：
  /// - state 类型：超过 24 小时删除
  /// - reflection/conversation：长期留存，仅清理 trivial 噪声
  /// - 低重要性记忆：超过 30 天删除
  Future<int> cleanupStaleMemories({
    required String characterId,
    required String userId,
  }) async {
    final allMemories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: Limit.memoryMaintenanceCap,
    );

    final now = DateTime.now();
    int deletedCount = 0;

    for (final memory in allMemories) {
      final age = now.difference(memory.createdAt);

      bool shouldDelete = false;

      switch (memory.type) {
        case MemoryType.state:
          shouldDelete = age.inHours > 24;
        case MemoryType.reflection:
          shouldDelete =
              memory.importance == MemoryImportance.trivial && age.inDays > 30;
        case MemoryType.conversation:
          shouldDelete =
              memory.importance == MemoryImportance.trivial && age.inDays > 30;
        case MemoryType.rollingSummary:
          // 永不自动删除
          shouldDelete = false;
        case MemoryType.preference:
        case MemoryType.milestone:
        case MemoryType.emotion:
          // 低重要性且超过 30 天
          shouldDelete =
              memory.importance == MemoryImportance.trivial && age.inDays > 30;
      }

      if (shouldDelete) {
        await _storage.deleteMemory(memory.id);
        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      debugPrint('MemoryEngine: cleaned up $deletedCount stale memories');
    }
    return deletedCount;
  }

  /// 检测并移除矛盾记忆
  ///
  /// 例如：旧记忆"喜欢火锅" vs 新记忆"不太想吃火锅" → 删除旧的
  Future<void> resolveContradictions({
    required String characterId,
    required String userId,
  }) async {
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: 50,
    );

    // 按类型分组，只检查 preference 和 emotion
    final prefs =
        memories.where((m) => m.type == MemoryType.preference).toList();
    final emotions =
        memories.where((m) => m.type == MemoryType.emotion).toList();

    // 检查 preference 内部矛盾
    for (int i = 0; i < prefs.length; i++) {
      for (int j = i + 1; j < prefs.length; j++) {
        if (_areContradictory(prefs[i].content, prefs[j].content)) {
          // 删除较旧的
          final older = prefs[i].createdAt.isBefore(prefs[j].createdAt)
              ? prefs[i]
              : prefs[j];
          await _storage.deleteMemory(older.id);
          debugPrint(
              'MemoryEngine: resolved contradiction, deleted: ${older.content}');
        }
      }
    }

    // 检查 emotion 内部矛盾
    for (int i = 0; i < emotions.length; i++) {
      for (int j = i + 1; j < emotions.length; j++) {
        if (_areContradictory(emotions[i].content, emotions[j].content)) {
          final older = emotions[i].createdAt.isBefore(emotions[j].createdAt)
              ? emotions[i]
              : emotions[j];
          await _storage.deleteMemory(older.id);
        }
      }
    }
  }

  /// 简单矛盾检测
  bool _areContradictory(String a, String b) {
    // 提取核心名词（去掉前缀如"饮食："）
    final coreA = a.replaceFirst(RegExp(r'^[^：]+：'), '');
    final coreB = b.replaceFirst(RegExp(r'^[^：]+：'), '');

    // 共享关键词（同一个话题）
    final keywordsA = _extractKeywords(coreA);
    final keywordsB = _extractKeywords(coreB);
    final shared = keywordsA.where((k) => keywordsB.contains(k)).toList();
    if (shared.isEmpty) return false;

    // 反义词检测
    final negations = [
      ['喜欢', '不喜欢'],
      ['喜欢', '讨厌'],
      ['爱吃', '不爱吃'],
      ['开心', '难过'],
      ['高兴', '伤心'],
      ['好', '不好'],
      ['想', '不想'],
    ];

    for (final pair in negations) {
      final pos = pair[0];
      final neg = pair[1];
      if ((a.contains(pos) && b.contains(neg)) ||
          (a.contains(neg) && b.contains(pos))) {
        return true;
      }
    }

    return false;
  }

  // ===================== 预提取（AI 回复前调用） =====================

  /// 在 AI 回复前快速提取当前消息的状态信息
  /// 解决"用户刚说吃完饭，AI 还问吃了吗"的问题
  Future<void> preExtractState({
    required String characterId,
    required String userId,
    required String currentMessage,
  }) async {
    if (currentMessage.length < 3) return;
    await _extractCurrentStates([currentMessage], characterId, userId);
  }

  // ===================== 记忆提取（保留原有逻辑） =====================

  /// 从对话中提取关键记忆
  Future<void> extractMemory({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> recentMessages,
    required String characterName,
  }) async {
    if (recentMessages.length < 2) return;

    final userMessages = recentMessages
        .where((m) => !m.isFromAI)
        .map((m) => m.content)
        .where((c) => c.length > 3)
        .take(8)
        .toList();

    if (userMessages.isEmpty) return;

    // 尝试用 LLM 提取，失败则回退到正则
    try {
      final llmExtracted = await _extractMemoriesWithLLM(
        character: character,
        userId: userId,
        userMessages: userMessages,
        allMessages: recentMessages,
      );
      if (llmExtracted) return;
    } catch (e) {
      debugPrint('LLM 记忆提取失败，回退到正则: $e');
    }

    // 回退：正则提取
    for (final msg in userMessages) {
      await _extractPreferences(msg, character.id, userId);
      await _extractMilestones(msg, recentMessages, character.id, userId);
    }
    await _extractCurrentStates(userMessages, character.id, userId);
  }

  /// 从当前角色的历史聊天记录中重建缺失记忆。
  ///
  /// 只读取本地聊天记录，不删除现有记忆；通过全量记忆去重避免重复写入。
  ///
  /// 为防止大量消息（上万/十万条）导致内存溢出或 UI 冻结：
  /// - 消息分页从数据库读取，不会一次性全部加载
  /// - 最多处理 [maxBatches] 批（默认 200 批 = 3200 条消息）
  /// - 每批 LLM 调用间暂停 200ms，避免触发 API 限流
  /// - 每处理一批让出 UI 线程，保持页面可交互
  /// 从历史聊天记录中重建记忆 — 支持断点续传
  ///
  /// 两种调用方式：
  /// 1. 全新重建：传 [character]，不传 [checkpoint]
  /// 2. 断点续传：传 [characterId] + [userId] + [checkpoint]，不传 [character]
  ///
  /// [onCheckpoint] 每批处理后回调，调用方负责持久化到 SharedPreferences。
  Future<MemoryRebuildResult> rebuildMemoriesFromHistory({
    AICharacter? character,
    String? characterId,
    required String userId,
    Map<String, dynamic>? checkpoint,
    int batchSize = 16,
    int maxBatches = 200,
    void Function(int processedMessages, int totalMessages)? onProgress,
    Future<void> Function(RebuildCheckpointData data)? onCheckpoint,
  }) async {
    // 确定 characterId
    final cId = character?.id ?? characterId;
    if (cId == null) {
      return const MemoryRebuildResult(
        scannedSessions: 0,
        scannedMessages: 0,
        savedMemories: 0,
        skippedBatches: 0,
        failedBatches: 0,
      );
    }

    // 获取角色名（用于日志和 UI 显示）
    String characterName = character?.name ?? '未知';
    if (character == null) {
      try {
        final c = await _storage.getAICharacter(cId);
        if (c != null) characterName = c.name;
      } catch (_) {}
    }

    final sessions = (await _storage.getChatSessionsByCharacterId(cId))
        .where((s) => s.userId == userId)
        .toList();

    if (sessions.isEmpty) {
      return const MemoryRebuildResult(
        scannedSessions: 0,
        scannedMessages: 0,
        savedMemories: 0,
        skippedBatches: 0,
        failedBatches: 0,
      );
    }

    final sessionIds = sessions.map((s) => s.id).toList();

    // ── 恢复或初始化计数器 ──
    int startSessionIndex = 0;
    int startDbOffset = 0;
    int scannedMessages = 0;
    int processedMessages = 0;
    int skippedBatches = 0;
    int failedBatches = 0;
    int totalBatches = 0;
    int beforeCount = 0;
    final errors = <String>[];

    if (checkpoint != null) {
      // 从断点恢复
      startSessionIndex = checkpoint['sessionIndex'] as int? ?? 0;
      startDbOffset = checkpoint['dbOffset'] as int? ?? 0;
      processedMessages = checkpoint['processedMessages'] as int? ?? 0;
      scannedMessages = checkpoint['scannedMessages'] as int? ?? 0;
      totalBatches = checkpoint['totalBatches'] as int? ?? 0;
      skippedBatches = checkpoint['skippedBatches'] as int? ?? 0;
      failedBatches = checkpoint['failedBatches'] as int? ?? 0;
      beforeCount = checkpoint['beforeMemoryCount'] as int? ?? 0;

      // 校验 sessionIds 一致性（会话可能已变化）
      final savedIds =
          (checkpoint['sessionIds'] as List<dynamic>?)?.cast<String>() ?? [];
      if (!_listEquals(savedIds, sessionIds)) {
        // 会话列表已变化，尝试找到断点 session 的新位置
        if (startSessionIndex < savedIds.length) {
          final resumeSessionId = savedIds[startSessionIndex];
          final newIndex = sessionIds.indexOf(resumeSessionId);
          if (newIndex >= 0) {
            startSessionIndex = newIndex;
          } else {
            // 断点的 session 已不存在，从头开始
            startSessionIndex = 0;
            startDbOffset = 0;
            processedMessages = 0;
            scannedMessages = 0;
            totalBatches = 0;
            skippedBatches = 0;
            failedBatches = 0;
          }
        }
      }
      debugPrint('MemoryEngine: 从断点恢复 sessionIdx=$startSessionIndex '
          'offset=$startDbOffset batches=$totalBatches');
    } else {
      // 全新重建
      beforeCount = (await _storage.getMemories(
        characterId: cId,
        userId: userId,
        limit: 9999,
      ))
          .length;
    }

    bool hitBatchLimit = false;
    const dbPageSize = 500;

    // 确保 character 对象可用（用于 extractMemory）
    AICharacter? activeCharacter = character;
    if (activeCharacter == null) {
      try {
        activeCharacter = await _storage.getAICharacter(cId);
      } catch (_) {}
    }

    for (var sIdx = startSessionIndex; sIdx < sessions.length; sIdx++) {
      final session = sessions[sIdx];
      int dbOffset = (sIdx == startSessionIndex) ? startDbOffset : 0;

      while (true) {
        final page = await _storage.getChatMessages(
          session.id,
          limit: dbPageSize,
          offset: dbOffset,
        );
        if (page.isEmpty) break;

        final visibleMessages = page
            .where((m) =>
                !m.isSystem &&
                !m.isHidden &&
                !m.isGhost &&
                !MessageSanitizer.isLikelyUnreadableGibberish(m.content) &&
                !_isBtContextPolluted(m.content) &&
                m.content.trim().length > 3)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        scannedMessages += visibleMessages.length;

        for (var i = 0; i < visibleMessages.length; i += batchSize) {
          if (totalBatches >= maxBatches) {
            hitBatchLimit = true;
            break;
          }

          final end = min(i + batchSize, visibleMessages.length);
          final batch = visibleMessages.sublist(i, end);
          final hasUserContent = batch.any((m) => m.isFromUser);
          if (!hasUserContent) {
            skippedBatches++;
            processedMessages += batch.length;
            onProgress?.call(processedMessages, scannedMessages);
            continue;
          }

          if (activeCharacter != null) {
            try {
              await extractMemory(
                character: activeCharacter,
                userId: userId,
                recentMessages: batch,
                characterName: characterName,
              );
            } catch (e) {
              failedBatches++;
              if (errors.length < 3) errors.add(e.toString());
              debugPrint('历史记忆重建批次失败: $e');
            }
          } else {
            failedBatches++;
            if (errors.length < 3) errors.add('无法加载角色 $cId');
          }

          totalBatches++;
          processedMessages += batch.length;
          onProgress?.call(processedMessages, scannedMessages);

          // ── 持久化断点 ──
          onCheckpoint?.call(RebuildCheckpointData(
            characterId: cId,
            userId: userId,
            sessionIndex: sIdx,
            sessionIds: sessionIds,
            dbOffset: dbOffset + dbPageSize,
            processedMessages: processedMessages,
            scannedMessages: scannedMessages,
            totalBatches: totalBatches,
            skippedBatches: skippedBatches,
            failedBatches: failedBatches,
            beforeMemoryCount: beforeCount,
          ));

          // ── 让出 UI 线程 + API 限流保护 ──
          await Future.delayed(const Duration(milliseconds: 200));
        }

        if (hitBatchLimit) break;
        if (page.length < dbPageSize) break;
        dbOffset += dbPageSize;
      }

      if (hitBatchLimit) break;
    }

    // 计算新增记忆数
    if (beforeCount == 0) {
      beforeCount = (await _storage.getMemories(
        characterId: cId,
        userId: userId,
        limit: 9999,
      ))
          .length;
    }
    final afterCount = (await _storage.getMemories(
      characterId: cId,
      userId: userId,
      limit: 9999,
    ))
        .length;

    return MemoryRebuildResult(
      scannedSessions: sessions.length,
      scannedMessages: scannedMessages,
      savedMemories: max(0, afterCount - beforeCount),
      skippedBatches: skippedBatches,
      failedBatches: failedBatches,
      errors: [
        ...errors,
        if (hitBatchLimit) '已达批次上限（$maxBatches 批），部分历史消息未处理。如需继续，可再次点击重建。',
      ],
    );
  }

  /// 列表相等比较
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 用 LLM 从消息中提取结构化记忆
  Future<bool> _extractMemoriesWithLLM({
    required AICharacter character,
    required String userId,
    required List<String> userMessages,
    required List<ChatMessage> allMessages,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) return false;
    final start = allMessages.length > 10 ? allMessages.length - 10 : 0;
    final recentContext = allMessages
        .sublist(start)
        .map((m) => '${m.isFromAI ? character.name : "用户"}: ${m.content}')
        .join('\n');

    final prompt = '''你是记忆提取专家。从以下对话中提取用户的关键信息，以 JSON 数组格式输出。

提取规则：
1. 偏好（preference）：食物、爱好、习惯、工作/学习、不喜欢的东西
2. 经历（milestone）：重要事件、计划、生活变化、生日、考试、旅行
3. 情感（emotion）：用户表达的情绪、心情、感受
4. 状态（state）：当前正在做什么、在哪里、身体状况

每条记忆格式：
{"type": "preference|milestone|emotion|state", "content": "记忆内容，50字以内", "importance": 1|2, "keywords": ["关键词1", "关键词2"]}

importance: 1=一般，2=重要

规则：
- 只提取用户（非AI）说的话中包含的信息
- 不要提取重复信息（如果之前已提取过）
- 内容要具体，不要泛泛
- 每条记忆一行JSON，不要用数组包裹
- 如果没有值得提取的信息，输出空字符串

最近对话：
$recentContext

本次用户消息：
${userMessages.join('\n')}

输出（每行一条JSON，没有则输出空）：''';

    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final response = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode({
            'model': config.modelName,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'temperature': 0.3,
            'max_tokens': 500,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return false;

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final text = ResponseDecoder.extractContent(data);
    if (text.trim().isEmpty) return false;

    // 解析每一行 JSON
    int savedCount = 0;
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('{')) continue;

      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        final typeStr = map['type'] as String? ?? '';
        final content = map['content'] as String? ?? '';
        if (content.isEmpty) continue;

        final type = _parseMemoryType(typeStr);
        final importanceIdx = map['importance'] as int? ?? 1;
        final importance = importanceIdx >= 2
            ? MemoryImportance.important
            : MemoryImportance.normal;
        final keywords = (map['keywords'] as List<dynamic>?)
                ?.map((k) => k.toString())
                .toList() ??
            [];

        // 去重：检查是否已有相似内容
        final existing = await _storage.getMemories(
          characterId: character.id,
          userId: userId,
          type: type,
          limit: 100,
        );
        final isDuplicate = existing.any(
            (m) => m.content.contains(content) || content.contains(m.content));
        if (isDuplicate) continue;

        await _storage.saveMemory(Memory(
          id: const Uuid().v4(),
          characterId: character.id,
          userId: userId,
          type: type,
          content: content,
          importance: importance,
          keywords: keywords,
          createdAt: DateTime.now(),
        ));
        savedCount++;
      } catch (e) {
        debugPrint('Error: $e');
      }
    }

    debugPrint('LLM 记忆提取完成: 保存了 $savedCount 条记忆');
    return savedCount > 0;
  }

  MemoryType _parseMemoryType(String type) => switch (type) {
        'preference' => MemoryType.preference,
        'milestone' => MemoryType.milestone,
        'emotion' => MemoryType.emotion,
        'state' => MemoryType.state,
        _ => MemoryType.preference,
      };

  /// 提取用户偏好
  Future<void> _extractPreferences(
      String content, String characterId, String userId) async {
    final preferences = <String>[];

    // 食物偏好
    final foodPatterns = [
      RegExp(r'(?:喜欢吃|爱吃|最爱吃|讨厌吃|不爱吃)(.+?)(?:[，。！？,!?]|$)'),
      RegExp(r'(?:对|对)(.+?)(?:过敏|不耐受)'),
    ];
    for (final pattern in foodPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        final thing = match.group(1)?.trim();
        if (thing != null && thing.length > 1 && thing.length < 20) {
          preferences.add('饮食：$thing');
        }
      }
    }

    // 兴趣爱好
    final hobbyPatterns = [
      RegExp(r'(?:喜欢|爱|热衷于|沉迷|迷上)(.+?)(?:[，。！？,!?]|$)'),
      RegExp(r'(?:最近|平时|周末|空闲)(?:在|经常)?(.+?)(?:[，。！？,!?]|$)'),
      RegExp(r'(?:爱好|兴趣)(?:是|有)?(.+?)(?:[，。！？,!?]|$)'),
    ];
    for (final pattern in hobbyPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        final thing = match.group(1)?.trim();
        if (thing != null &&
            thing.length > 1 &&
            thing.length < 25 &&
            !_isGenericPhrase(thing)) {
          preferences.add('兴趣：$thing');
        }
      }
    }

    // 厌恶/不喜欢
    if (content.contains('不喜欢') ||
        content.contains('讨厌') ||
        content.contains('受不了')) {
      final match =
          RegExp(r'(?:不喜欢|讨厌|受不了)(.+?)(?:[，。！？,!?]|$)').firstMatch(content);
      if (match != null) {
        final thing = match.group(1)?.trim();
        if (thing != null && thing.length > 1 && thing.length < 20) {
          preferences.add('不喜欢：$thing');
        }
      }
    }

    // 生活习惯
    final habitPatterns = [
      RegExp(r'(?:习惯|通常|一般|每天|经常)(.+?)(?:[，。！？,!?]|$)'),
      RegExp(r'(?:熬夜|早起|晚睡|早起|作息)(.+?)(?:[，。！？,!?]|$)'),
    ];
    for (final pattern in habitPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        final thing = match.group(1)?.trim();
        if (thing != null && thing.length > 1 && thing.length < 25) {
          preferences.add('习惯：$thing');
        }
      }
    }

    // 工作/学习相关
    final workPatterns = [
      RegExp(r'(?:工作|上班|职业|做|从事)(?:是|在|于)?(.+?)(?:[，。！？,!?]|$)'),
      RegExp(r'(?:学|读|专业|研究)(?:的是|的是|的是)?(.+?)(?:[，。！？,!?]|$)'),
    ];
    for (final pattern in workPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        final thing = match.group(1)?.trim();
        if (thing != null && thing.length > 1 && thing.length < 25) {
          preferences.add('工作/学习：$thing');
        }
      }
    }

    for (final pref in preferences) {
      final existing = await _findSimilarMemory(characterId, userId, pref);
      if (existing == null) {
        await _storage.saveMemory(Memory(
          id: const Uuid().v4(),
          characterId: characterId,
          userId: userId,
          type: MemoryType.preference,
          content: pref,
          importance: MemoryImportance.normal,
          createdAt: DateTime.now(),
        ));
      }
    }
  }

  /// 判断是否是过于通用的短语
  bool _isGenericPhrase(String text) {
    final genericWords = {'这个', '那个', '什么', '东西', '事情', '时候', '地方', '感觉'};
    return genericWords.contains(text);
  }

  /// 提取重要事件
  Future<void> _extractMilestones(
    String content,
    List<ChatMessage> context,
    String characterId,
    String userId,
  ) async {
    final milestonePatterns = [
      RegExp(r'(今天|昨天|上周|上个月|去年).{0,10}(?:生日|考试|面试|旅行|搬家|分手|毕业|入职|获奖|生病|康复)'),
      RegExp(r'(准备|要|打算|计划).{0,15}(?:去|来|做|参加|开始|结束)'),
      RegExp(r'(?:开心|难过|感动|难忘|紧张|兴奋|失望).{0,5}(?:的是|的事情|的回忆|的一天|的消息)'),
      RegExp(r'(?:第一次|终于|没想到|意外).{0,10}(?:[，。！？,!?]|$)'),
    ];

    for (final pattern in milestonePatterns) {
      if (pattern.hasMatch(content)) {
        final existing = await _findSimilarMemory(characterId, userId,
            content.substring(0, content.length.clamp(0, 50)));
        if (existing == null) {
          await _storage.saveMemory(Memory(
            id: const Uuid().v4(),
            characterId: characterId,
            userId: userId,
            type: MemoryType.milestone,
            content: content.length > 100
                ? '${content.substring(0, 100)}...'
                : content,
            importance: MemoryImportance.important,
            createdAt: DateTime.now(),
          ));
        }
        break;
      }
    }

    // 用户给角色购买/赠送的重要物品，例如“给你买了新手机”。这类事实对后续对话
    // 很关键，不能只依赖 LLM 提取。
    final giftPatterns = [
      RegExp(
          r'(?:给|帮|替)(?:你|她|他|它|TA|ta).{0,6}(?:买|购置|准备|订|换|送)了?(.{2,24}?)(?:[，。！？,!?]|$)'),
      RegExp(r'(?:买|购置|准备|订|换|送)了?(.{2,24}?)(?:给|送给)(?:你|她|他|它|TA|ta)'),
    ];
    for (final pattern in giftPatterns) {
      final match = pattern.firstMatch(content);
      if (match == null) continue;
      final item = match.group(1)?.trim();
      if (item == null || item.length < 2 || _isGenericPhrase(item)) continue;
      final memoryText = '用户为你购置/赠送了$item';
      final existing =
          await _findSimilarMemory(characterId, userId, memoryText);
      if (existing == null) {
        await _storage.saveMemory(Memory(
          id: const Uuid().v4(),
          characterId: characterId,
          userId: userId,
          type: MemoryType.milestone,
          content: memoryText,
          importance: MemoryImportance.important,
          keywords: _extractKeywords(memoryText, maxKeywords: 8),
          createdAt: DateTime.now(),
        ));
      }
      break;
    }

    // 提取用户提到的未来计划
    final planPatterns = [
      RegExp(
          r'(?:下周|下个月|明天|后天|周末|过几天).{0,15}(?:要|打算|计划|准备).{0,10}(?:去|做|参加|开始)'),
      RegExp(r'(?:等|等到|等过).{0,5}(?:放假|休息|周末|毕业|考完).{0,10}(?:要|打算|计划)'),
    ];
    for (final pattern in planPatterns) {
      if (pattern.hasMatch(content)) {
        final match = pattern.firstMatch(content);
        if (match != null) {
          final planText = match.group(0) ?? content;
          final existing = await _findSimilarMemory(characterId, userId,
              planText.substring(0, planText.length.clamp(0, 50)));
          if (existing == null) {
            await _storage.saveMemory(Memory(
              id: const Uuid().v4(),
              characterId: characterId,
              userId: userId,
              type: MemoryType.milestone,
              content:
                  '计划：${planText.length > 80 ? '${planText.substring(0, 80)}...' : planText}',
              importance: MemoryImportance.important,
              createdAt: DateTime.now(),
            ));
          }
        }
        break;
      }
    }
  }

  Future<void> _extractCurrentStates(
    List<String> userMessages,
    String characterId,
    String userId,
  ) async {
    final statePatterns = <String, List<RegExp>>{
      '饮食': [
        RegExp(r'(?:还没|还没有|没)(?:吃饭|吃东西|吃午饭|吃晚饭|吃早餐|吃宵夜)'),
        RegExp(r'(?:吃过了|吃了|刚吃|正在吃|在吃饭)'),
        RegExp(r'(?:饿了|好饿|肚子饿|不饿)'),
        RegExp(r'(?:不想吃|没胃口|吃不下)'),
      ],
      '工作学习': [
        RegExp(r'(?:在|正在|还在)(?:加班|上班|上课|学习|写作业|复习|备考|开会|赶工|做项目)'),
        RegExp(r'(?:下班了|放学了|下课了|收工了|放假了|休息了)'),
        RegExp(r'(?:今天(?:加班|上班|上课)|明天(?:加班|上班|上课))'),
        RegExp(r'(?:好忙|好累|忙死了|累死了|忙得不行)'),
      ],
      '活动状态': [
        RegExp(r'(?:在|正在|准备)(?:睡觉|睡了|躺了|休息|玩|看电视|打游戏|刷手机|运动|跑步|散步|洗澡|出门)'),
        RegExp(r'(?:刚(?:起床|醒来|到家|出门|回来))'),
        RegExp(r'(?:睡不着|失眠|困了|好困)'),
      ],
      '身体状态': [
        RegExp(r'(?:头疼|肚子疼|感冒了|发烧了|不舒服|身体不舒服|来例假了|生理期)'),
        RegExp(r'(?:好多了|好了|恢复了|不疼了)'),
      ],
      '当前位置': [
        RegExp(r'(?:在家|到家了|回去了|在家呢)'),
        RegExp(r'(?:在公司|在办公室|在学校|在图书馆|在外面|在地铁上|在公交上)'),
        RegExp(r'(?:出去了|出去玩|出门了|出差了|旅游去了)'),
      ],
    };

    for (final msg in userMessages) {
      for (final entry in statePatterns.entries) {
        for (final pattern in entry.value) {
          if (pattern.hasMatch(msg)) {
            final match = pattern.firstMatch(msg);
            if (match != null) {
              final stateText = '${entry.key}：${match.group(0)}';
              final existing =
                  await _findSimilarState(characterId, userId, entry.key);
              if (existing != null) {
                await _storage.saveMemory(existing.copyWith(
                  content: stateText,
                  createdAt: DateTime.now(),
                  keywords: _extractKeywords(stateText),
                ));
              } else {
                await _storage.saveMemory(Memory(
                  id: const Uuid().v4(),
                  characterId: characterId,
                  userId: userId,
                  type: MemoryType.state,
                  content: stateText,
                  importance: MemoryImportance.important,
                  keywords: _extractKeywords(stateText),
                  createdAt: DateTime.now(),
                ));
              }
            }
            break;
          }
        }
      }
    }
  }

  Future<Memory?> _findSimilarState(
    String characterId,
    String userId,
    String category,
  ) async {
    final recentMemories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: 20,
    );

    for (final memory in recentMemories) {
      if (memory.type == MemoryType.state &&
          memory.content.startsWith('$category：')) {
        final hoursAgo = DateTime.now().difference(memory.createdAt).inHours;
        if (hoursAgo < 12) {
          return memory;
        }
      }
    }
    return null;
  }

  /// 查找相似记忆（防止重复）
  Future<Memory?> _findSimilarMemory(
      String characterId, String userId, String content) async {
    final recentMemories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: 30,
    );

    final keywords = _extractKeywords(content);

    for (final memory in recentMemories) {
      for (final keyword in keywords) {
        if (memory.content.contains(keyword) ||
            memory.keywords.any((k) => content.contains(k))) {
          return memory;
        }
      }
    }

    return null;
  }

  /// 提取关键字
  List<String> _extractKeywords(
    String text, {
    int maxKeywords = Limit.topKeywords,
  }) {
    final stopWords = {
      '的',
      '了',
      '在',
      '是',
      '我',
      '有',
      '和',
      '就',
      '不',
      '人',
      '都',
      '一',
      '一个',
      '上',
      '也',
      '很',
      '到',
      '说',
      '要',
      '去',
      '你',
      '会',
      '着',
      '没有',
      '看',
      '好',
      '自己',
      '这',
    };

    final keywords = <String>[];
    final len = text.length;

    for (int i = 0; i < len - 1; i++) {
      for (int j = 2; j <= 4 && i + j <= len; j++) {
        final word = text.substring(i, i + j);
        if (!stopWords.contains(word) && word.length >= 2) {
          keywords.add(word);
        }
      }
    }

    final freq = <String, int>{};
    for (final k in keywords) {
      freq[k] = (freq[k] ?? 0) + 1;
    }

    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(maxKeywords).map((e) => e.key).toList();
  }

  // ===================== 滚动摘要（永久记忆） =====================

  /// 获取滚动摘要
  Future<String?> getRollingSummary({
    required String characterId,
    required String userId,
  }) async {
    final summaries = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      type: MemoryType.rollingSummary,
      limit: 1,
    );
    return summaries.isNotEmpty ? summaries.first.content : null;
  }

  /// 保存滚动摘要
  Future<void> saveRollingSummary({
    required String characterId,
    required String userId,
    required String summary,
    required int messageCount,
  }) async {
    final existing = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      type: MemoryType.rollingSummary,
      limit: 1,
    );

    final memory = Memory(
      id: existing.isNotEmpty ? existing.first.id : const Uuid().v4(),
      characterId: characterId,
      userId: userId,
      type: MemoryType.rollingSummary,
      content: summary,
      importance: MemoryImportance.crucial,
      keywords: ['__rolling_summary', 'msg_count:$messageCount'],
      createdAt:
          existing.isNotEmpty ? existing.first.createdAt : DateTime.now(),
      lastAccessedAt: DateTime.now(),
      accessCount: (existing.isNotEmpty ? existing.first.accessCount : 0) + 1,
    );

    await _storage.saveMemory(memory);
  }

  /// 检查是否需要生成新的滚动摘要
  Future<List<ChatMessage>?> checkRollingSummaryNeeded({
    required String characterId,
    required String userId,
    required List<ChatMessage> allMessages,
  }) async {
    if (allMessages.length < 10) return null;

    final existing = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      type: MemoryType.rollingSummary,
      limit: 1,
    );

    int lastCount = 0;
    if (existing.isNotEmpty) {
      final countKeyword = existing.first.keywords
          .where((k) => k.startsWith('msg_count:'))
          .firstOrNull;
      if (countKeyword != null) {
        lastCount = int.tryParse(countKeyword.split(':')[1]) ?? 0;
      }
    }

    final newMessageCount = allMessages.length - lastCount;
    if (newMessageCount < 15) return null;

    final startIndex = lastCount > 0 ? lastCount : 0;
    if (startIndex >= allMessages.length) return null;

    return allMessages.sublist(startIndex);
  }

  // ===================== v2 艾宾浩斯热度系统 =====================

  /// 标记记忆被回忆（注入 prompt 时调用）
  ///
  /// 被回忆的记忆权重 +0.01（用进废退）
  /// 冷记忆被唤醒时额外 +0.1（帮助它脱离冷区）
  /// 最高不超过 2.0
  Future<void> markRecalled({
    required String characterId,
    required String userId,
    required List<String> recalledMemoryIds,
  }) async {
    if (recalledMemoryIds.isEmpty) return;

    // 批量查询一次，而非每个 ID 查一次
    final allMemories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: Limit.memoryMaintenanceCap,
    );

    for (final id in recalledMemoryIds) {
      try {
        final memory = allMemories.where((m) => m.id == id).firstOrNull;
        if (memory != null && !memory.pinned) {
          double boost = 0.01; // 基础强化
          // 冷记忆被用户话题唤醒 → 额外强化，帮助脱离冷区
          if (memory.weight < 0.5) {
            boost = 0.1;
          }
          final newWeight = (memory.weight + boost).clamp(0.0, 2.0);
          await _storage.saveMemory(memory.copyWith(
            weight: newWeight,
            lastRecalledAt: DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Error: $e');
      }
    }
  }

  /// 每日衰减（艾宾浩斯遗忘曲线）
  ///
  /// 规则：
  /// - 未被回忆的记忆：weight × 0.998（缓慢衰减）
  /// - 被回忆过的记忆：weight × 1.01（强化）
  /// - 被锁定（pinned）的记忆：不衰减
  /// - weight 最低 0.1，最高 2.0
  ///
  /// 建议在每天凌晨调用一次
  Future<int> dailyDecay({
    required String characterId,
    required String userId,
  }) async {
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: Limit.memoryMaintenanceCap,
    );

    final now = DateTime.now();
    int decayedCount = 0;
    int reinforcedCount = 0;

    for (final memory in memories) {
      // 跳过锁定的记忆
      if (memory.pinned) continue;

      // 跳过滚动摘要（永久记忆）
      if (memory.type == MemoryType.rollingSummary) continue;

      double newWeight;

      // 判断是否昨天被回忆过
      final wasRecalledToday = memory.lastRecalledAt != null &&
          now.difference(memory.lastRecalledAt!).inHours < 24;

      if (wasRecalledToday) {
        // 被回忆 → 强化（用进废退）
        newWeight = (memory.weight * 1.01).clamp(0.0, 2.0);
        reinforcedCount++;
      } else {
        // 未被回忆 → 衰减（艾宾浩斯）
        newWeight = (memory.weight * 0.998).clamp(0.1, 2.0);
        decayedCount++;
      }

      if (newWeight != memory.weight) {
        await _storage.saveMemory(memory.copyWith(weight: newWeight));
      }
    }

    debugPrint(
        'MemoryEngine: daily decay done — $decayedCount decayed, $reinforcedCount reinforced');
    return decayedCount + reinforcedCount;
  }

  /// 梦境整合（合并低权重旧记忆）
  ///
  /// 借鉴 kiwi-mem 的 Dream 系统：
  /// - 30天以上 + weight < 0.3 + 未锁定 + 未合并 → 合并为一条摘要
  /// - 原记忆标记为已合并（不再参与后续整合）
  /// - 原记忆保留（永久存档），但不再注入 prompt
  ///
  /// 建议每周调用一次
  Future<String?> dreamConsolidation({
    required String characterId,
    required String userId,
  }) async {
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: Limit.memoryMaintenanceCap,
    );

    final now = DateTime.now();

    // 找出需要合并的记忆：30天以上 + weight < 0.3 + 未锁定 + 未合并
    final candidates = memories
        .where((m) =>
                m.type != MemoryType.rollingSummary &&
                !m.pinned &&
                m.weight < 0.3 &&
                now.difference(m.createdAt).inDays > 30 &&
                !m.keywords.contains('__merged') // 未被合并过
            )
        .toList();

    if (candidates.length < 3) return null; // 太少不值得合并

    // 最多合并 15 条
    final toMerge = candidates.take(15).toList();

    // 构建合并摘要
    final buffer = StringBuffer();
    buffer.writeln('过去的记忆摘要（${now.month}/${now.day} 整合）：');
    for (final m in toMerge) {
      buffer.writeln('- ${m.content}');
    }

    final summary = buffer.toString();

    // 保存为新的滚动摘要
    await saveRollingSummary(
      characterId: characterId,
      userId: userId,
      summary: summary,
      messageCount: 0,
    );

    // 标记原记忆为已合并（不再参与后续整合和注入）
    for (final m in toMerge) {
      await _storage.saveMemory(m.copyWith(
        keywords: [...m.keywords, '__merged'],
      ));
    }

    debugPrint(
        'MemoryEngine: dream consolidation — merged ${toMerge.length} memories');
    return summary;
  }

  /// 每日维护入口（在 App 启动或凌晨调用）
  ///
  /// 自动判断是否需要执行：
  /// - 每日衰减：每天执行一次
  /// - 梦境整合：每周执行一次
  Future<void> runDailyMaintenance({
    required String characterId,
    required String userId,
  }) async {
    try {
      // 检查今天是否已执行过衰减
      final lastDecayStr =
          _storage.getString('memory_last_decay_${characterId}_$userId');
      final now = DateTime.now();

      if (lastDecayStr != null) {
        final lastDecay = DateTime.tryParse(lastDecayStr);
        if (lastDecay != null && now.difference(lastDecay).inHours < 20) {
          return; // 今天已执行过
        }
      }

      // 执行每日衰减
      await dailyDecay(characterId: characterId, userId: userId);

      // 每7天执行一次梦境整合
      final lastDreamStr =
          _storage.getString('memory_last_dream_${characterId}_$userId');
      if (lastDreamStr != null) {
        final lastDream = DateTime.tryParse(lastDreamStr);
        if (lastDream != null && now.difference(lastDream).inDays < 7) {
          // 记录衰减时间后返回
          await _storage.setString('memory_last_decay_${characterId}_$userId',
              now.toIso8601String());
          return;
        }
      }

      await dreamConsolidation(characterId: characterId, userId: userId);

      // 记录执行时间
      await _storage.setString(
          'memory_last_decay_${characterId}_$userId', now.toIso8601String());
      await _storage.setString(
          'memory_last_dream_${characterId}_$userId', now.toIso8601String());
    } catch (e) {
      debugPrint('MemoryEngine: daily maintenance failed: $e');
    }
  }

  /// 获取记忆热度统计（调试用）
  Future<Map<String, dynamic>> getHeatStats({
    required String characterId,
    required String userId,
  }) async {
    final memories = await _storage.getMemories(
      characterId: characterId,
      userId: userId,
      limit: Limit.memoryMaintenanceCap,
    );

    if (memories.isEmpty) return {'total': 0};

    final weights = memories.map((m) => m.weight).toList();
    final hot = weights.where((w) => w > 1.0).length;
    final warm = weights.where((w) => w >= 0.5 && w <= 1.0).length;
    final cold = weights.where((w) => w < 0.5).length;
    final avg = weights.reduce((a, b) => a + b) / weights.length;

    return {
      'total': memories.length,
      'hot': hot, // 热记忆（完整注入）
      'warm': warm, // 温记忆（摘要注入）
      'cold': cold, // 冷记忆（不注入）
      'avg_weight': avg.toStringAsFixed(3),
    };
  }

  // ===================== 外部调用兼容方法 =====================

  /// 保存对话摘要（解决30条后失忆问题）
  ///
  /// 将最近对话的关键信息压缩为一条 conversation 类型记忆
  Future<void> saveConversationSummary({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> messages,
  }) async {
    if (messages.isEmpty) return;

    // 提取最近 10 条用户/AI 消息作为摘要基础
    final recentContent = messages
        .where((m) => m.type != MessageType.system)
        .take(10)
        .map((m) => '${m.isFromAI ? character.name : "用户"}: ${m.content}')
        .join('\n');

    if (recentContent.trim().isEmpty) return;

    final summary = '最近对话摘要：\n$recentContent';

    final memory = Memory(
      id: const Uuid().v4(),
      characterId: character.id,
      userId: userId,
      type: MemoryType.conversation,
      content: summary,
      importance: MemoryImportance.important,
      keywords: const ['__conversation_summary'],
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      accessCount: 0,
    );

    await _storage.saveMemory(memory);
  }

  /// 保存对话章节（形成关系发展叙事线）
  ///
  /// 每 20 条消息形成一个章节，记录关系发展的关键节点
  Future<void> saveConversationChapter({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> messages,
  }) async {
    if (messages.length < 20) return;

    // 取最近 20 条消息作为章节
    final chapterMsgs = messages.take(20).toList();
    final userMsgs = chapterMsgs
        .where((m) => !m.isFromAI && m.type != MessageType.system)
        .toList();
    final aiMsgs = chapterMsgs.where((m) => m.isFromAI).toList();

    if (userMsgs.isEmpty) return;

    // 生成章节摘要
    final topics = userMsgs.take(5).map((m) => m.content).join('、');
    final chapter = '对话章节（${chapterMsgs.length}条消息）：'
        '用户主要话题涉及 $topics，'
        'AI 回复 ${aiMsgs.length} 次。';

    final memory = Memory(
      id: const Uuid().v4(),
      characterId: character.id,
      userId: userId,
      type: MemoryType.conversation,
      content: chapter,
      importance: MemoryImportance.normal,
      keywords: const ['__conversation_chapter'],
      createdAt: DateTime.now(),
      lastAccessedAt: DateTime.now(),
      accessCount: 0,
    );

    await _storage.saveMemory(memory);
  }

  /// 获取相关记忆（按热度加权精选，用于 prompt 注入）
  Future<String> getRelevantMemoriesForPrompt({
    required AICharacter character,
    required String userId,
    required String currentTopic,
    required int maxMemories,
  }) async {
    final allMemories = await _storage.getMemories(
      characterId: character.id,
      userId: userId,
      limit: Limit.memoryPromptCap,
    );

    // 过滤掉滚动摘要、过时状态、已合并的记忆
    final filtered = allMemories.where((m) =>
        m.type != MemoryType.rollingSummary &&
        !m.keywords.contains('__merged') &&
        !(m.type == MemoryType.state &&
            DateTime.now().difference(m.createdAt).inHours >= 12));

    if (filtered.isEmpty) return '';

    final scored = _scoreMemories(filtered.toList(), currentTopic);
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    final selected = <String>[];
    for (final (memory, _) in scored) {
      final keywordMatched = _memoryMatchesTopic(memory, currentTopic);
      if (memory.weight < 0.5 && !memory.pinned && !keywordMatched) continue;
      final content = _formatMemoryLine(memory);
      if (content == null) continue;
      selected.add(content);
      if (selected.length >= maxMemories) break;
    }

    if (selected.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('【${character.name}记得关于你的事情】');
    for (final line in selected) {
      buffer.writeln(line);
    }
    return buffer.toString();
  }

  /// 获取最近状态（用于 prompt 注入，防止重复询问）
  Future<String> getRecentStatesForPrompt({
    required AICharacter character,
    required String userId,
  }) async {
    final states = await _getRecentStatesCompact(
      characterId: character.id,
      userId: userId,
    );
    if (states.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('【最近状态 — 请勿重复询问】');
    buffer.writeln(states);
    return buffer.toString();
  }

  /// 获取对话叙事线（当前返回空，预留接口）
  Future<String> getConversationNarrative({
    required AICharacter character,
    required String userId,
  }) async {
    // 暂未实现独立叙事线，由 buildConsolidatedMemoryPrompt 内部处理
    return '';
  }

  /// 获取对话摘要列表（用于 prompt 注入）
  Future<String> getConversationSummariesForPrompt({
    required AICharacter character,
    required String userId,
  }) async {
    final summary = await getRollingSummary(
      characterId: character.id,
      userId: userId,
    );
    if (summary == null || summary.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('【永久记忆档案】');
    buffer.writeln(summary);
    return buffer.toString();
  }

  // ===================== 兼容性保留 =====================

  /// 构建关系档案（保留给 proactive/moment 等外部调用）
  Future<String> buildRelationshipProfile({
    required AICharacter character,
    required String userId,
  }) async {
    final memories = await _storage.getMemories(
      characterId: character.id,
      userId: userId,
      limit: 50,
    );

    if (memories.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('【关系档案 — 我对 ${userId.substring(0, 8)} 的了解】');

    final preferences = <String>[];
    final events = <String>[];
    final emotions = <String>[];
    final states = <String>[];

    for (final memory in memories) {
      switch (memory.type) {
        case MemoryType.preference:
          preferences.add(memory.content);
        case MemoryType.milestone:
          events.add(memory.content);
        case MemoryType.emotion:
          emotions.add(memory.content);
        case MemoryType.state:
          final hoursAgo = DateTime.now().difference(memory.createdAt).inHours;
          if (hoursAgo < 12) {
            states.add(memory.content);
          }
        default:
          break;
      }
    }

    if (preferences.isNotEmpty) {
      buffer.writeln('\n【我知道的喜好】');
      for (final p in preferences.take(8)) {
        buffer.writeln('· $p');
      }
    }

    if (events.isNotEmpty) {
      buffer.writeln('\n【共同经历】');
      for (final e in events.take(5)) {
        buffer.writeln('· $e');
      }
    }

    if (emotions.isNotEmpty) {
      buffer.writeln('\n【记住的情绪】');
      for (final em in emotions.take(5)) {
        buffer.writeln('· $em');
      }
    }

    if (states.isNotEmpty) {
      buffer.writeln('\n【最近的状态】');
      for (final s in states.take(5)) {
        buffer.writeln('· $s');
      }
    }

    return buffer.toString();
  }
}
