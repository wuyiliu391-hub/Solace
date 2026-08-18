// MemoryEngine 外部调用兼容方法与跨角色记忆互通。
// 本文件是 memory_engine.dart 的 part，与其共同构成一个库。

part of '../memory_engine.dart';

mixin MemoryEngineCompatCrossApi on MemoryEngineEhSummaryApi {
  /// 从用户消息中识别提到的其他角色（按名称/别名最长匹配，再按出现顺序）
  Future<List<AICharacter>> resolveMentionedCharacters({
    required String text,
    required String currentCharacterId,
    int maxHits = MemoryEngine.maxCrossCharactersFull,
  }) async {
    final raw = text.trim();
    if (raw.isEmpty) return const [];

    List<AICharacter> all;
    try {
      all = await _storage.getAllAICharacters();
    } catch (e) {
      debugPrint('MemoryEngine: resolveMentionedCharacters load failed: $e');
      return const [];
    }

    final candidates = <({AICharacter c, String alias, int len})>[];
    for (final c in all) {
      if (c.id == currentCharacterId || c.isHidden) continue;
      final aliases = <String>{
        c.name.trim(),
        if ((c.userAlias ?? '').trim().isNotEmpty) c.userAlias!.trim(),
        if ((c.userNickname ?? '').trim().isNotEmpty) c.userNickname!.trim(),
      }.where((a) => a.length >= 2).toList();
      for (final a in aliases) {
        candidates.add((c: c, alias: a, len: a.length));
      }
    }
    // 长名优先，避免「小明」抢「小明明」
    candidates.sort((a, b) => b.len.compareTo(a.len));

    // 记录每个角色最早出现位置，便于按用户提及顺序排序
    final firstPos = <String, int>{};
    final byId = <String, AICharacter>{};
    final lowerRaw = raw.toLowerCase();
    for (final item in candidates) {
      if (byId.containsKey(item.c.id)) continue;
      final alias = item.alias;
      var idx = raw.indexOf(alias);
      if (idx < 0) {
        idx = lowerRaw.indexOf(alias.toLowerCase());
      }
      if (idx < 0) continue;
      byId[item.c.id] = item.c;
      firstPos[item.c.id] = idx;
    }

    final ordered = byId.keys.toList()
      ..sort((a, b) => (firstPos[a] ?? 0).compareTo(firstPos[b] ?? 0));

    final hits = <AICharacter>[];
    for (final id in ordered) {
      hits.add(byId[id]!);
      if (hits.length >= maxHits) break;
    }
    return hits;
  }

  /// 构建「用户提到其他角色」时的真实互通上下文。
  /// 支持 1~N 个角色：多角色时自动压缩单人档案，并附多方关系速览。
  /// 只注入真实存在的角色数据与记忆，禁止模型另编一个同名路人。
  Future<String> buildCrossCharacterContext({
    required AICharacter speaker,
    required String userId,
    required String userMessage,
    int maxOthers = MemoryEngine.maxCrossCharactersFull,
  }) async {
    final mentioned = await resolveMentionedCharacters(
      text: userMessage,
      currentCharacterId: speaker.id,
      maxHits: maxOthers,
    );
    if (mentioned.isEmpty) return '';

    final multi = mentioned.length >= 2;
    // 多角色时压缩每人细节，避免 prompt 爆炸
    final memLimit = multi ? (mentioned.length >= 4 ? 2 : 3) : 5;
    final socialLimit = multi ? 2 : 4;
    final personalityLen = multi ? 40 : 80;
    final lastMsgLen = multi ? 40 : 60;

    final buffer = StringBuffer();
    buffer.writeln('\n【跨角色互通 — 真实角色档案（禁止编造）】');
    if (multi) {
      buffer.writeln(
          '用户本轮提到了 ${mentioned.length} 个真实角色：${mentioned.map((c) => c.name).join('、')}。');
      buffer.writeln('这是多方关系语境，不是一对一闲聊。');
    } else {
      buffer.writeln('用户提到了以下你认识的真实角色。这些是同一个世界里的既有角色，不是路人，也不是新编角色。');
    }
    buffer.writeln('规则：');
    buffer.writeln('1. 只能使用下列档案与记忆中的事实，禁止另编姓名、关系、经历。');
    buffer.writeln('2. 若档案里没有某细节，就承认不清楚，不要脑补。');
    buffer.writeln('3. 你是${speaker.name}，用你自己的视角谈对方，不要变成对方本人。');
    if (multi) {
      buffer.writeln('4. 多人同时出现时：分别对齐每人与用户的真实关系，不要张冠李戴。');
      buffer.writeln('5. 不要把 B 的记忆安到 C 头上；谈「我们几个」时按各自亲密度与事实回应。');
    }

    // 预取 speaker 社交记忆，多方复用
    List<Memory> speakerSocial = const [];
    try {
      speakerSocial = await loadSocialMemories(speaker.id);
    } catch (_) {}

    // 收集多方速览行
    final rosterLines = <String>[];

    var count = 0;
    for (final other in mentioned) {
      if (count >= maxOthers) break;
      count++;

      // 用户与对方的亲密度 / 会话摘要
      int intimacy = 0;
      String? lastMessage;
      DateTime? lastTime;
      try {
        final sessions = await _storage.getChatSessionsByCharacterId(other.id);
        final mine = sessions.where((s) => s.userId == userId).toList();
        final session = mine.isNotEmpty
            ? mine.first
            : (sessions.isNotEmpty ? sessions.first : null);
        if (session != null) {
          intimacy = session.intimacyLevel;
          lastMessage = session.lastMessage;
          lastTime = session.lastMessageTime;
        }
      } catch (e) {
        debugPrint('cross-char session load failed: $e');
      }

      final relation = _intimacyRelationLabel(intimacy);
      rosterLines.add('${other.name}（用户关系：$relation，$intimacy/100）');

      buffer.writeln('');
      buffer.writeln('── 角色：${other.name} ──');
      buffer.writeln('- 身份：真实存在的 AI 角色（id 已绑定，不可替换）');
      if ((other.gender ?? '').trim().isNotEmpty) {
        buffer.writeln('- 性别：${other.gender}');
      }
      if ((other.personality).trim().isNotEmpty) {
        final p = other.personality.trim();
        buffer.writeln(
            '- 性格要点：${p.length > personalityLen ? '${p.substring(0, personalityLen)}…' : p}');
      }
      if ((other.userNickname ?? '').trim().isNotEmpty) {
        buffer.writeln('- 对方对用户的称呼：${other.userNickname}');
      }
      buffer.writeln('- 用户与${other.name}的关系：$relation（亲密度 $intimacy/100）');
      if (lastMessage != null && lastMessage.trim().isNotEmpty) {
        final lm = lastMessage.trim();
        final snippet =
            lm.length > lastMsgLen ? '${lm.substring(0, lastMsgLen)}…' : lm;
        final when = lastTime != null
            ? '${lastTime.month}/${lastTime.day} ${lastTime.hour.toString().padLeft(2, '0')}:${lastTime.minute.toString().padLeft(2, '0')}'
            : '';
        buffer.writeln(
            '- 用户与${other.name}最近会话摘要${when.isNotEmpty ? '（$when）' : ''}：$snippet');
      }

      // 用户-对方 私有记忆（真实）
      try {
        final mems = await _storage.getMemories(
          characterId: other.id,
          userId: userId,
          limit: multi ? 8 : 12,
        );
        final picks = <String>[];
        for (final m in mems) {
          if (m.type == MemoryType.rollingSummary) continue;
          final c = m.content.trim();
          if (c.isEmpty) continue;
          if (looksLikeBtAgentPayload(c)) continue;
          picks.add(c.length > 70 ? '${c.substring(0, 70)}…' : c);
          if (picks.length >= memLimit) break;
        }
        if (picks.isNotEmpty) {
          buffer.writeln('- ${other.name}与用户相关的真实记忆：');
          for (final p in picks) {
            buffer.writeln('  · $p');
          }
        } else {
          buffer.writeln('- 暂无足够的用户-${other.name}记忆条目。');
        }
      } catch (e) {
        debugPrint('cross-char private memories failed: $e');
      }

      // speaker 与 other 的社交记忆（若有）
      try {
        final related = speakerSocial
            .where((m) =>
                m.userId == other.id ||
                m.content.contains(other.name) ||
                ((other.userAlias ?? '').isNotEmpty &&
                    m.content.contains(other.userAlias!)))
            .take(socialLimit)
            .toList();
        if (related.isNotEmpty) {
          buffer.writeln('- 你（${speaker.name}）与${other.name}之间的社交记忆：');
          for (final m in related) {
            final c = m.content.trim();
            if (c.isEmpty) continue;
            buffer
                .writeln('  · ${c.length > 70 ? '${c.substring(0, 70)}…' : c}');
          }
        }
      } catch (e) {
        debugPrint('cross-char social memories failed: $e');
      }
    }

    // 多方关系速览 + 点名未展开的提示
    if (multi) {
      buffer.writeln('');
      buffer.writeln('【多方关系速览】');
      buffer.writeln('- 说话人：${speaker.name}');
      for (final line in rosterLines) {
        buffer.writeln('- $line');
      }
      buffer.writeln('- 用户同时谈及多人时：先对齐各自关系，再回应群体事件；禁止把所有人当成同一种关系。');
    }

    // 若消息里像还点了更多名字但被截断
    if (mentioned.length >= maxOthers) {
      buffer.writeln('- 提示：本轮已注入 $maxOthers 个角色档案；若用户还提到其他人，只承认名字存在，不编造细节。');
    }

    buffer.writeln('');
    buffer.writeln('再次强调：以上是真实互通数据。提到这些名字时，必须对齐上述关系与记忆，禁止另造一个同名的新人。');
    return buffer.toString();
  }

  /// 构建群聊共享上下文 — 全员设定压缩 + 全员与用户记忆 + 群内社交记忆。
  ///
  /// SWAP 模式下每个角色发言时注入（见 group_chat_bloc），让成员互相知道
  /// 彼此的设定与实时记忆库（全共享，用户已确认）。总预算约 600 tokens，
  /// 5 人群安全。数据全部真实，禁止模型编造其他成员的档案。
  Future<String> buildGroupSharedContext({
    required AICharacter self,
    required List<AICharacter> members, // 除自己外的群成员
    required String userId,
    required String groupId,
    String? chatId,
    int maxMemPerMember = 3,
    int maxSocialPerMember = 2,
  }) async {
    final buffer = StringBuffer();
    if (chatId != null && chatId.isNotEmpty) {
      try {
        final summary = await _storage.getGroupChatSummary(groupId, chatId);
        if (summary != null && summary.summary.trim().isNotEmpty) {
          buffer.writeln('【群聊长期记忆摘要】');
          buffer.writeln(summary.summary.trim());
          buffer.writeln();
        }
      } catch (e) {
        debugPrint('MemoryEngine: group rolling summary failed: $e');
      }
    }
    if (members.isEmpty) return buffer.toString();
    buffer.writeln('\n【群成员共享信息 — 实时记忆库（禁止编造）】');
    buffer.writeln('你是「${self.name}」，本段是群里所有成员的公开信息与记忆，全员可见。');
    buffer.writeln('规则：');
    buffer.writeln('1. 你只能以「${self.name}」的身份发言，不要变成其他成员本人。');
    buffer.writeln('2. 下列信息全部真实，禁止另编姓名、关系、经历。');
    buffer.writeln('3. 提到他人时对齐其设定与记忆，不要张冠李戴。');

    for (final other in members) {
      buffer.writeln('');
      buffer.writeln('── 成员：${other.name} ──');

      // 档案压缩摘要
      final traits = <String>[];
      if ((other.gender ?? '').trim().isNotEmpty) {
        traits.add('性别：${other.gender}');
      }
      final p = other.personality.trim();
      if (p.isNotEmpty) {
        traits.add('性格：${p.length > 40 ? '${p.substring(0, 40)}…' : p}');
      }
      var bg = (other.backgroundStory ?? '').trim();
      if (bg.isEmpty) bg = (other.worldSetting ?? '').trim();
      if (bg.isNotEmpty) {
        traits.add('背景：${bg.length > 40 ? '${bg.substring(0, 40)}…' : bg}');
      }
      if ((other.catchphrases ?? '').trim().isNotEmpty) {
        traits.add('口头禅：${other.catchphrases}');
      }
      if ((other.userNickname ?? '').trim().isNotEmpty) {
        traits.add('对用户称呼：${other.userNickname}');
      }
      if (traits.isNotEmpty) buffer.writeln('- ${traits.join('；')}');

      // 成员与用户的私密记忆（全共享）
      try {
        final mems = await _storage.getMemories(
          characterId: other.id,
          userId: userId,
          limit: maxMemPerMember + 4,
        );
        final picks = <String>[];
        for (final m in mems) {
          if (m.type == MemoryType.rollingSummary) continue;
          final c = m.content.trim();
          if (c.isEmpty || looksLikeBtAgentPayload(c)) continue;
          picks.add(c.length > 70 ? '${c.substring(0, 70)}…' : c);
          if (picks.length >= maxMemPerMember) break;
        }
        if (picks.isNotEmpty) {
          buffer.writeln('- ${other.name}与用户相关记忆：');
          for (final pick in picks) {
            buffer.writeln('  · $pick');
          }
        }
      } catch (e) {
        debugPrint('MemoryEngine: group shared private mem failed: $e');
      }

      // 该成员在群里的发言沉淀（targetCharacterId 复用为群 id）
      try {
        final social = await loadSocialMemories(other.id);
        final inGroup = social
            .where((m) => m.userId == groupId)
            .take(maxSocialPerMember)
            .toList();
        if (inGroup.isNotEmpty) {
          buffer.writeln('- ${other.name}在群里说过：');
          for (final m in inGroup) {
            final c = m.content.trim();
            if (c.isEmpty) continue;
            buffer
                .writeln('  · ${c.length > 70 ? '${c.substring(0, 70)}…' : c}');
          }
        }
      } catch (e) {
        debugPrint('MemoryEngine: group shared social mem failed: $e');
      }
    }

    buffer.writeln('');
    buffer.writeln('再次强调：以上为全员共享的实时信息；回应他人时对齐上述事实。');
    return buffer.toString();
  }

  Future<String> buildRelatedGroupMemoryContext(
      String characterId, String query,
      {int limit = 3}) async {
    try {
      final memories =
          await _storage.getGroupPublicEventMemories(characterId: characterId);
      final relevant = group_event.buildRelevantGroupEventMemories(
          query: query, memories: memories, limit: limit);
      if (relevant.isEmpty) return '';
      final buffer = StringBuffer('【群聊中的相关记忆】\n');
      for (final memory in relevant) {
        buffer.writeln('- ${memory.content}');
        if (memory.speakerNames.isNotEmpty) {
          buffer.writeln('  参与者：${memory.speakerNames.join('、')}');
        }
      }
      for (final memory in relevant.where((memory) => !memory.pinned)) {
        await _storage.updateGroupPublicEventMemory(memory.copyWith(
          weight: (memory.weight + 0.01).clamp(0.0, 2.0),
          lastRecalledAt: DateTime.now(),
        ));
      }
      return buffer.toString().trim();
    } catch (e) {
      debugPrint('MemoryEngine: related group memory failed: $e');
      return '';
    }
  }

  String _intimacyRelationLabel(int level) {
    if (level >= 80) return '非常亲密/深度羁绊';
    if (level >= 60) return '亲密好友/暧昧升温';
    if (level >= 40) return '熟悉的朋友';
    if (level >= 20) return '认识、有过互动';
    if (level > 0) return '略有接触';
    return '几乎还不熟（但对方仍是用户世界里的真实角色）';
  }

  /// 为一条记忆生成1-2句中文摘要（约20-40字），用于前端卡片展示
  /// 失败或无配置时返回 null，调用方自行兜底（截断原文）
  Future<String?> generateSummary(String content,
      {String? apiKey, String? baseUrl, String? modelName}) async {
    if (content.length < 40) return null;

    String key = apiKey ?? '';
    String url = baseUrl ?? '';
    String model = modelName ?? '';

    if (key.isEmpty || url.isEmpty) {
      final config = await _storage.getActiveAIConfig();
      if (config == null) return null;
      key = config.apiKey;
      url = config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      model = config.modelName;
    }

    final prompt = '用1-2句简短的中文（20-40字）总结以下内容的核心要点，只输出总结，不要任何额外文字：\n\n$content';

    try {
      final uri = Uri.parse('$url/chat/completions');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      };
      final body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': _storage.buildGlobalModePrompt(scope: '记忆摘要')
          },
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.3,
        'max_tokens': 100,
      });
      final client = _httpClient;
      final response = client != null
          ? await client
              .post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 10))
          : await http
              .post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final text = ResponseDecoder.extractContent(data);
      final trimmed = text.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  /// 为一条 Memory 生成摘要并持久化到数据库
  Future<void> generateAndSaveSummary(Memory memory) async {
    if (memory.content.length < 40) return;
    final summary = await generateSummary(memory.content);
    if (summary == null || summary.isEmpty) return;
    await _storage.saveMemory(memory.copyWith(summary: summary));
  }
}
