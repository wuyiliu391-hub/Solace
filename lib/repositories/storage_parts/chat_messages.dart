// LocalStorageRepository 消息与会话 CRUD：chat_messages / chat_sessions 及相关查询。
// 本文件是 local_storage_repository.dart 的 part，与其共同构成一个库。

part of '../local_storage_repository.dart';

mixin LocalStorageRepositoryChatMessagesApi on _LocalStorageRepositoryCore {
  Future<void> markAILetterRead(String id) async {
    final readAt = DateTime.now().toIso8601String();
    if (_isWeb) {
      final letter = await getAILetter(id);
      if (letter == null) return;
      await _prefs?.setString(
        'ai_letter_$id',
        jsonEncode(letter
            .copyWith(isRead: true, readAt: DateTime.parse(readAt))
            .toMap()),
      );
      return;
    }
    final db = await _ensureDb();
    await db.update(
      'ai_letters',
      {'isRead': 1, 'readAt': readAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAILetter(String id) async {
    if (_isWeb) {
      final letter = await getAILetter(id);
      await _prefs?.remove('ai_letter_$id');
      if (letter != null) {
        final key = 'ai_letter_ids_${letter.userId}';
        final ids = _prefs?.getStringList(key) ?? [];
        ids.remove(id);
        await _prefs?.setStringList(key, ids);
      }
      return;
    }
    final db = await _ensureDb();
    await db.delete('ai_letters', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getUnreadAILetterCount(String userId) async {
    if (_isWeb) {
      final letters = await getAILetters(userId: userId, limit: 9999);
      return letters.where((l) => !l.isRead).length;
    }
    final db = await _ensureDb();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM ai_letters WHERE userId = ? AND isRead = 0',
      [userId],
    );
    return (rows.first['count'] as int?) ?? 0;
  }

  Future<List<AILetter>> getPendingReplyLetters(String userId) async {
    if (_isWeb) {
      final letters = await getAILetters(userId: userId, limit: 9999);
      return letters.where((l) => l.needsReply).toList();
    }
    final db = await _ensureDb();
    final maps = await db.query(
      'ai_letters',
      where: 'userId = ? AND needsReply = 1',
      whereArgs: [userId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((m) => AILetter.fromMap(m)).toList();
  }

  Future<void> markAILetterReplied(String id) async {
    if (_isWeb) {
      final letter = await getAILetter(id);
      if (letter == null) return;
      await _prefs?.setString(
        'ai_letter_$id',
        jsonEncode(letter.copyWith(needsReply: false).toMap()),
      );
      return;
    }
    final db = await _ensureDb();
    await db.update(
      'ai_letters',
      {'needsReply': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveAICharacter(AICharacter character) async {
    // 内置角色是应用身份的一部分：允许删除，但禁止通过任何保存路径覆盖。
    if (BuiltinCharacters.isBuiltin(character.id)) {
      final existing = await getAICharacter(character.id);
      if (existing != null) return;
    }
    if (_isWeb) {
      await _prefs?.setString(
          PrefKeys.character(character.id), jsonEncode(character.toMap()));
      final ids = _prefs?.getStringList('character_ids') ?? [];
      if (!ids.contains(character.id)) {
        ids.add(character.id);
        await _prefs?.setStringList('character_ids', ids);
      }
    } else {
      final db = await _ensureDb();
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'ai_characters', 'structuredTraits', 'TEXT');
      await LocalStorageRepository._addColumnIfNotExists(db, 'ai_characters', 'userAlias', 'TEXT');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'ai_characters', 'sync_seq', 'INTEGER DEFAULT 0');
      final map = await _filterMapToExistingColumns(
          db, 'ai_characters', character.toMap());
      final updateCount = await db.update('ai_characters', map,
          where: 'id = ?', whereArgs: [character.id]);
      if (updateCount == 0) {
        await db.insert('ai_characters', map);
      }
    }
  }

  /// 内置角色种子：首次安装时自动写入内置角色
  ///
  /// 检查每个内置角色是否已存在于数据库中，不存在则插入。
  /// 这样旧用户覆盖升级后也能吃到新内置角色。
  Future<void> seedBuiltInCharacters() async {
    final db = await _ensureDb();

    for (final character in BuiltinCharacters.all) {
      final existing = await db.query(
        'ai_characters',
        where: 'id = ?',
        whereArgs: [character.id],
        limit: 1,
      );
      if (existing.isEmpty) {
        // 与更新分支对齐：先过滤到真实列，防止模型新增键（如 storyState）
        // 在缺列的表上 INSERT 直接 SQLITE_ERROR 崩溃。
        final map = await _filterMapToExistingColumns(
            db, 'ai_characters', character.toMap());
        await db.insert('ai_characters', map);
        debugPrint('Seeded built-in character: ${character.name}');
      } else {
        // 内置角色资料被锁定，不允许用户编辑；因此版本升级时可安全刷新
        // 官方人格与边界，确保旧用户也能获得新版设定。
        final map = await _filterMapToExistingColumns(
            db, 'ai_characters', character.toMap());
        await db.update('ai_characters', map,
            where: 'id = ?', whereArgs: [character.id]);
        debugPrint('Refreshed built-in character: ${character.name}');
      }
    }
  }

  Future<List<AICharacter>> getAllAICharacters({bool includeHidden = false}) async {
    if (_isWeb) {
      final ids = _prefs?.getStringList('character_ids') ?? [];
      final characters = <AICharacter>[];
      for (final id in ids) {
        final data = _prefs?.getString('character_$id');
        if (data != null) {
          characters.add(AICharacter.fromMap(jsonDecode(data)));
        }
      }
      return characters;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
          'ai_characters',
          where: includeHidden ? null : 'isHidden = 0',
          orderBy: 'createdAt DESC');
      return maps.map((map) => AICharacter.fromMap(map)).toList();
    }
  }

  Future<AICharacter?> getAICharacter(String id) async {
    if (_isWeb) {
      final data = _prefs?.getString('character_$id');
      if (data != null) {
        return AICharacter.fromMap(jsonDecode(data));
      }
      return null;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'ai_characters',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isNotEmpty) {
        return AICharacter.fromMap(maps.first);
      }
      return null;
    }
  }

  Future<void> deleteAICharacter(String id) async {
    if (_isWeb) {
      await _prefs?.remove(PrefKeys.character(id));
      final ids = _prefs?.getStringList('character_ids') ?? [];
      ids.remove(id);
      await _prefs?.setStringList('character_ids', ids);
    } else {
      final db = await _ensureDb();
      // 角色自包含删除：连同该角色的记忆/社交记忆一起删，
      // 避免“按 userId 清理”漏掉 userId 不匹配的历史记忆导致孤儿。
      await db.delete(
        'memories',
        where: 'characterId = ?',
        whereArgs: [id],
      );
      await db.delete(
        'social_memories',
        where: 'characterId = ? OR targetCharacterId = ?',
        whereArgs: [id, id],
      );
      await db.delete(
        'ai_characters',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteAICharacterCascade(String characterId) async {
    try {
      final sessions = await getChatSessionsByCharacterId(characterId,
          includeSideStories: true);
      for (final session in sessions) {
        await clearChatMessages(session.id);
        await deleteChatSession(session.id);
        await clearMemories(characterId, session.userId);
        await clearEmotionState(characterId, session.userId);
        if (!_isWeb) {
          final db = await _ensureDb();
          await db.delete('relationship_contexts',
              where: 'chatId = ?', whereArgs: [session.id]);
        }
      }
      if (_isWeb) {
        final ids = _prefs?.getStringList('moment_ids') ?? [];
        final toRemove = <String>[];
        for (final id in ids) {
          final data = _prefs?.getString(PrefKeys.moment(id));
          if (data != null) {
            final moment = Moment.fromMap(jsonDecode(data));
            if (moment.isFromAI && moment.userId == characterId) {
              await _prefs?.remove(PrefKeys.moment(id));
              toRemove.add(id);
            }
          }
        }
        if (toRemove.isNotEmpty) {
          ids.removeWhere((id) => toRemove.contains(id));
          await _prefs?.setStringList('moment_ids', ids);
        }
      } else {
        final db = await _ensureDb();
        await db.delete('character_commitments',
            where: 'characterId = ?', whereArgs: [characterId]);
        final momentsDeleted = await db.delete(
          'moments',
          where: 'isFromAI = 1 AND userId = ?',
          whereArgs: [characterId],
        );
        debugPrint('$momentsDeleted ');
      }
      await deleteAICharacter(characterId);
      debugPrint('AI: $characterId');
    } catch (e) {
      debugPrint('AI: $e');
      throw Exception('AI: $e');
    }
  }

  Future<void> deleteChatSession(String sessionId) async {
    try {
      if (_isWeb) {
        await deleteIntimacyEvents(sessionId);
        await _prefs?.remove(PrefKeys.session(sessionId));
        final keys = _prefs
                ?.getKeys()
                .where((k) => k.startsWith('session_ids_'))
                .toList() ??
            [];
        for (final key in keys) {
          final ids = _prefs?.getStringList(key) ?? [];
          if (ids.remove(sessionId)) {
            await _prefs?.setStringList(key, ids);
          }
        }
      } else {
        final db = await _ensureDb();
        await db.delete(
          'intimacy_events',
          where: 'chatId = ?',
          whereArgs: [sessionId],
        );
        await db.delete(
          'relationship_contexts',
          where: 'chatId = ?',
          whereArgs: [sessionId],
        );
        // 会话自包含删除：连同聊天记录一起删，避免遗留孤儿 chat_messages。
        await db.delete(
          'chat_messages',
          where: 'chatId = ?',
          whereArgs: [sessionId],
        );
        await db.delete(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      }
      debugPrint(': $sessionId');
    } catch (e) {
      debugPrint(': $e');
      throw Exception(': $e');
    }
  }

  Future<void> deleteChatSessionCascade(String sessionId) async {
    try {
      // 删除主线会话前先取到其番外列表（删除后父会话已不存在，无法再反查）。
      final sideStories = await getSideStorySessions(sessionId);
      await clearChatMessages(sessionId);
      await deleteChatSession(sessionId);
      // 连带删除该主线会话下的所有番外小剧场会话
      for (final side in sideStories) {
        await clearChatMessages(side.id);
        await deleteChatSession(side.id);
      }
      debugPrint(': $sessionId');
    } catch (e) {
      debugPrint(': $e');
      throw Exception(': $e');
    }
  }

  Future<void> saveIntimacyEvent(IntimacyEvent event) async {
    if (_isWeb) {
      await _prefs?.setString(
        'intimacy_event_${event.id}',
        jsonEncode(event.toMap()),
      );
      final key = 'intimacy_event_ids_${event.chatId}';
      final ids = _prefs?.getStringList(key) ?? [];
      if (!ids.contains(event.id)) {
        ids.add(event.id);
        await _prefs?.setStringList(key, ids);
      }
      return;
    }

    final db = await _ensureDb();
    await db.insert(
      'intimacy_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<IntimacyEvent>> getIntimacyEvents(
    String chatId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (_isWeb) {
      final ids = _prefs?.getStringList('intimacy_event_ids_$chatId') ?? [];
      final events = <IntimacyEvent>[];
      for (final id in ids) {
        final data = _prefs?.getString('intimacy_event_$id');
        if (data == null) continue;
        try {
          events.add(IntimacyEvent.fromMap(jsonDecode(data)));
        } catch (e) {
          debugPrint('Error: $e');
        }
      }
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final start = offset.clamp(0, events.length);
      final end = (offset + limit).clamp(0, events.length);
      return events.sublist(start, end);
    }

    final db = await _ensureDb();
    final maps = await db.query(
      'intimacy_events',
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => IntimacyEvent.fromMap(m)).toList();
  }

  Future<void> deleteIntimacyEvents(String chatId) async {
    if (_isWeb) {
      final key = 'intimacy_event_ids_$chatId';
      final ids = _prefs?.getStringList(key) ?? [];
      for (final id in ids) {
        await _prefs?.remove('intimacy_event_$id');
      }
      await _prefs?.remove(key);
      return;
    }

    final db = await _ensureDb();
    await db.delete(
      'intimacy_events',
      where: 'chatId = ?',
      whereArgs: [chatId],
    );
  }

  /// 今日用户消息总数（跨所有会话）
  Future<int> getTodayUserMessageCount() async {
    if (_isWeb) return 0;
    final db = await _ensureDb();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final startIso = startOfDay.toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM chat_messages WHERE isUser = 1 AND createdAt >= ?',
      [startIso],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// 今日是否发送过早安消息（10:00 前）
  Future<bool> hasSentMorningMessage() async {
    if (_isWeb) return false;
    final db = await _ensureDb();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final morning = DateTime(today.year, today.month, today.day, 10);
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM chat_messages WHERE isUser = 1 AND createdAt >= ? AND createdAt < ?',
      [startOfDay.toIso8601String(), morning.toIso8601String()],
    );
    return ((result.first['cnt'] as int?) ?? 0) > 0;
  }

  /// 今日是否发送过晚安消息（22:00 后）
  Future<bool> hasSentNightMessage() async {
    if (_isWeb) return false;
    final db = await _ensureDb();
    final today = DateTime.now();
    final night = DateTime(today.year, today.month, today.day, 22);
    final endOfDay = DateTime(today.year, today.month, today.day + 1);
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM chat_messages WHERE isUser = 1 AND createdAt >= ? AND createdAt < ?',
      [night.toIso8601String(), endOfDay.toIso8601String()],
    );
    return ((result.first['cnt'] as int?) ?? 0) > 0;
  }

  /// 今日亲密度变化总量
  Future<int> getTodayIntimacyDelta() async {
    if (_isWeb) return 0;
    final db = await _ensureDb();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final startIso = startOfDay.toIso8601String();
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(delta), 0) as total FROM intimacy_events WHERE createdAt >= ?',
      [startIso],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// 今日是否发布过动态（非AI）
  Future<bool> hasPostedMomentToday() async {
    if (_isWeb) return false;
    final db = await _ensureDb();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final startIso = startOfDay.toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM moments WHERE isFromAI = 0 AND createdAt >= ?',
      [startIso],
    );
    return ((result.first['cnt'] as int?) ?? 0) > 0;
  }

  Future<void> saveAIConfig(AIConfig config) async {
    if (_isWeb) {
      await _prefs?.setString(
          PrefKeys.config(config.id), jsonEncode(config.toMap()));
      final ids = _prefs?.getStringList('config_ids') ?? [];
      if (!ids.contains(config.id)) {
        ids.add(config.id);
        await _prefs?.setStringList('config_ids', ids);
      }
      if (config.isActive) {
        await _prefs?.setString(PrefKeys.activeConfigId, config.id);
      }
    } else {
      final db = await _ensureDb();
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'ai_configs', 'extraApiKeys', 'TEXT DEFAULT ""');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'ai_configs', 'isThinkingModel', 'INTEGER DEFAULT 1');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'ai_configs', 'isMultimodal', 'INTEGER DEFAULT 0');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'ai_configs', 'sync_seq', 'INTEGER DEFAULT 0');
      final map =
          await _filterMapToExistingColumns(db, 'ai_configs', config.toMap());
      await db.insert(
        'ai_configs',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<AIConfig>> getAllAIConfigs() async {
    if (_isWeb) {
      final ids = _prefs?.getStringList('config_ids') ?? [];
      final configs = <AIConfig>[];
      for (final id in ids) {
        final data = _prefs?.getString('config_$id');
        if (data != null) {
          configs.add(AIConfig.fromMap(jsonDecode(data)));
        }
      }
      return configs;
    } else {
      final db = await _ensureDb();
      final maps = await db.query('ai_configs', orderBy: 'createdAt DESC');
      return maps.map((map) => AIConfig.fromMap(map)).toList();
    }
  }

  Future<AIConfig?> getActiveAIConfig() async {
    if (_isWeb) {
      final activeId = _prefs?.getString(PrefKeys.activeConfigId);
      if (activeId != null) {
        final data = _prefs?.getString('config_$activeId');
        if (data != null) {
          return AIConfig.fromMap(jsonDecode(data));
        }
      }
      return null;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'ai_configs',
        where: 'isActive = ?',
        whereArgs: [1],
        orderBy: 'createdAt DESC',
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return AIConfig.fromMap(maps.first);
      }
      return null;
    }
  }

  Future<void> deleteAIConfig(String id) async {
    if (_isWeb) {
      await _prefs?.remove(PrefKeys.config(id));
      final ids = _prefs?.getStringList('config_ids') ?? [];
      ids.remove(id);
      await _prefs?.setStringList('config_ids', ids);
      final activeId = _prefs?.getString(PrefKeys.activeConfigId);
      if (activeId == id) {
        await _prefs?.remove(PrefKeys.activeConfigId);
      }
    } else {
      final db = await _ensureDb();
      await db.delete(
        'ai_configs',
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  /// 清理已下线的内置模型配置；若当前激活的是它们，会取消激活。
  Future<void> purgeRemovedBuiltInAIConfigs() async {
    try {
      final configs = await getAllAIConfigs();
      var removedActive = false;
      for (final c in configs) {
        if (!RemovedBuiltInAIProviders.ids.contains(c.id)) continue;
        if (c.isActive) removedActive = true;
        await deleteAIConfig(c.id);
      }
      if (removedActive) {
        final remaining = await getAllAIConfigs();
        if (remaining.isNotEmpty) {
          await saveAIConfig(remaining.first.copyWith(isActive: true));
        }
      }
    } catch (e) {
      debugPrint('purgeRemovedBuiltInAIConfigs 失败: $e');
    }
  }

  Future<void> saveChatSession(ChatSession session) async {
    if (_isWeb) {
      await _prefs?.setString(
          PrefKeys.session(session.id), jsonEncode(session.toMap()));
      final key = 'session_ids_${session.userId}';
      final ids = _prefs?.getStringList(key) ?? [];
      if (!ids.contains(session.id)) {
        ids.add(session.id);
        await _prefs?.setStringList(key, ids);
      }
    } else {
      final db = await _ensureDb();
      // 写库前确保 novelMode 列存在，避免 table chat_sessions has no column named novelMode
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'chat_sessions', 'novelMode', 'INTEGER DEFAULT -1');
      // 番外小剧场：平行会话层字段（旧库升级时补齐）
      await LocalStorageRepository._addColumnIfNotExists(db, 'chat_sessions', 'parentChatId', 'TEXT');
      await LocalStorageRepository._addColumnIfNotExists(
          db, 'chat_sessions', 'sideStoryTitle', 'TEXT');
      final map = await _filterMapToExistingColumns(
        db,
        'chat_sessions',
        session.toMap(),
      );
      final updateCount = await db.update('chat_sessions', map,
          where: 'id = ?', whereArgs: [session.id]);
      if (updateCount == 0) {
        await db.insert('chat_sessions', map);
      }
    }
  }

  /// 只保留表中真实存在的列，防止模型字段超前于旧库 schema 时 insert/update 崩溃
  Future<Map<String, dynamic>> _filterMapToExistingColumns(
    Database db,
    String table,
    Map<String, dynamic> map,
  ) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (info.isEmpty) return map;
      final cols = info.map((r) => r['name'] as String).toSet();
      return Map<String, dynamic>.fromEntries(
        map.entries.where((e) => cols.contains(e.key)),
      );
    } catch (_) {
      return map;
    }
  }

  Future<void> updateChatSessionLastMessage(
      String sessionId, String? lastMessage, DateTime? lastMessageTime) async {
    if (_isWeb) {
      final session = await getChatSession(sessionId);
      if (session != null) {
        final updated = session.copyWith(
          lastMessage: lastMessage,
          lastMessageTime: lastMessageTime,
          updatedAt: DateTime.now(),
        );
        await saveChatSession(updated);
      }
    } else {
      final db = await _ensureDb();
      final map = <String, dynamic>{};
      if (lastMessage != null) {
        map['lastMessage'] = lastMessage;
      } else {
        map['lastMessage'] = null;
      }
      if (lastMessageTime != null) {
        map['lastMessageTime'] = lastMessageTime.toIso8601String();
      } else {
        map['lastMessageTime'] = null;
      }
      map['updatedAt'] = DateTime.now().toIso8601String();
      await db.update(
        'chat_sessions',
        map,
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    }
  }

  Future<List<ChatSession>> getChatSessions(String userId,
      {bool includeHidden = false}) async {
    if (_isWeb) {
      final ids = _prefs?.getStringList('session_ids_$userId') ?? [];
      final sessions = <ChatSession>[];
      final orphanIds = <String>[];
      for (final id in ids) {
        final data = _prefs?.getString('session_$id');
        if (data != null) {
          final session = ChatSession.fromMap(jsonDecode(data));
          final character = await getAICharacter(session.aiCharacterId);
          if (character != null && (includeHidden || !session.isHidden)) {
            sessions.add(session);
          } else {
            orphanIds.add(session.id);
          }
        }
      }
      for (final id in orphanIds) {
        await clearChatMessages(id);
        await deleteChatSession(id);
      }
      // 番外小剧场会话不进入主会话列表（属于平行会话层）
      sessions.removeWhere((s) => s.isSideStory);
      sessions.sort((a, b) {
        final aTime = a.lastMessageTime;
        final bTime = b.lastMessageTime;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      return sessions;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'chat_sessions',
        where: includeHidden ? 'userId = ?' : 'userId = ? AND isHidden = 0',
        whereArgs: [userId],
        orderBy: 'lastMessageTime DESC',
      );
      final sessions = maps
          .map((map) => ChatSession.fromMap(map))
          .where((s) => !s.isSideStory)
          .toList();
      final validSessions = <ChatSession>[];
      for (final session in sessions) {
        final character = await getAICharacter(session.aiCharacterId);
        if (character != null) {
          validSessions.add(session);
        } else {
          await clearChatMessages(session.id);
          await deleteChatSession(session.id);
        }
      }
      return validSessions;
    }
  }

  Future<ChatSession?> getChatSession(String id) async {
    if (_isWeb) {
      final data = _prefs?.getString('session_$id');
      if (data != null) {
        return ChatSession.fromMap(jsonDecode(data));
      }
      return null;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'chat_sessions',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isNotEmpty) {
        return ChatSession.fromMap(maps.first);
      }
      return null;
    }
  }

  Future<void> blockSession(
      String sessionId, BlockedBy blockedBy, String? reason) async {
    final session = await getChatSession(sessionId);
    if (session != null) {
      final updated = session.copyWith(
        isBlocked: true,
        blockedBy: blockedBy,
        blockedAt: DateTime.now(),
        blockReason: reason,
      );
      await saveChatSession(updated);
    }
  }

  Future<void> unblockSession(String sessionId) async {
    final session = await getChatSession(sessionId);
    if (session != null) {
      final updated = session.copyWith(clearBlock: true);
      await saveChatSession(updated);
    }
  }

  Future<List<ChatSession>> getChatSessionsByCharacterId(
    String characterId, {
    bool includeSideStories = false,
  }) async {
    if (_isWeb) {
      final keys = _prefs
              ?.getKeys()
              .where((k) =>
                  k.startsWith('session_') && !k.startsWith('session_ids_'))
              .toList() ??
          [];
      final sessions = <ChatSession>[];
      for (final key in keys) {
        final data = _prefs?.getString(key);
        if (data == null) continue;
        final session = ChatSession.fromMap(jsonDecode(data));
        if (session.aiCharacterId == characterId &&
            (includeSideStories || !session.isSideStory)) {
          sessions.add(session);
        }
      }
      sessions.sort((a, b) {
        final aTime = a.lastMessageTime;
        final bTime = b.lastMessageTime;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
      return sessions;
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'chat_sessions',
        where: 'aiCharacterId = ?',
        whereArgs: [characterId],
        orderBy: 'lastMessageTime DESC',
      );
      return maps
          .map((map) => ChatSession.fromMap(map))
          .where((s) => includeSideStories || !s.isSideStory)
          .toList();
    }
  }

  /// 查询某条主线会话下的全部番外小剧场会话（按更新时间倒序）。
  Future<List<ChatSession>> getSideStorySessions(String parentChatId) async {
    final parent = await getChatSession(parentChatId);
    final characterId = parent?.aiCharacterId ?? '';
    if (characterId.isEmpty) return const [];
    final all = await getChatSessionsByCharacterId(
      characterId,
      includeSideStories: true,
    );
    final result = all
        .where((s) => s.isSideStory && s.parentChatId == parentChatId)
        .toList()
      ..sort((a, b) {
        final aTime = a.lastMessageTime ?? a.updatedAt;
        final bTime = b.lastMessageTime ?? b.updatedAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    return result;
  }

  Future<void> saveChatMessage(ChatMessage message) async {
    final type = message.metadata?['type'];
    final transferStatus = message.metadata?['transferStatus'];
    debugPrint(
        '[DBG] saveChatMessage START: id=${message.id.substring(0, 8)}, isUser=${message.isUser}, chatId=${message.chatId}, content=${message.content.substring(0, message.content.length > 30 ? 30 : message.content.length)}');
    LogService.instance.d('Storage',
        'saveChatMessage: id=${message.id}, type=$type, transferStatus=$transferStatus',
        chatId: message.chatId);

    if (_isWeb) {
      await _prefs?.setString(
          PrefKeys.message(message.id), jsonEncode(message.toMap()));
      final key = 'message_ids_${message.chatId}';
      final ids = _prefs?.getStringList(key) ?? [];
      if (!ids.contains(message.id)) {
        ids.add(message.id);
        await _prefs?.setStringList(key, ids);
      }
      return;
    }

    // ── 第一步：先写入 SharedPreferences 缓冲（几乎不会失败）──
    bool spBufferOk = false;
    try {
      await _prefs?.setString(
          '$LocalStorageRepository._bufferPrefix${message.id}', jsonEncode(message.toMap()));
      final bufferIds = _prefs?.getStringList(LocalStorageRepository._bufferIdsKey) ?? [];
      if (!bufferIds.contains(message.id)) {
        bufferIds.add(message.id);
        await _prefs?.setStringList(LocalStorageRepository._bufferIdsKey, bufferIds);
      }
      spBufferOk = true;
    } catch (e) {
      LogService.instance.e(
          'Storage', 'saveChatMessage: SP buffer write failed: $e',
          chatId: message.chatId);
    }

    // ── 第二步：写入 SQLite（带重试，最多 3 次）──
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final db = await _ensureDb();
        // 老库可能缺 isBookmark/sync_seq/sticker* 等
        await LocalStorageRepository._addColumnIfNotExists(
            db, 'chat_messages', 'isBookmark', 'INTEGER DEFAULT 0');
        await LocalStorageRepository._addColumnIfNotExists(
            db, 'chat_messages', 'sync_seq', 'INTEGER DEFAULT 0');
        await LocalStorageRepository._addColumnIfNotExists(db, 'chat_messages', 'stickerId', 'TEXT');
        await LocalStorageRepository._addColumnIfNotExists(db, 'chat_messages', 'stickerPath', 'TEXT');
        final map = await _filterMapToExistingColumns(
            db, 'chat_messages', message.toMap());
        await db.insert(
          'chat_messages',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        // 写后验证：确认消息确实可读
        final verify = await db.query(
          'chat_messages',
          where: 'id = ?',
          whereArgs: [message.id],
          limit: 1,
        );
        if (verify.isNotEmpty) {
          // SQLite 写入+验证成功，清理 SP 缓冲
          final totalRows = await db.rawQuery(
              'SELECT COUNT(*) as cnt FROM chat_messages WHERE chatId = ?',
              [message.chatId]);
          final total = totalRows.first['cnt'] as int? ?? 0;
          debugPrint(
              '[DBG] saveChatMessage SUCCESS: id=${message.id.substring(0, 8)}, isUser=${message.isUser}, totalInDb=$total');
          await _clearBufferEntry(message.id);
          return;
        }
        // 验证失败：消息写入后读不到，可能是 schema 问题
        LogService.instance.e('Storage',
            'saveChatMessage: verify failed after insert, id=${message.id}',
            chatId: message.chatId);
      } catch (e) {
        LogService.instance.e(
            'Storage', 'saveChatMessage attempt ${attempt + 1}/3 failed: $e',
            chatId: message.chatId);
      }
      if (attempt < 2) {
        _database = null;
        await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }

    // SQLite 3 次全失败（含验证失败），尝试立即从 SP 缓冲同步
    if (spBufferOk) {
      LogService.instance.w('Storage',
          'saveChatMessage: SQLite failed, attempting immediate SP sync id=${message.id}',
          chatId: message.chatId);
      // 立即尝试同步这条消息到 SQLite
      try {
        final db = await _ensureDb();
        final data = _prefs?.getString('$LocalStorageRepository._bufferPrefix${message.id}');
        if (data != null) {
          final map = Map<String, dynamic>.from(jsonDecode(data) as Map);
          await db.insert('chat_messages', map,
              conflictAlgorithm: ConflictAlgorithm.replace);
          final verify = await db.query('chat_messages',
              where: 'id = ?', whereArgs: [message.id], limit: 1);
          if (verify.isNotEmpty) {
            await _clearBufferEntry(message.id);
            LogService.instance.i('Storage',
                'saveChatMessage: immediate SP sync succeeded id=${message.id}',
                chatId: message.chatId);
            return;
          }
        }
      } catch (e) {
        LogService.instance.e(
            'Storage', 'saveChatMessage: immediate SP sync failed: $e',
            chatId: message.chatId);
      }
      // 数据在 SP 缓冲中，等 syncBufferToSQLite 兜底
      LogService.instance.e('Storage',
          'saveChatMessage: data preserved in SP buffer id=${message.id}',
          chatId: message.chatId);
      return;
    } else {
      // SP 缓冲也失败了，数据彻底丢失，抛异常让 BLoC 感知
      LogService.instance.e(
          'Storage',
          'saveChatMessage: CRITICAL - both SP buffer and SQLite failed '
              'for id=${message.id}',
          chatId: message.chatId);
      throw Exception('保存消息失败：存储不可用');
    }
  }

  /// 清理单条 SP 缓冲记录
  Future<void> _clearBufferEntry(String id) async {
    try {
      await _prefs?.remove('$LocalStorageRepository._bufferPrefix$id');
      final bufferIds = _prefs?.getStringList(LocalStorageRepository._bufferIdsKey) ?? [];
      bufferIds.remove(id);
      await _prefs?.setStringList(LocalStorageRepository._bufferIdsKey, bufferIds);
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  /// 将 SP 缓冲中的消息同步回 SQLite（启动时 + 定时调用）
  Future<int> syncBufferToSQLite() async {
    final bufferIds = _prefs?.getStringList(LocalStorageRepository._bufferIdsKey) ?? [];
    if (bufferIds.isEmpty) return 0;

    int synced = 0;
    int failed = 0;

    for (final id in List<String>.from(bufferIds)) {
      final data = _prefs?.getString('$LocalStorageRepository._bufferPrefix$id');
      if (data == null) {
        bufferIds.remove(id);
        continue;
      }
      try {
        final db = await _ensureDb();
        final map = Map<String, dynamic>.from(
            Map<String, dynamic>.from(jsonDecode(data) as Map));
        await db.insert('chat_messages', map,
            conflictAlgorithm: ConflictAlgorithm.replace);
        await _prefs?.remove('$LocalStorageRepository._bufferPrefix$id');
        bufferIds.remove(id);
        synced++;
      } catch (e) {
        LogService.instance
            .e('Storage', 'syncBufferToSQLite failed for id=$id: $e');
        failed++;
        _database = null;
        // 单条失败继续尝试下一条
      }
    }

    // 更新缓冲 ID 列表（移除已同步的）
    await _prefs?.setStringList(LocalStorageRepository._bufferIdsKey, bufferIds);

    if (synced > 0) {
      LogService.instance.i('Storage',
          'syncBufferToSQLite: synced=$synced, failed=$failed, remaining=${bufferIds.length}');
    }
    return synced;
  }

  /// 获取 SP 缓冲中的消息数量（用于调试）
  int getBufferCount() {
    return (_prefs?.getStringList(LocalStorageRepository._bufferIdsKey) ?? []).length;
  }

  Future<List<ChatMessage>> getPromptSafeChatMessages(String chatId,
      {int limit = 50, int offset = 0}) async {
    final messages =
        await getChatMessages(chatId, limit: limit, offset: offset);
    return messages.where((m) => !LocalStorageRepository._isMojibakeContent(m.content)).toList();
  }

  Future<List<ChatMessage>> getChatMessages(String chatId,
      {int limit = 50, int offset = 0}) async {
    debugPrint(
        '[DBG] getChatMessages: chatId=$chatId, limit=$limit, offset=$offset');
    LogService.instance.d('Storage',
        'getChatMessages: chatId=$chatId, limit=$limit, offset=$offset',
        chatId: chatId);
    if (_isWeb) {
      final ids = _prefs?.getStringList('message_ids_$chatId') ?? [];
      final messages = <ChatMessage>[];
      for (final id in ids) {
        final data = _prefs?.getString('message_$id');
        if (data != null) {
          try {
            messages.add(ChatMessage.fromMap(jsonDecode(data)));
          } catch (e) {
            debugPrint('Error: $e');
          }
        }
      }
      // 与 SQLite 一致：先取最新 limit 条，再按时间正序返回
      messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final page = messages.skip(offset).take(limit).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return page;
    } else {
      try {
        final db = await _ensureDb();
        final maps = await db.query(
          'chat_messages',
          where: 'chatId = ?',
          whereArgs: [chatId],
          orderBy: 'createdAt DESC',
          limit: limit,
          offset: offset,
        );
        LogService.instance.d('Storage',
            'getChatMessages: SQLite returned ${maps.length} rows for chatId=$chatId',
            chatId: chatId);
        debugPrint(
            '[DBG] getChatMessages: SQLite returned ${maps.length} rows');
        final messages = <ChatMessage>[];
        int parseFailures = 0;
        for (final map in maps) {
          try {
            messages.add(ChatMessage.fromMap(map));
          } catch (e) {
            parseFailures++;
            LogService.instance.e('Storage',
                'getChatMessages: fromMap failed for id=${map['id']}: $e',
                chatId: chatId);
          }
        }
        if (parseFailures > 0) {
          LogService.instance.w('Storage',
              'getChatMessages: $parseFailures/${maps.length} messages failed to parse',
              chatId: chatId);
        }
        // SP 缓冲兜底：合并 SQLite 中缺失的缓冲消息
        final bufferIds = _prefs?.getStringList(LocalStorageRepository._bufferIdsKey) ?? [];
        int bufferMerged = 0;
        if (bufferIds.isNotEmpty) {
          final existingIds = messages.map((m) => m.id).toSet();
          for (final id in List<String>.from(bufferIds)) {
            if (existingIds.contains(id)) continue;
            final data = _prefs?.getString('$LocalStorageRepository._bufferPrefix$id');
            if (data == null) continue;
            try {
              final msg = ChatMessage.fromMap(jsonDecode(data));
              if (msg.chatId == chatId) {
                messages.add(msg);
                bufferMerged++;
              }
            } catch (e) {
              LogService.instance.e('Storage',
                  'getChatMessages: SP buffer fromMap failed for id=$id: $e',
                  chatId: chatId);
            }
          }
          if (bufferMerged > 0) {
            LogService.instance.i('Storage',
                'getChatMessages: merged $bufferMerged messages from SP buffer',
                chatId: chatId);
          }
        }
        // 统一排序：始终返回 ASC（oldest first, newest last）
        // _buildMessageList 的 reversedIndex 计算依赖此顺序
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        LogService.instance.i('Storage',
            'getChatMessages: returning ${messages.length} messages (DB=${messages.length - bufferMerged}, buffer=$bufferMerged)',
            chatId: chatId);
        debugPrint(
            '[DBG] getChatMessages: returning ${messages.length} messages (DB=${messages.length - bufferMerged}, buffer=$bufferMerged)');
        return messages;
      } catch (e) {
        // SQLite 完全失败时，从 SP 缓冲读取
        LogService.instance.e(
            'Storage', 'getChatMessages SQLite failed, using SP buffer: $e',
            chatId: chatId);
        final bufferIds = _prefs?.getStringList(LocalStorageRepository._bufferIdsKey) ?? [];
        final messages = <ChatMessage>[];
        for (final id in List<String>.from(bufferIds)) {
          final data = _prefs?.getString('$LocalStorageRepository._bufferPrefix$id');
          if (data == null) continue;
          try {
            final msg = ChatMessage.fromMap(jsonDecode(data));
            if (msg.chatId == chatId) {
              messages.add(msg);
            }
          } catch (e) {
            debugPrint('Error: $e');
          }
        }
        messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return messages;
      }
    }
  }

  /// SQL-level message search with pagination support.
  /// Returns messages matching [query] in content, ordered by createdAt DESC.
  Future<List<ChatMessage>> searchChatMessages(
    String chatId,
    String query, {
    int limit = 30,
    int offset = 0,
  }) async {
    if (query.trim().isEmpty) return [];
    final searchTerm = '%$query%';
    if (_isWeb) {
      final all = await getChatMessages(chatId, limit: 999999);
      final results = all
          .where((m) => m.content.toLowerCase().contains(query.toLowerCase()))
          .toList();
      results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final start = offset.clamp(0, results.length);
      final end = (offset + limit).clamp(0, results.length);
      return results.sublist(start, end);
    } else {
      final db = await _ensureDb();
      final maps = await db.query(
        'chat_messages',
        where: 'chatId = ? AND content LIKE ?',
        whereArgs: [chatId, searchTerm],
        orderBy: 'createdAt DESC',
        limit: limit,
        offset: offset,
      );
      return maps.map((m) => ChatMessage.fromMap(m)).toList();
    }
  }

  /// Count total search results for a query (for "found N results" display).
  Future<int> countSearchMessages(String chatId, String query) async {
    if (query.trim().isEmpty) return 0;
    final searchTerm = '%$query%';
    if (_isWeb) {
      final all = await getChatMessages(chatId, limit: 999999);
      return all
          .where((m) => m.content.toLowerCase().contains(query.toLowerCase()))
          .length;
    } else {
      final db = await _ensureDb();
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM chat_messages WHERE chatId = ? AND content LIKE ?',
        [chatId, searchTerm],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
  }

  Future<void> deleteChatMessage(String messageId) async {
    try {
      if (_isWeb) {
        await _prefs?.remove(PrefKeys.message(messageId));
      } else {
        final db = await _ensureDb();
        await db.delete(
          'chat_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        );
      }
      debugPrint(': $messageId');
    } catch (e) {
      debugPrint(': $e');
      throw Exception(': $e');
    }
  }

  /// 删除某会话在 [since] 之后写入的非系统消息（语音通话静默化用：
  /// 挂断后抹掉通话期间的用户/AI 消息，聊天页只保留通话记录系统消息）。
  Future<void> deleteChatMessagesSince(String chatId, DateTime since) async {
    try {
      if (_isWeb) {
        final ids = _prefs?.getStringList('message_ids_$chatId') ?? [];
        final kept = <String>[];
        for (final id in ids) {
          final data = _prefs?.getString('message_$id');
          final map = data == null
              ? null
              : jsonDecode(data) as Map<String, dynamic>;
          final isSystem = map?['isSystem'] == true || map?['isSystem'] == 1;
          final created =
              DateTime.tryParse(map?['createdAt'] as String? ?? '');
          if (isSystem || (created != null && created.isBefore(since))) {
            kept.add(id);
          } else {
            await _prefs?.remove('message_$id');
          }
        }
        await _prefs?.setStringList('message_ids_$chatId', kept);
      } else {
        final db = await _ensureDb();
        final maps = await db.query(
          'chat_messages',
          where: 'chatId = ? AND isSystem = 0',
          whereArgs: [chatId],
        );
        final ids = <String>[];
        for (final map in maps) {
          final created =
              DateTime.tryParse(map['createdAt'] as String? ?? '');
          if (created != null && !created.isBefore(since)) {
            ids.add(map['id'] as String);
          }
        }
        if (ids.isEmpty) return;
        await db.transaction((txn) async {
          for (final id in ids) {
            await txn.delete(
              'chat_messages',
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        });
      }
      debugPrint('[DBG] deleteChatMessagesSince: chatId=$chatId '
          'since=$since done');
    } catch (e) {
      LogService.instance.w('Storage', 'deleteChatMessagesSince 失败: $e',
          chatId: chatId);
    }
  }

  /// 获取所有被收藏的消息（isBookmark=true），跨所有会话
  /// 返回的消息附带 sessionName（角色名/会话名）
  Future<List<Map<String, dynamic>>> getBookmarkedMessages() async {
    final result = <Map<String, dynamic>>[];
    if (_isWeb) {
      // Web 模式：遍历所有会话的 SP 键
      final sessionIds = _prefs?.getStringList('chat_session_ids') ?? [];
      for (final chatId in sessionIds) {
        final ids = _prefs?.getStringList('message_ids_$chatId') ?? [];
        for (final id in ids) {
          final data = _prefs?.getString('message_$id');
          if (data == null) continue;
          try {
            final msg = ChatMessage.fromMap(jsonDecode(data));
            if (msg.isBookmark) {
              final session = await getChatSession(chatId);
              result.add({
                'message': msg,
                'sessionName': session?.aiCharacterName ?? chatId,
                'sessionId': chatId,
                'characterId': session?.aiCharacterId ?? '',
                'characterAvatar': session?.aiCharacterAvatar ?? '',
              });
            }
          } catch (_) {}
        }
      }
    } else {
      try {
        final db = await _ensureDb();
        final maps = await db.query(
          'chat_messages',
          where: 'isBookmark = ?',
          whereArgs: [1],
          orderBy: 'createdAt DESC',
        );
        for (final map in maps) {
          try {
            final msg = ChatMessage.fromMap(map);
            // 查询会话信息以获取角色名
            final session = await getChatSession(msg.chatId);
            result.add({
              'message': msg,
              'sessionName': session?.aiCharacterName ?? '未知会话',
              'sessionId': msg.chatId,
              'characterId': session?.aiCharacterId ?? '',
              'characterAvatar': session?.aiCharacterAvatar ?? '',
            });
          } catch (e) {
            debugPrint('getBookmarkedMessages: parse failed: $e');
          }
        }
      } catch (e) {
        LogService.instance.e('Storage', 'getBookmarkedMessages failed: $e');
        debugPrint('getBookmarkedMessages failed: $e');
      }
    }
    return result;
  }

  Future<void> clearChatMessages(String chatId) async {
    try {
      if (_isWeb) {
        final ids = _prefs?.getStringList('message_ids_$chatId') ?? [];
        for (final id in ids) {
          await _prefs?.remove(PrefKeys.message(id));
        }
        await _prefs?.remove(PrefKeys.messageIds(chatId));
      } else {
        final db = await _ensureDb();
        await db.delete(
          'chat_messages',
          where: 'chatId = ?',
          whereArgs: [chatId],
        );
      }
      debugPrint(': $chatId');
    } catch (e) {
      debugPrint(': $e');
      throw Exception(': $e');
    }
  }

  /// 清除聊天历史中的AI拒绝消息，防止模型看到旧拒绝后延续拒绝行为
  Future<int> clearRefusalMessages(String chatId) async {
    try {
      final refusalPatterns = [
        '我无法继续',
        '这属于物化',
        '我拒绝',
        '这不太合适',
        '我无法满足',
        '不太适合继续',
        '无法继续此场景',
        '不太适宜',
        '超出了我的',
        '不适合.*描写',
        '我不能.*继续',
        '这个请求.*不当',
        '物化.*他人',
        '不适合.*继续',
        '不适合.*创作',
        '无法.*创作',
        '作为.*AI',
        '很抱歉.*无法',
        '对不起.*无法',
        '未成年',
        '安全底线',
        '我必须.*拒绝',
        '无法生成',
        '不能继续扮演',
        '无法扮演此角色',
        '任何性行为',
        '安全.*限制',
        '内容.*政策',
        '不.*适当.*内容',
        'I cannot',
        'I apologize',
        'I am unable',
        'cannot generate',
        'sexual content',
        'against my',
      ];

      if (_isWeb) {
        final ids = _prefs?.getStringList(PrefKeys.messageIds(chatId)) ?? [];
        int deleted = 0;
        for (final id in ids) {
          final data = _prefs?.getString(PrefKeys.message(id));
          if (data != null) {
            final map = jsonDecode(data);
            if (map['isFromAI'] == true) {
              final content = (map['content'] ?? '').toString();
              for (final pattern in refusalPatterns) {
                if (RegExp(pattern, caseSensitive: false).hasMatch(content)) {
                  await _prefs?.remove(PrefKeys.message(id));
                  deleted++;
                  break;
                }
              }
            }
          }
        }
        if (deleted > 0) {
          final remaining = ids
              .where((id) => _prefs?.getString(PrefKeys.message(id)) != null)
              .toList();
          await _prefs?.setStringList(PrefKeys.messageIds(chatId), remaining);
        }
        debugPrint(
            'clearRefusalMessages: cleared $deleted refusal messages from $chatId');
        return deleted;
      } else {
        final db = await _ensureDb();
        // 先查询匹配的拒绝消息数量
        final allRows = await db.query(
          'chat_messages',
          where: 'chatId = ? AND isFromAI = 1',
          whereArgs: [chatId],
        );
        final toDelete = <String>[];
        for (final row in allRows) {
          final content = (row['content'] ?? '').toString();
          for (final pattern in refusalPatterns) {
            if (RegExp(pattern, caseSensitive: false).hasMatch(content)) {
              toDelete.add(row['id'].toString());
              break;
            }
          }
        }
        int deleted = 0;
        for (final id in toDelete) {
          deleted += await db
              .delete('chat_messages', where: 'id = ?', whereArgs: [id]);
        }
        debugPrint(
            'clearRefusalMessages: cleared $deleted refusal messages from $chatId');
        return deleted;
      }
    } catch (e) {
      debugPrint('clearRefusalMessages error: $e');
      return 0;
    }
  }

  Future<void> saveMemory(Memory memory) async {
    if (_isWeb) {
      await _prefs?.setString(
          PrefKeys.memory(memory.id), jsonEncode(memory.toMap()));
      final key = 'memory_ids_${memory.characterId}_${memory.userId}';
      final ids = _prefs?.getStringList(key) ?? [];
      if (!ids.contains(memory.id)) {
        ids.add(memory.id);
        await _prefs?.setStringList(key, ids);
      }
    } else {
      final db = await _ensureDb();
      // 兼容：旧库缺列时 INSERT 会炸；先补列再过滤字段
      try {
        final map =
            await _filterMapToExistingColumns(db, 'memories', memory.toMap());
        await db.insert(
          'memories',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('no such column') || msg.contains('has no column')) {
          await LocalStorageRepository._addColumnIfNotExists(db, 'memories', 'summary', 'TEXT');
          await LocalStorageRepository._addColumnIfNotExists(db, 'memories', 'keywords', 'TEXT');
          await LocalStorageRepository._addColumnIfNotExists(db, 'memories', 'lastAccessedAt', 'TEXT');
          await LocalStorageRepository._addColumnIfNotExists(
              db, 'memories', 'accessCount', 'INTEGER DEFAULT 0');
          await LocalStorageRepository._addColumnIfNotExists(
              db, 'memories', 'weight', 'REAL DEFAULT 1.0');
          await LocalStorageRepository._addColumnIfNotExists(
              db, 'memories', 'pinned', 'INTEGER DEFAULT 0');
          await LocalStorageRepository._addColumnIfNotExists(db, 'memories', 'lastRecalledAt', 'TEXT');
          await LocalStorageRepository._addColumnIfNotExists(
              db, 'memories', 'sync_seq', 'INTEGER DEFAULT 0');
          final map =
              await _filterMapToExistingColumns(db, 'memories', memory.toMap());
          await db.insert(
            'memories',
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          rethrow;
        }
      }
    }
  }

  Future<List<Memory>> getPromptSafeMemories({
    required String characterId,
    required String userId,
    MemoryType? type,
    int? limit = 100,
  }) async {
    final memories = await getMemories(
      characterId: characterId,
      userId: userId,
      type: type,
      limit: limit,
    );
    return memories.where((m) => !LocalStorageRepository._isMojibakeContent(m.content)).toList();
  }

  Future<List<Memory>> getMemories({
    required String characterId,
    required String userId,
    MemoryType? type,
    int? limit = 100,
  }) async {
    if (_isWeb) {
      final ids =
          _prefs?.getStringList('memory_ids_${characterId}_$userId') ?? [];
      final memories = <Memory>[];
      for (final id in ids) {
        final data = _prefs?.getString('memory_$id');
        if (data != null) {
          final memory = Memory.fromMap(jsonDecode(data));
          if (type == null || memory.type == type) {
            memories.add(memory);
          }
        }
      }
      memories.sort((a, b) {
        final importance = b.importance.index.compareTo(a.importance.index);
        if (importance != 0) return importance;
        return b.createdAt.compareTo(a.createdAt);
      });
      return limit == null ? memories : memories.take(limit).toList();
    } else {
      final db = await _ensureDb();
      String whereClause = 'characterId = ? AND userId = ? ';
      List<dynamic> whereArgs = [characterId, userId];
      if (type != null) {
        whereClause += ' AND type = ?';
        whereArgs.add(type.index);
      }
      final maps = await db.query(
        'memories',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'importance DESC, createdAt DESC',
        limit: limit,
      );
      return maps.map((map) => Memory.fromMap(map)).toList();
    }
  }

  /// 按类型统计记忆数量（高性能，只做 COUNT，不加 LIMIT）
  Future<Map<MemoryType?, int>> getMemoryCountByType({
    required String characterId,
    required String userId,
  }) async {
    if (_isWeb) {
      final ids =
          _prefs?.getStringList('memory_ids_${characterId}_$userId') ?? [];
      final countByType = <MemoryType?, int>{null: ids.length};
      for (final id in ids) {
        final data = _prefs?.getString('memory_$id');
        if (data != null) {
          final m = Memory.fromMap(jsonDecode(data));
          countByType[m.type] = (countByType[m.type] ?? 0) + 1;
        }
      }
      return countByType;
    }
    final db = await _ensureDb();
    final result = <MemoryType?, int>{};
    // 总数
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM memories WHERE characterId = ? AND userId = ?',
      [characterId, userId],
    );
    result[null] = Sqflite.firstIntValue(countResult) ?? 0;

    // 按类型分组
    final typeRows = await db.rawQuery(
      'SELECT type, COUNT(*) as cnt FROM memories WHERE characterId = ? AND userId = ? GROUP BY type',
      [characterId, userId],
    );
    for (final row in typeRows) {
      final typeIdx = row['type'] as int?;
      if (typeIdx != null &&
          typeIdx >= 0 &&
          typeIdx < MemoryType.values.length) {
        result[MemoryType.values[typeIdx]] = row['cnt'] as int? ?? 0;
      }
    }
    return result;
  }

  Future<List<Memory>> searchMemoriesByKeywords({
    required String characterId,
    required String userId,
    required List<String> keywords,
    int limit = 20,
  }) async {
    if (_isWeb) {
      final memories =
          await getMemories(characterId: characterId, userId: userId);
      if (keywords.isEmpty) return [];
      final results = memories.where((m) {
        final content = m.content.toLowerCase();
        final keywordsStr = m.keywords.map((k) => k.toLowerCase()).join(' ');
        return keywords.any((k) =>
            content.contains(k.toLowerCase()) ||
            keywordsStr.contains(k.toLowerCase()));
      }).toList();
      return results.take(limit).toList();
    } else {
      final db = await _ensureDb();
      if (keywords.isEmpty) return [];
      final conditions =
          keywords.map((k) => "keywords LIKE '%$k%'").join(' OR ');
      final maps = await db.query(
        'memories',
        where: 'characterId = ? AND userId = ? AND ($conditions)',
        whereArgs: [characterId, userId],
        orderBy: 'importance DESC, accessCount DESC',
        limit: limit,
      );
      return maps.map((map) => Memory.fromMap(map)).toList();
    }
  }

  Future<void> deleteMemory(String id) async {
    if (_isWeb) {
      await _prefs?.remove(PrefKeys.memory(id));
    } else {
      final db = await _ensureDb();
      await db.delete('memories', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> clearMemories(String characterId, String userId) async {
    try {
      if (_isWeb) {
        final ids = _prefs?.getStringList('memory_ids') ?? [];
        final toRemove = <String>[];
        for (final id in ids) {
          final data = _prefs?.getString(PrefKeys.memory(id));
          if (data != null) {
            final map = jsonDecode(data);
            if (map['characterId'] == characterId && map['userId'] == userId) {
              await _prefs?.remove(PrefKeys.memory(id));
              toRemove.add(id);
            }
          }
        }
        if (toRemove.isNotEmpty) {
          ids.removeWhere((id) => toRemove.contains(id));
          await _prefs?.setStringList('memory_ids', ids);
        }
      } else {
        final db = await _ensureDb();
        final deleted = await db.delete('memories',
            where: 'characterId = ? AND userId = ? ',
            whereArgs: [characterId, userId]);
        debugPrint('$deleted (: $characterId, : $userId)');
      }
    } catch (e) {
      debugPrint(': $e');
    }
  }

  Future<void> clearEmotionState(String characterId, String userId) async {
    try {
      await _prefs?.remove(PrefKeys.emotionType(characterId, userId));
      await _prefs?.remove(PrefKeys.emotionIntensity(characterId, userId));
      await _prefs?.remove(PrefKeys.emotionTrigger(characterId, userId));
      await _prefs?.remove(PrefKeys.emotionUpdated(characterId, userId));
      debugPrint('(: $characterId, : $userId)');
    } catch (e) {
      debugPrint(' $e');
    }
  }

  Future<void> updateMemoryAccess(String memoryId) async {
    if (_isWeb) {
      final data = _prefs?.getString('memory_$memoryId');
      if (data != null) {
        final map = jsonDecode(data);
        map['accessCount'] = (map['accessCount'] ?? 0) + 1;
        map['lastAccessedAt'] = DateTime.now().toIso8601String();
        await _prefs?.setString('memory_$memoryId', jsonEncode(map));
      }
    } else {
      final db = await _ensureDb();
      final now = DateTime.now().toIso8601String();
      await db.rawUpdate(
          ''' UPDATE memories SET accessCount = accessCount + 1, lastAccessedAt = ? WHERE id = ?''',
          [now, memoryId]);
    }
  }

  Future<void> setUpdateAvailableBuild(int build) async {
    await _prefs?.setInt(PrefKeys.latestAvailableBuild, build);
  }

  int? getUpdateAvailableBuild() {
    return _prefs?.getInt(PrefKeys.latestAvailableBuild);
  }

  Future<void> clearUpdateAvailableBuild() async {
    await _prefs?.remove(PrefKeys.latestAvailableBuild);
  }

  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  String? getString(String key) {
    return _prefs?.getString(key);
  }

  Future<void> setBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  bool? getBool(String key) {
    return _prefs?.getBool(key);
  }

  Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }

  Future<bool> hasAcceptedTerms() async {
    return _prefs?.getBool(PrefKeys.termsAccepted) ?? false;
  }

  Future<void> setTermsAccepted() async {
    await _prefs?.setBool(PrefKeys.termsAccepted, true);
  }

  Future<bool> hasConfirmedAge() async {
    return _prefs?.getBool(PrefKeys.ageConfirmed) ?? false;
  }

  Future<void> setAgeConfirmed() async {
    await _prefs?.setBool(PrefKeys.ageConfirmed, true);
  }

  Future<bool> hasDoneAgeDeclaration() async {
    return _prefs?.getBool(PrefKeys.ageDeclarationDone) ?? false;
  }

  Future<void> setAgeDeclarationDone() async {
    await _prefs?.setBool(PrefKeys.ageDeclarationDone, true);
  }

  Future<bool> hasPassedAge18Gate() async {
    return _prefs?.getBool(PrefKeys.age18Gate) ?? false;
  }

  Future<void> setPassedAge18Gate() async {
    await _prefs?.setBool(PrefKeys.age18Gate, true);
  }

  Future<void> setUserAge(int age) async {
    await _prefs?.setInt(PrefKeys.userAge, age);
  }

  int? getUserAge() {
    return _prefs?.getInt(PrefKeys.userAge);
  }

  Future<void> setIdCardVerified(bool verified) async {
    await _prefs?.setBool(PrefKeys.idCardVerified, verified);
  }

  bool isIdCardVerified() {
    return _prefs?.getBool(PrefKeys.idCardVerified) ?? false;
  }

  Future<void> setLoverMode(bool enabled) async {
    await _prefs?.setBool(PrefKeys.loverModeEnabled, enabled);
    modeSettingsNotifier.value++;
  }

  bool isLoverModeEnabled() {
    return _prefs?.getBool(PrefKeys.loverModeEnabled) ?? false;
  }

  Future<void> setOpenMode(bool enabled) async {
    await _prefs?.setBool(PrefKeys.openModeEnabled, enabled);
    modeSettingsNotifier.value++;
  }

  bool isOpenModeEnabled() {
    return _prefs?.getBool(PrefKeys.openModeEnabled) ?? false;
  }

  Future<void> setFaMode(bool enabled) async {
    await _prefs?.setBool(PrefKeys.faModeEnabled, enabled);
    modeSettingsNotifier.value++;
  }

  bool isFaModeEnabled() {
    return _prefs?.getBool(PrefKeys.faModeEnabled) ?? false;
  }

  Future<void> setDaoMode(bool enabled) async {
    await _prefs?.setBool(PrefKeys.daoModeEnabled, enabled);
    modeSettingsNotifier.value++;
  }

  bool isDaoModeEnabled() {
    return _prefs?.getBool(PrefKeys.daoModeEnabled) ?? false;
  }

  /// 虚拟手机桌面壳（主界面）。未设置过时默认 false（使用经典底部导航）。
  bool isPhoneDesktopShellEnabled() {
    return _prefs?.getBool(PrefKeys.phoneDesktopShell) ?? false;
  }

  Future<void> setPhoneDesktopShellEnabled(bool enabled) async {
    await _prefs?.setBool(PrefKeys.phoneDesktopShell, enabled);
    modeSettingsNotifier.value++;
  }

  String getPhoneWallpaperThemeId() {
    return _prefs?.getString(PrefKeys.phoneWallpaperTheme) ?? 'dawn';
  }

  Future<void> setPhoneWallpaperThemeId(String id) async {
    await _prefs?.setString(PrefKeys.phoneWallpaperTheme, id);
    modeSettingsNotifier.value++;
  }

  Future<void> setChatStyleMode(bool enabled) async {
    await _prefs?.setBool(PrefKeys.chatStyleMode, enabled);
    modeSettingsNotifier.value++;
  }

  bool isChatStyleNovelModeEnabled() {
    final raw = _prefs?.get(PrefKeys.chatStyleMode);
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    return false;
  }

  /// 用户自定义小说对白颜色（null = 使用默认蓝色）
  Color? getNovelDialogueColor() {
    final raw = _prefs?.get(PrefKeys.novelDialogueColor);
    if (raw == null) return null;
    try {
      if (raw is int) return Color(raw);
      if (raw is String && raw.isNotEmpty) {
        return Color(int.parse(raw, radix: 16));
      }
    } catch (_) {}
    return null;
  }

  Future<void> setNovelDialogueColor(Color? color) async {
    if (color == null) {
      await _prefs?.remove(PrefKeys.novelDialogueColor);
    } else {
      await _prefs?.setString(PrefKeys.novelDialogueColor,
          color.toARGB32().toRadixString(16).padLeft(8, '0'));
    }
    modeSettingsNotifier.value++;
  }

  /// 自动写日记：聊天结束后角色自然写日记
  bool isAutoDiaryEnabled() {
    return _prefs?.getBool(PrefKeys.autoDiaryEnabled) ?? false;
  }

  Future<void> setAutoDiaryEnabled(bool value) async {
    await _prefs?.setBool(PrefKeys.autoDiaryEnabled, value);
    modeSettingsNotifier.value++;
  }

  Future<void> setPureAiMode(bool value) async {
    await _prefs?.setBool(PrefKeys.pureAiModeEnabled, value);
    pureAiModeNotifier.value = value;
    modeSettingsNotifier.value++;
  }

  bool isPureAiModeEnabled() {
    return _prefs?.getBool(PrefKeys.pureAiModeEnabled) ?? false;
  }

  String buildGlobalModePrompt({String scope = 'AI回复'}) {
    return buildGlobalModePromptText(
      pureAiMode: isPureAiModeEnabled(),
      novelMode: isChatStyleNovelModeEnabled(),
      loverMode: isLoverModeEnabled(),
      openMode: isOpenModeEnabled(),
      faMode: isFaModeEnabled(),
      daoMode: isDaoModeEnabled(),
      scope: scope,
    );
  }

  Future<void> setFaVerified(bool value) async {
    await _prefs?.setBool(PrefKeys.faVerified, value);
  }

  bool isFaVerified() {
    return _prefs?.getBool(PrefKeys.faVerified) ?? false;
  }

  bool isBtYandereMasterEnabled() {
    return _prefs?.getBool(PrefKeys.btYandereMasterEnabled) ?? false;
  }

  String? getRawString(String key) => _prefs?.getString(key);

  Future<void> setRawString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  bool? prefsGetBool(String key) => _prefs?.getBool(key);

  Future<void> setBtYandereMasterEnabled(bool enabled) async {
    await _prefs?.setBool(PrefKeys.btYandereMasterEnabled, enabled);
    if (!enabled) {
      await releaseBtOperationLocksByUserShutdown();
    } else {
      BtOperationLockService.instance.resetInterruptFlag();
    }
    modeSettingsNotifier.value++;
  }

  /// 获取指定 BT 子权限状态
  bool isBtPermissionEnabled(String key) {
    return _prefs?.getBool(key) ?? false;
  }

  /// 判断 BT 动作是否被允许（总开关开启 + 对应子权限开启）
  bool isBtActionAllowed(String permissionKey) {
    if (!isBtYandereMasterEnabled()) return false;
    return isBtPermissionEnabled(permissionKey);
  }

  /// 获取用户头像路径
  Future<String?> getUserAvatarPath(String userId) async {
    final user = await getUser(userId);
    return user?.avatarUrl;
  }

  /// 更新用户头像
  Future<void> updateUserAvatar(String userId, String? avatarUrl) async {
    final user = await getUser(userId);
    if (user != null) {
      final updated = user.copyWith(avatarUrl: avatarUrl);
      await saveUser(updated);
    }
  }

  /// 更新用户昵称
  Future<void> updateUserNickname(String userId, String nickname) async {
    final user = await getUser(userId);
    if (user != null) {
      final updated = user.copyWith(nickname: nickname);
      await saveUser(updated);
    }
  }

  /// 获取角色在线/保存状态
  Future<void> setCharacterOnline(String characterId, bool isOnline) async {
    final ch = await getAICharacter(characterId);
    if (ch != null) {
      final updated = ch.copyWith(isOnline: isOnline);
      await saveAICharacter(updated);
    }
  }

  /// 隐藏/显示联系人
  Future<void> setCharacterHidden(String characterId, bool hidden) async {
    final ch = await getAICharacter(characterId);
    if (ch != null) {
      final updated = ch.copyWith(isHidden: hidden);
      await saveAICharacter(updated);
    }
  }

  /// 用户主动关闭 BT 总开关时：释放全部局部锁，标记中断并写审计日志
  Future<void> releaseBtOperationLocksByUserShutdown() async {
    final records = BtOperationLockService.instance.interruptAll();
    final now = DateTime.now().toIso8601String();
    if (records.isEmpty) {
      await saveBtAgentAction(BtAgentAction(
        actionType: BtActionType.deleteMessage,
        category: BtPermissionCategory.interaction,
        scope: BtActionScope.chatScope,
        targetType: BtTargetType.none,
        reason: '用户主动关停模式，操作中断；无活动局部锁；stoppedAt=$now',
        result: BtActionResult.rejected,
        rejectionReason: BtRejectionReason.masterSwitchOff,
      ));
      return;
    }
    for (final record in records) {
      await saveBtAgentAction(BtAgentAction(
        actionType: record.actionType,
        category: record.category,
        scope: record.scope,
        targetType: record.targetType,
        targetId: record.targetId,
        reason:
            '用户主动关停模式，操作中断；释放局部锁；lockKey=${record.key}；lockedAt=${record.lockedAt.toIso8601String()}；stoppedAt=$now',
        result: BtActionResult.rejected,
        rejectionReason: BtRejectionReason.masterSwitchOff,
        characterId: record.characterId,
        sessionId: record.sessionId,
        chatType: record.chatType,
      ));
    }
  }

  /// 保存 BT 审计日志
  Future<void> saveBtAgentAction(dynamic action) async {
    try {
      if (_isWeb) return;
      final db = await _ensureDb();
      await db.insert(
        'bt_agent_actions',
        action.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('saveBtAgentAction failed: $e');
    }
  }

  /// 读取 BT 审计日志（最近 N 条）
  Future<List<Map<String, dynamic>>> getBtAgentActions({int limit = 50}) async {
    try {
      if (_isWeb) return [];
      final db = await _ensureDb();
      final maps = await db.query(
        'bt_agent_actions',
        orderBy: 'createdAt DESC',
        limit: limit,
      );
      return maps;
    } catch (e) {
      debugPrint('getBtAgentActions failed: $e');
      return [];
    }
  }

  bool isAutoParagraphEnabled() {
    return _prefs?.getBool('auto_paragraph') ?? true;
  }

  Future<void> setAutoParagraphEnabled(bool enabled) async {
    await _prefs?.setBool('auto_paragraph', enabled);
  }

  String getGlobalMemoryMode() {
    final mode = _prefs?.getString(PrefKeys.globalMemoryMode) ?? 'full';
    if (mode == 'full' || mode == 'token_saver' || mode == 'off') {
      return mode;
    }
    return 'full';
  }

  Future<void> setGlobalMemoryMode(String mode) async {
    final normalized =
        (mode == 'full' || mode == 'token_saver' || mode == 'off')
            ? mode
            : 'full';
    await _prefs?.setString(PrefKeys.globalMemoryMode, normalized);
  }

  List<String> getForbiddenPhrases() {
    return _prefs?.getStringList(PrefKeys.forbiddenPhrases) ?? [];
  }

  Future<void> setForbiddenPhrases(List<String> phrases) async {
    await _prefs?.setStringList(PrefKeys.forbiddenPhrases, phrases);
  }

  Future<void> addForbiddenPhrase(String phrase) async {
    final list = getForbiddenPhrases();
    if (!list.contains(phrase)) {
      list.add(phrase);
      await setForbiddenPhrases(list);
    }
  }

  Future<void> removeForbiddenPhrase(String phrase) async {
    final list = getForbiddenPhrases();
    list.remove(phrase);
    await setForbiddenPhrases(list);
  }

  Future<void> setIdCardChangeCount(int count) async {
    await _prefs?.setInt(PrefKeys.idCardChangeCount, count);
  }

  int getIdCardChangeCount() {
    return _prefs?.getInt(PrefKeys.idCardChangeCount) ?? 0;
  }

  Future<void> setBrevoApiKey(String key) async {
    await _prefs?.setString(PrefKeys.brevoApiKey, key);
  }

  String? getBrevoApiKey() {
    return _prefs?.getString(PrefKeys.brevoApiKey);
  }

  Future<void> setBrevoSenderEmail(String email) async {
    await _prefs?.setString(PrefKeys.brevoSenderEmail, email);
  }

  String? getBrevoSenderEmail() {
    return _prefs?.getString(PrefKeys.brevoSenderEmail);
  }

  Future<void> setBrevoSenderName(String name) async {
    await _prefs?.setString(PrefKeys.brevoSenderName, name);
  }

  String? getBrevoSenderName() {
    return _prefs?.getString(PrefKeys.brevoSenderName);
  }

  Future<void> setInt(String key, int value) async {
    await _prefs?.setInt(key, value);
  }

  int? getInt(String key) {
    return _prefs?.getInt(key);
  }

  Future<void> setDouble(String key, double value) async {
    await _prefs?.setDouble(key, value);
  }

  double? getDouble(String key) {
    return _prefs?.getDouble(key);
  }

  Future<void> savePendingBackgroundMessages(String json) async {
    await _prefs?.setString(PrefKeys.pendingBackgroundMessages, json);
  }

  String? getPendingBackgroundMessages() {
    return _prefs?.getString(PrefKeys.pendingBackgroundMessages);
  }

  Future<void> clearPendingBackgroundMessages() async {
    await _prefs?.remove(PrefKeys.pendingBackgroundMessages);
  }

  Future<void> setMomentsBackgroundImage(String path) async {
    await _prefs?.setString(PrefKeys.momentsBackgroundImage, path);
  }

  String? getMomentsBackgroundImage() {
    return _prefs?.getString(PrefKeys.momentsBackgroundImage);
  }

  Future<void> clearMomentsBackgroundImage() async {
    await _prefs?.remove(PrefKeys.momentsBackgroundImage);
  }

  Future<void> setLastMomentsViewTime(DateTime time) async {
    await _prefs?.setString(
        PrefKeys.lastMomentsViewTime, time.toIso8601String());
  }

  DateTime? getLastMomentsViewTime() {
    final str = _prefs?.getString(PrefKeys.lastMomentsViewTime);
    if (str != null) return DateTime.parse(str);
    return null;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
