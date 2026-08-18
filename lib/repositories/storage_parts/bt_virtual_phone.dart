// LocalStorageRepository BT Agent 封装 / 虚拟手机 / 小说 / 群聊等表 CRUD。
// 本文件是 local_storage_repository.dart 的 part，与其共同构成一个库。

part of '../local_storage_repository.dart';

mixin LocalStorageRepositoryBtVPhoneApi on LocalStorageRepositoryMomentsShopApi {
  /// 插入系统消息到聊天记录
  Future<void> insertSystemChatMessage(String sessionId, String content) async {
    try {
      final db = await _ensureDb();
      await db.insert('chat_messages', {
        'id': const Uuid().v4(),
        'chatId': sessionId,
        'senderId': 'system',
        'senderName': '系统',
        'content': content,
        'isUser': 0,
        'isSystem': 1,
        'isHidden': 0,
        'isGhost': 0,
        'type': 'text',
        'status': 'sent',
        'createdAt': DateTime.now().toIso8601String(),
        'sync_seq': 0,
      });
    } catch (e) {
      debugPrint('insertSystemChatMessage failed: $e');
    }
  }

  /// BT: 以角色身份发布动态
  Future<void> btPostMoment(String characterId, String content) async {
    try {
      final ch = await getAICharacter(characterId);
      if (ch == null) return;
      final userId = getString(PrefKeys.currentUserId) ?? 'default';
      final moment = Moment(
        id: const Uuid().v4(),
        userId: userId,
        userName: ch.name,
        userAvatar: ch.avatarUrl,
        content: content,
        isFromAI: true,
        createdAt: DateTime.now(),
      );
      await saveMoment(moment);
    } catch (e) {
      debugPrint('btPostMoment failed: $e');
    }
  }

  /// BT: 隐藏动态
  Future<void> btHideMoment(String momentId) async {
    try {
      final db = await _ensureDb();
      await db.update('moments', {'isHidden': 1},
          where: 'id = ?', whereArgs: [momentId]);
    } catch (e) {
      debugPrint('btHideMoment failed: $e');
    }
  }

  /// BT: 评论动态
  Future<void> btCommentMoment(
      String momentId, String characterId, String comment) async {
    try {
      final ch = await getAICharacter(characterId);
      if (ch == null) return;
      final db = await _ensureDb();
      final maps =
          await db.query('moments', where: 'id = ?', whereArgs: [momentId]);
      if (maps.isEmpty) return;
      final moment = Moment.fromMap(maps.first);
      final newComment = MomentComment(
        id: const Uuid().v4(),
        userId: characterId,
        userName: ch.name,
        content: comment,
        createdAt: DateTime.now(),
      );
      final updatedComments = [...moment.comments, newComment];
      await db.update(
        'moments',
        {
          'comments':
              jsonEncode(updatedComments.map((c) => c.toMap()).toList()),
        },
        where: 'id = ?',
        whereArgs: [momentId],
      );
    } catch (e) {
      debugPrint('btCommentMoment failed: $e');
    }
  }

  /// BT: 清空角色相关动态
  Future<void> btClearCharacterMoments(String characterId) async {
    try {
      final db = await _ensureDb();
      await db.delete('moments',
          where: 'userId = ? AND isFromAI = 1', whereArgs: [characterId]);
    } catch (e) {
      debugPrint('btClearCharacterMoments failed: $e');
    }
  }

  /// BT: 发送信件
  Future<void> btSendLetter({
    required String fromId,
    required String toId,
    required String content,
  }) async {
    try {
      final ch = await getAICharacter(fromId);
      if (ch == null) return;
      final userId = getString(PrefKeys.currentUserId) ?? 'default';
      final letter = AILetter(
        id: const Uuid().v4(),
        userId: userId,
        characterId: fromId,
        characterName: ch.name,
        characterAvatar: ch.avatarUrl,
        recipientName: toId,
        title: '来自${ch.name}的信',
        content: content,
        isFromUser: false,
        createdAt: DateTime.now(),
      );
      await saveAILetter(letter);
    } catch (e) {
      debugPrint('btSendLetter failed: $e');
    }
  }

  /// BT: 清空角色相关信件
  Future<void> btClearCharacterLetters(String characterId) async {
    try {
      if (_isWeb) return;
      final db = await _ensureDb();
      await db.delete('ai_letters',
          where: 'characterId = ?', whereArgs: [characterId]);
    } catch (e) {
      debugPrint('btClearCharacterLetters failed: $e');
    }
  }

  /// BT: 创建日记（通过 SharedPreferences diaryEntriesV2）
  Future<void> btCreateDiary(String characterId, String content) async {
    try {
      final existing = getString(PrefKeys.diaryEntriesV2) ?? '[]';
      final List<dynamic> entries = jsonDecode(existing);
      entries.insert(0, {
        'id': const Uuid().v4(),
        'characterId': characterId,
        'content': content,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));
    } catch (e) {
      debugPrint('btCreateDiary failed: $e');
    }
  }

  /// BT: 修改日记
  Future<void> btModifyDiary(String diaryId, String content) async {
    try {
      final existing = getString(PrefKeys.diaryEntriesV2) ?? '[]';
      final List<dynamic> entries = jsonDecode(existing);
      for (int i = 0; i < entries.length; i++) {
        if (entries[i]['id'] == diaryId) {
          entries[i]['content'] = content;
          entries[i]['updatedAt'] = DateTime.now().toIso8601String();
          break;
        }
      }
      await setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));
    } catch (e) {
      debugPrint('btModifyDiary failed: $e');
    }
  }

  /// BT: 删除日记
  Future<void> btDeleteDiary(String diaryId) async {
    try {
      final existing = getString(PrefKeys.diaryEntriesV2) ?? '[]';
      final List<dynamic> entries = jsonDecode(existing);
      entries.removeWhere((e) => e['id'] == diaryId);
      await setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));
    } catch (e) {
      debugPrint('btDeleteDiary failed: $e');
    }
  }

  /// BT: 清空角色相关日记
  Future<void> btClearDiary(String characterId) async {
    try {
      final existing = getString(PrefKeys.diaryEntriesV2) ?? '[]';
      final List<dynamic> entries = jsonDecode(existing);
      entries.removeWhere((e) => e['characterId'] == characterId);
      await setString(PrefKeys.diaryEntriesV2, jsonEncode(entries));
    } catch (e) {
      debugPrint('btClearDiary failed: $e');
    }
  }

  Future<void> saveVirtualPhone(VirtualPhone phone) async {
    final db = await _ensureDb();
    await db.insert('virtual_phones', phone.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<VirtualPhone?> getVirtualPhoneByCharacter(String characterId) async {
    final db = await _ensureDb();
    final maps = await db.query('virtual_phones',
        where: 'characterId = ?', whereArgs: [characterId], limit: 1);
    return maps.isNotEmpty ? VirtualPhone.fromMap(maps.first) : null;
  }

  Future<VirtualPhone?> getVirtualPhone(String id) async {
    final db = await _ensureDb();
    final maps =
        await db.query('virtual_phones', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? VirtualPhone.fromMap(maps.first) : null;
  }

  /// 统计某角色与某用户之间「真实单聊」的可见消息累计数。
  /// 作为虚拟手机「生活推进」的活跃度信号（排除系统/隐藏/幽灵消息）。
  Future<int> countVisibleChatMessages(
      String characterId, String userId) async {
    try {
      final db = await _ensureDb();
      final sessions = await getChatSessionsByCharacterId(characterId);
      final mine = sessions.where((s) => s.userId == userId).toList();
      if (mine.isEmpty) return 0;
      var total = 0;
      for (final s in mine) {
        final rows = await db.rawQuery(
          "SELECT COUNT(*) AS c FROM chat_messages WHERE chatId = ? "
          "AND (isSystem IS NULL OR isSystem = 0) "
          "AND (isHidden IS NULL OR isHidden = 0) "
          "AND (isGhost IS NULL OR isGhost = 0)",
          [s.id],
        );
        total += Sqflite.firstIntValue(rows) ?? 0;
      }
      return total;
    } catch (e) {
      debugPrint('countVisibleChatMessages failed: $e');
      return 0;
    }
  }

  /// 清空某部手机的全部子内容（重新全量生成前调用）
  Future<void> clearVirtualPhoneContent(String phoneId) async {
    final db = await _ensureDb();
    final chats = await db.query('vp_chats',
        columns: ['id'], where: 'phoneId = ?', whereArgs: [phoneId]);
    for (final c in chats) {
      await db.delete('vp_chat_messages',
          where: 'chatId = ?', whereArgs: [c['id']]);
    }
    await db.delete('vp_chats', where: 'phoneId = ?', whereArgs: [phoneId]);
    await db.delete('vp_contacts', where: 'phoneId = ?', whereArgs: [phoneId]);
    await db.delete('vp_notes', where: 'phoneId = ?', whereArgs: [phoneId]);
    await db.delete('vp_moments', where: 'phoneId = ?', whereArgs: [phoneId]);
  }

  Future<void> deleteVirtualPhone(String id) async {
    final db = await _ensureDb();
    await clearVirtualPhoneContent(id);
    await db.delete('virtual_phones', where: 'id = ?', whereArgs: [id]);
  }

  // ---- 联系人 ----
  Future<void> saveVpContact(VpContact c) async {
    final db = await _ensureDb();
    await db.insert('vp_contacts', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<VpContact>> getVpContacts(String phoneId) async {
    final db = await _ensureDb();
    final maps = await db.query('vp_contacts',
        where: 'phoneId = ?',
        whereArgs: [phoneId],
        orderBy: 'pinned DESC, orderIndex ASC');
    return maps.map((m) => VpContact.fromMap(m)).toList();
  }

  // ---- 聊天线 + 消息 ----
  Future<void> saveVpChat(VpChat chat) async {
    final db = await _ensureDb();
    await db.insert('vp_chats', chat.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<VpChat>> getVpChats(String phoneId) async {
    final db = await _ensureDb();
    final maps = await db.query('vp_chats',
        where: 'phoneId = ?', whereArgs: [phoneId], orderBy: 'orderIndex ASC');
    return maps.map((m) => VpChat.fromMap(m)).toList();
  }

  Future<void> saveVpChatMessage(VpChatMessage m) async {
    final db = await _ensureDb();
    await db.insert('vp_chat_messages', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<VpChatMessage>> getVpChatMessages(String chatId) async {
    final db = await _ensureDb();
    final maps = await db.query('vp_chat_messages',
        where: 'chatId = ?', whereArgs: [chatId], orderBy: 'orderIndex ASC');
    return maps.map((m) => VpChatMessage.fromMap(m)).toList();
  }

  // ---- 备忘录 ----
  Future<void> saveVpNote(VpNote n) async {
    final db = await _ensureDb();
    await db.insert('vp_notes', n.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<VpNote>> getVpNotes(String phoneId) async {
    final db = await _ensureDb();
    final maps = await db.query('vp_notes',
        where: 'phoneId = ?', whereArgs: [phoneId], orderBy: 'orderIndex ASC');
    return maps.map((m) => VpNote.fromMap(m)).toList();
  }

  // ---- 动态 ----
  Future<void> saveVpMoment(VpMoment m) async {
    final db = await _ensureDb();
    await db.insert('vp_moments', m.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<VpMoment>> getVpMoments(String phoneId) async {
    final db = await _ensureDb();
    final maps = await db.query('vp_moments',
        where: 'phoneId = ?', whereArgs: [phoneId], orderBy: 'orderIndex ASC');
    return maps.map((m) => VpMoment.fromMap(m)).toList();
  }

  Future<void> saveNovel(Novel novel) async {
    final db = await _ensureDb();
    await db.insert('novels', novel.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Novel?> getNovel(String id) async {
    final db = await _ensureDb();
    final maps = await db.query('novels', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Novel.fromMap(maps.first);
  }

  Future<List<Novel>> getNovels(String userId) async {
    final db = await _ensureDb();
    final maps = await db.query(
      'novels',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'updatedAt DESC',
    );
    return maps.map((m) => Novel.fromMap(m)).toList();
  }

  Future<void> deleteNovel(String id) async {
    final db = await _ensureDb();
    await db.delete('novels', where: 'id = ?', whereArgs: [id]);
    // 级联删除章节
    await db.delete('novel_chapters', where: 'novelId = ?', whereArgs: [id]);
  }

  Future<void> saveNovelChapter(NovelChapter chapter) async {
    final db = await _ensureDb();
    await db.insert('novel_chapters', chapter.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<NovelChapter>> getNovelChapters(String novelId) async {
    final db = await _ensureDb();
    final maps = await db.query(
      'novel_chapters',
      where: 'novelId = ?',
      whereArgs: [novelId],
      orderBy: 'sortOrder ASC',
    );
    return maps.map((m) => NovelChapter.fromMap(m)).toList();
  }

  Future<void> deleteNovelChapter(String id) async {
    final db = await _ensureDb();
    await db.delete('novel_chapters', where: 'id = ?', whereArgs: [id]);
  }

  /// 保存群聊会话
  Future<void> saveGroupChatSession(GroupChatSession session) async {
    if (_isWeb) {
      await _prefs?.setString(
          'gc_session_${session.id}', jsonEncode(session.toJson()));
      return;
    }
    final db = await _ensureDb();
    // 按真实列过滤，避免历史脏表缺列/多列导致 INSERT 崩溃（对齐 shop_items 安全写入）
    final cols = await LocalStorageRepository.getTableColumns(db, 'group_chat_sessions');
    final map = session.toMap();
    final safe = <String, dynamic>{};
    for (final e in map.entries) {
      if (cols.contains(e.key)) safe[e.key] = e.value;
    }
    if (!safe.containsKey('id')) {
      throw StateError('group_chat_sessions insert missing id, cols=$cols');
    }
    // 兜底：补填表侧 NOT NULL 无默认值的列（如历史 participantIds），
    // 模型 toMap() 不含它，单靠列过滤无法兜住 → 'NOT NULL constraint failed'。
    await LocalStorageRepository._fillNotNullDefaults(db, 'group_chat_sessions', safe);
    await db.insert('group_chat_sessions', safe,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取群聊会话
  Future<GroupChatSession?> getGroupChatSession(String id) async {
    if (_isWeb) {
      final data = _prefs?.getString('gc_session_$id');
      if (data != null) {
        return GroupChatSession.fromJson(jsonDecode(data));
      }
      return null;
    }
    final db = await _ensureDb();
    final maps =
        await db.query('group_chat_sessions', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return GroupChatSession.fromMap(maps.first);
  }

  /// 获取用户的所有群聊会话
  Future<List<GroupChatSession>> getGroupChatSessions(String userId) async {
    if (_isWeb) {
      final keys = _prefs
              ?.getKeys()
              .where((k) => k.startsWith('gc_session_'))
              .toList() ??
          [];
      final sessions = <GroupChatSession>[];
      for (final key in keys) {
        final data = _prefs?.getString(key);
        if (data != null) {
          try {
            sessions.add(GroupChatSession.fromJson(jsonDecode(data)));
          } catch (_) {}
        }
      }
      sessions.sort((a, b) {
        final aTime = a.lastMessageTime ?? DateTime(0);
        final bTime = b.lastMessageTime ?? DateTime(0);
        return bTime.compareTo(aTime);
      });
      return sessions;
    }
    final db = await _ensureDb();
    final maps = await db.query(
      'group_chat_sessions',
      orderBy: 'lastMessageTime DESC',
    );
    return maps.map((m) => GroupChatSession.fromMap(m)).toList();
  }

  /// 删除群聊会话
  Future<void> deleteGroupChatSession(String groupId) async {
    if (_isWeb) {
      await _prefs?.remove('gc_session_$groupId');
      final messageKeys = _prefs
              ?.getKeys()
              .where((key) => key.startsWith('gc_msg_'))
              .toList() ??
          [];
      for (final key in messageKeys) {
        final data = _prefs?.getString(key);
        if (data == null) continue;
        try {
          if (GroupChatMessage.fromJson(jsonDecode(data)).groupId == groupId) {
            await _prefs?.remove(key);
          }
        } catch (_) {}
      }
      await _deleteWebGroupChatSummaries(groupId);
      final branchKeys = _prefs
              ?.getKeys()
              .where((key) => key.startsWith('group_branch_'))
              .toList() ??
          [];
      for (final key in branchKeys) {
        final data = _prefs?.getString(key);
        if (data == null) continue;
        try {
          final branch = GroupChatBranch.fromMap(jsonDecode(data));
          if (branch.groupId == groupId) await _prefs?.remove(key);
        } catch (_) {}
      }
      await _deleteWebGroupPublicEvents(groupId: groupId);
      return;
    }
    final db = await _ensureDb();
    await db
        .delete('group_chat_sessions', where: 'id = ?', whereArgs: [groupId]);
    // 级联删除消息
    await db.delete('group_chat_messages',
        where: 'groupId = ?', whereArgs: [groupId]);
    await db.delete('group_chat_summaries',
        where: 'groupId = ?', whereArgs: [groupId]);
    await db.delete('group_chat_branches',
        where: 'groupId = ?', whereArgs: [groupId]);
    await db.delete('group_public_event_memories',
        where: 'groupId = ?', whereArgs: [groupId]);
  }

  /// 保存群聊消息
  Future<void> saveGroupChatMessage(GroupChatMessage msg) async {
    if (_isWeb) {
      await _prefs?.setString('gc_msg_${msg.id}', jsonEncode(msg.toJson()));
      return;
    }
    final db = await _ensureDb();
    await db.insert('group_chat_messages', msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<GroupChatLorebookEntry>> getGroupChatLorebookEntries(
      String groupId,
      {String? chatId}) async {
    if (_isWeb) {
      final keys = _prefs?.getKeys().where((k) => k.startsWith('gc_lore_')) ??
          const <String>[];
      return keys
          .map((key) {
            final raw = _prefs?.getString(key);
            if (raw == null) return null;
            try {
              final entry = GroupChatLorebookEntry.fromMap(jsonDecode(raw));
              return entry.groupId == groupId &&
                      (chatId == null ||
                          entry.chatId == null ||
                          entry.chatId == chatId)
                  ? entry
                  : null;
            } catch (_) {
              return null;
            }
          })
          .whereType<GroupChatLorebookEntry>()
          .toList();
    }
    final db = await _ensureDb();
    final rows = await db.query('group_chat_lorebook_entries',
        where: 'groupId = ? AND (chatId IS NULL OR chatId = ?)',
        whereArgs: [groupId, chatId]);
    return rows.map(GroupChatLorebookEntry.fromMap).toList();
  }

  Future<void> saveGroupChatLorebookEntry(GroupChatLorebookEntry entry) async {
    if (_isWeb) {
      await _prefs?.setString('gc_lore_${entry.id}', jsonEncode(entry.toMap()));
      return;
    }
    final db = await _ensureDb();
    await db.insert('group_chat_lorebook_entries', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteGroupChatLorebookEntry(String id) async {
    if (_isWeb) {
      await _prefs?.remove('gc_lore_$id');
      return;
    }
    final db = await _ensureDb();
    await db.delete('group_chat_lorebook_entries',
        where: 'id = ?', whereArgs: [id]);
  }

  /// 获取群的全部聊天记录（分支）
  Future<List<GroupChatBranch>> getGroupChatBranches(String groupId) async {
    if (_isWeb) {
      final keys = _prefs
              ?.getKeys()
              .where((key) => key.startsWith('gc_branch_'))
              .toList() ??
          const <String>[];
      final branches = <GroupChatBranch>[];
      for (final key in keys) {
        final raw = _prefs?.getString(key);
        if (raw == null) continue;
        try {
          final branch = GroupChatBranch.fromMap(jsonDecode(raw));
          if (branch.groupId == groupId) branches.add(branch);
        } catch (_) {}
      }
      branches.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return branches;
    }
    final db = await _ensureDb();
    final maps = await db.query('group_chat_branches',
        where: 'groupId = ?', whereArgs: [groupId], orderBy: 'createdAt ASC');
    return maps.map(GroupChatBranch.fromMap).toList();
  }

  /// 新建聊天记录（分支）
  Future<GroupChatBranch> createGroupChatBranch(
      String groupId, String name) async {
    final branch = GroupChatBranch(
      branchId: 'br_${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      name: name,
      createdAt: DateTime.now(),
    );
    if (_isWeb) {
      await _prefs?.setString(
          'gc_branch_${branch.branchId}', jsonEncode(branch.toMap()));
    } else {
      final db = await _ensureDb();
      await db.insert('group_chat_branches', branch.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return branch;
  }

  /// Forks the current chat at a message and copies its visible prefix.
  Future<GroupChatBranch> createGroupChatBranchFromMessage({
    required String groupId,
    required String sourceChatId,
    required String forkMessageId,
    String name = '分支',
  }) async {
    final branch = GroupChatBranch(
      branchId: 'br_${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      name: name,
      createdAt: DateTime.now(),
      parentBranchId: sourceChatId,
      forkMessageId: forkMessageId,
      checkpointMessageId: forkMessageId,
    );
    if (!_isWeb) {
      final db = await _ensureDb();
      await db.insert('group_chat_branches', branch.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await _prefs?.setString(
          'gc_branch_${branch.branchId}', jsonEncode(branch.toMap()));
    }
    final source = await getGroupChatMessages(groupId,
        limit: 100000, chatId: sourceChatId);
    for (final message in source) {
      await saveGroupChatMessage(message.copyWith(
        id: '${branch.branchId}_${message.id}',
        chatId: branch.branchId,
        parentMessageId: message.parentMessageId ?? message.id,
      ));
      if (message.id == forkMessageId) break;
    }
    return branch;
  }

  /// 重命名聊天记录（分支）
  Future<void> renameGroupChatBranch(String branchId, String name) async {
    if (_isWeb) {
      final raw = _prefs?.getString('gc_branch_$branchId');
      if (raw == null) return;
      try {
        final branch = GroupChatBranch.fromMap(jsonDecode(raw));
        await _prefs?.setString('gc_branch_$branchId',
            jsonEncode(branch.copyWith(name: name).toMap()));
      } catch (_) {}
      return;
    }
    final db = await _ensureDb();
    await db.update('group_chat_branches', {'name': name},
        where: 'branchId = ?', whereArgs: [branchId]);
  }

  /// 删除聊天记录（分支）及其中消息
  Future<void> deleteGroupChatBranch(String groupId, String branchId) async {
    if (_isWeb) {
      await _prefs?.remove('gc_branch_$branchId');
      await deleteGroupChatSummary(groupId, branchId);
      await _deleteWebGroupPublicEvents(groupId: groupId, chatId: branchId);
      final messageKeys = _prefs
              ?.getKeys()
              .where((key) => key.startsWith('gc_msg_'))
              .toList() ??
          [];
      for (final key in messageKeys) {
        final data = _prefs?.getString(key);
        if (data == null) continue;
        try {
          final message = GroupChatMessage.fromJson(jsonDecode(data));
          if (message.groupId == groupId && message.chatId == branchId) {
            await _prefs?.remove(key);
          }
        } catch (_) {}
      }
      final loreKeys = _prefs
              ?.getKeys()
              .where((key) => key.startsWith('gc_lore_'))
              .toList() ??
          const <String>[];
      for (final key in loreKeys) {
        final raw = _prefs?.getString(key);
        if (raw == null) continue;
        try {
          final entry = GroupChatLorebookEntry.fromMap(jsonDecode(raw));
          if (entry.groupId == groupId && entry.chatId == branchId) {
            await _prefs?.remove(key);
          }
        } catch (_) {}
      }
      return;
    }
    final db = await _ensureDb();
    await db.delete('group_chat_branches',
        where: 'branchId = ?', whereArgs: [branchId]);
    await db.delete('group_chat_messages',
        where: 'groupId = ? AND chatId = ?', whereArgs: [groupId, branchId]);
    await db.delete('group_chat_summaries',
        where: 'groupId = ? AND chatId = ?', whereArgs: [groupId, branchId]);
    await db.delete('group_public_event_memories',
        where: 'groupId = ? AND chatId = ?', whereArgs: [groupId, branchId]);
    await db.delete('group_chat_lorebook_entries',
        where: 'groupId = ? AND chatId = ?', whereArgs: [groupId, branchId]);
  }

  /// 获取群聊消息列表（chatId 非空时按聊天记录过滤）
  Future<List<GroupChatMessage>> getGroupChatMessages(String groupId,
      {int limit = 100, int offset = 0, String? chatId}) async {
    if (_isWeb) {
      final keys =
          _prefs?.getKeys().where((k) => k.startsWith('gc_msg_')).toList() ??
              [];
      final messages = <GroupChatMessage>[];
      for (final key in keys) {
        final data = _prefs?.getString(key);
        if (data != null) {
          try {
            final msg = GroupChatMessage.fromJson(jsonDecode(data));
            if (msg.groupId == groupId &&
                (chatId == null ||
                    chatId.isEmpty ||
                    msg.chatId == chatId ||
                    (chatId == groupId && msg.chatId.isEmpty))) {
              messages.add(msg);
            }
          } catch (_) {}
        }
      }
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages.skip(offset).take(limit).toList();
    }
    final db = await _ensureDb();
    final maps = chatId != null && chatId.isNotEmpty
        ? await db.query(
            'group_chat_messages',
            where: 'groupId = ? AND chatId = ?',
            whereArgs: [groupId, chatId],
            orderBy: 'createdAt DESC',
            limit: limit,
            offset: offset,
          )
        : await db.query(
            'group_chat_messages',
            where: 'groupId = ?',
            whereArgs: [groupId],
            orderBy: 'createdAt DESC',
            limit: limit,
            offset: offset,
          );
    return maps.map((m) => GroupChatMessage.fromMap(m)).toList();
  }

  /// 删除群聊消息
  Future<void> deleteGroupChatMessage(String messageId) async {
    if (_isWeb) {
      await _prefs?.remove('gc_msg_$messageId');
      await _deleteWebGroupPublicEventsBySourceMessageId(messageId);
      return;
    }
    final db = await _ensureDb();
    await db
        .delete('group_chat_messages', where: 'id = ?', whereArgs: [messageId]);
    final rows = await db.query('group_public_event_memories',
        columns: ['id', 'sourceMessageIds']);
    for (final row in rows) {
      final raw = row['sourceMessageIds'];
      try {
        final ids = raw is String ? jsonDecode(raw) : raw;
        if (ids is List && ids.map((id) => id.toString()).contains(messageId)) {
          await db.delete('group_public_event_memories',
              where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (_) {}
    }
  }

  Future<GroupChatSummary?> getGroupChatSummary(
      String groupId, String chatId) async {
    if (_isWeb) {
      final data = _prefs
          ?.getString('group_summary_${groupSummaryKey(groupId, chatId)}');
      if (data == null) return null;
      try {
        return GroupChatSummary.fromMap(jsonDecode(data));
      } catch (_) {
        return null;
      }
    }
    final db = await _ensureDb();
    final rows = await db.query(
      'group_chat_summaries',
      where: 'groupId = ? AND chatId = ?',
      whereArgs: [groupId, chatId],
      limit: 1,
    );
    return rows.isEmpty ? null : GroupChatSummary.fromMap(rows.first);
  }

  Future<void> saveGroupChatSummary(GroupChatSummary summary) async {
    if (_isWeb) {
      await _prefs?.setString(
        'group_summary_${groupSummaryKey(summary.groupId, summary.chatId)}',
        jsonEncode(summary.toMap()),
      );
      return;
    }
    final db = await _ensureDb();
    await db.insert(
      'group_chat_summaries',
      summary.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteGroupChatSummary(String groupId, String chatId) async {
    if (_isWeb) {
      await _prefs?.remove('group_summary_${groupSummaryKey(groupId, chatId)}');
      return;
    }
    final db = await _ensureDb();
    await db.delete(
      'group_chat_summaries',
      where: 'groupId = ? AND chatId = ?',
      whereArgs: [groupId, chatId],
    );
  }

  Future<void> saveGroupPublicEventMemory(GroupPublicEventMemory memory) async {
    if (_isWeb) {
      await _prefs?.setString(
          'group_event_${memory.id}', jsonEncode(memory.toMap()));
      return;
    }
    final db = await _ensureDb();
    await db.insert('group_public_event_memories', memory.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<GroupPublicEventMemory>> getGroupPublicEventMemories({
    required String characterId,
    String? groupId,
    String? chatId,
    int? limit,
  }) async {
    if (_isWeb) {
      final result = <GroupPublicEventMemory>[];
      for (final key
          in _prefs?.getKeys().where((k) => k.startsWith('group_event_')) ??
              const <String>[]) {
        final raw = _prefs?.getString(key);
        if (raw == null) continue;
        try {
          final memory = GroupPublicEventMemory.fromMap(jsonDecode(raw));
          if (memory.characterId == characterId &&
              (groupId == null || memory.groupId == groupId) &&
              (chatId == null || memory.chatId == chatId)) result.add(memory);
        } catch (_) {}
      }
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return limit == null ? result : result.take(limit).toList();
    }
    final db = await _ensureDb();
    final clauses = <String>['characterId = ?'];
    final args = <Object>[characterId];
    if (groupId != null) {
      clauses.add('groupId = ?');
      args.add(groupId);
    }
    if (chatId != null) {
      clauses.add('chatId = ?');
      args.add(chatId);
    }
    final rows = await db.query('group_public_event_memories',
        where: clauses.join(' AND '),
        whereArgs: args,
        orderBy: 'createdAt DESC',
        limit: limit);
    return rows.map(GroupPublicEventMemory.fromMap).toList();
  }

  Future<void> deleteGroupPublicEventMemory(String id) async {
    if (_isWeb) {
      await _prefs?.remove('group_event_$id');
      return;
    }
    final db = await _ensureDb();
    await db.delete('group_public_event_memories',
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateGroupPublicEventMemory(
      GroupPublicEventMemory memory) async {
    if (_isWeb) {
      await _prefs?.setString(
          'group_event_${memory.id}', jsonEncode(memory.toMap()));
      return;
    }
    final db = await _ensureDb();
    await db.update('group_public_event_memories', memory.toMap(),
        where: 'id = ?', whereArgs: [memory.id]);
  }

  Future<void> _deleteWebGroupPublicEvents(
      {required String groupId, String? chatId}) async {
    final keys = _prefs
            ?.getKeys()
            .where((key) => key.startsWith('group_event_'))
            .toList() ??
        [];
    for (final key in keys) {
      final raw = _prefs?.getString(key);
      if (raw == null) continue;
      try {
        final memory = GroupPublicEventMemory.fromMap(jsonDecode(raw));
        if (memory.groupId == groupId &&
            (chatId == null || memory.chatId == chatId)) {
          await _prefs?.remove(key);
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteWebGroupPublicEventsBySourceMessageId(
      String messageId) async {
    final keys =
        _prefs?.getKeys().where((k) => k.startsWith('group_event_')).toList() ??
            [];
    for (final key in keys) {
      final raw = _prefs?.getString(key);
      if (raw == null) continue;
      try {
        final memory = GroupPublicEventMemory.fromMap(jsonDecode(raw));
        if (memory.sourceMessageIds.contains(messageId)) {
          await _prefs?.remove(key);
        }
      } catch (_) {}
    }
  }

  Future<void> _deleteWebGroupChatSummaries(String groupId) async {
    final keys = _prefs
            ?.getKeys()
            .where((key) => key.startsWith('group_summary_'))
            .toList() ??
        [];
    for (final key in keys) {
      final data = _prefs?.getString(key);
      if (data == null) continue;
      try {
        if (GroupChatSummary.fromMap(jsonDecode(data)).groupId == groupId) {
          await _prefs?.remove(key);
        }
      } catch (_) {}
    }
  }
}
