// MemoryEngine 艾宾浩斯热度系统与滚动摘要（永久记忆档案）。
// 本文件是 memory_engine.dart 的 part，与其共同构成一个库。

part of '../memory_engine.dart';

mixin MemoryEngineEhSummaryApi on _MemoryEngineCore {
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

    await _saveWithSummary(memory);
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

    await _saveWithSummary(memory);
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

    await _saveWithSummary(memory);
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
