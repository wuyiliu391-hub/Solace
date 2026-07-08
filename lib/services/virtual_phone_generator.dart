import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_character.dart';
import '../models/chat_session.dart';
import '../models/memory.dart';
import '../models/virtual_phone/virtual_phone.dart';
import '../models/virtual_phone/vp_contact.dart';
import '../models/virtual_phone/vp_chat.dart';
import '../models/virtual_phone/vp_note.dart';
import '../models/virtual_phone/vp_moment.dart';
import '../repositories/local_storage_repository.dart';
import 'ai_service.dart';
import 'growth_data_service.dart' show relationshipStage;
import 'memory_engine.dart';

/// 虚拟手机生成器
///
/// 依据 AI 角色的**人设 + 已成型的记忆库 + 真实单聊历史 + 关系状态**，
/// 分模块（通讯录→聊天→备忘→动态）顺序衍生出「这台手机里的世界」。
///
/// 强约束：所有内容都必须从记忆/人设中衍生，禁止脱离记忆库的无关联随机填充；
/// 记忆不足时宁缺毋滥、允许模块留空。全部是创作内容，纯本地存储，
/// 不读取任何真实设备数据，不上传任何数据。
class VirtualPhoneGenerator {
  final AIService _ai;
  final LocalStorageRepository _storage;
  final MemoryEngine _memory;
  final _uuid = const Uuid();

  VirtualPhoneGenerator({
    required AIService aiService,
    required LocalStorageRepository storage,
  })  : _ai = aiService,
        _storage = storage,
        _memory = MemoryEngine(storage);

  /// 首次进入 / 手动刷新：分模块顺序重新生成整台手机内容。
  ///
  /// 返回生成完成后的 [VirtualPhone]（status=ready 或 failed）。
  Future<VirtualPhone> generateAll({
    required VirtualPhone phone,
    required AICharacter character,
    required String userNickname,
    required String userId,
  }) async {
    // 标记生成中
    var current = phone.copyWith(status: 'generating', updatedAt: DateTime.now());
    await _storage.saveVirtualPhone(current);

    try {
      // 1) 先构建「记忆锚点上下文」——所有模块共享的衍生依据
      final memoryContext =
          await _buildMemoryContext(character, userId, userNickname);

      // 清空旧内容后，分模块顺序生成（禁止一次性批量）
      await _storage.clearVirtualPhoneContent(phone.id);

      // 2) 通讯录（挂靠记忆中出现过的人物 + 人设关系网）
      final contacts =
          await _genContacts(phone.id, character, memoryContext, userNickname);

      // 3) 聊天记录（复用真实聊天摘录 + 已定联系人，逐步衔接）
      await _genChats(
          phone.id, character, memoryContext, contacts, userNickname);

      // 4) 备忘/心事（引用记忆库里的具体喜好/情绪/里程碑）
      await _genNotes(phone.id, character, memoryContext, userNickname);

      // 5) 动态（取材于共同经历/最近状态/记住的情绪）
      await _genMoments(phone.id, character, memoryContext, userNickname);

      // 记录本次全量建档时的真实聊天基线（作为后续"生活推进"的起点）
      final baseline =
          await _storage.countVisibleChatMessages(character.id, userId);
      final now = DateTime.now();
      current = current.copyWith(
        status: 'ready',
        ownerName: character.name,
        generatedAt: now,
        lastAdvanceMsgCount: baseline,
        lastAdvanceAt: now,
        updatedAt: now,
      );
      await _storage.saveVirtualPhone(current);
      return current;
    } catch (e, st) {
      debugPrint('VirtualPhoneGenerator.generateAll failed: $e\n$st');
      current = current.copyWith(status: 'failed', updatedAt: DateTime.now());
      await _storage.saveVirtualPhone(current);
      return current;
    }
  }


  // ============ 生活推进（增量追加，不清空）============

  /// 让这台手机「像真人一样，跟着最近发生的事继续过日子」。
  ///
  /// 只做**小增量追加**：基于最新记忆 + 最近真实对话，新增少量动态 / 备忘，
  /// 并给与「我」的那条聊天线接几句新消息。**绝不清空旧内容**，旧内容作为历史沉淀。
  /// 一次只调用一次 LLM、产出很少，成本低、频率可控。
  ///
  /// 返回更新后的 [VirtualPhone]（刷新了 lastAdvanceMsgCount / lastAdvanceAt）。
  Future<VirtualPhone> advanceLife({
    required VirtualPhone phone,
    required AICharacter character,
    required String userNickname,
    required String userId,
  }) async {
    // 未建档/未就绪的手机不做增量（应先走 generateAll 建底）
    if (phone.status != 'ready') return phone;

    try {
      final ctx = await _buildMemoryContext(character, userId, userNickname);

      // 已有内容概览，避免重复、便于衔接
      final existingMoments = await _storage.getVpMoments(phone.id);
      final existingNotes = await _storage.getVpNotes(phone.id);
      final chats = await _storage.getVpChats(phone.id);

      // 找到与「我」的聊天线（title 含用户昵称，或第一条）
      final nick = userNickname.isEmpty ? '亲爱的' : userNickname;
      VpChat? userChat;
      for (final c in chats) {
        if (c.title.contains(nick)) {
          userChat = c;
          break;
        }
      }

      final recentMoments =
          existingMoments.take(4).map((m) => '· ${m.content}').join('\n');
      final recentNotes =
          existingNotes.take(3).map((n) => '· ${n.title}：${n.body}').join('\n');

      final b = StringBuffer();
      b.writeln(ctx.text);
      b.writeln('== 这台手机已有的近期内容（不要重复）==');
      b.writeln('已有动态：\n${recentMoments.isEmpty ? "（无）" : recentMoments}');
      b.writeln('已有备忘：\n${recentNotes.isEmpty ? "（无）" : recentNotes}');
      b.writeln();
      b.writeln('== 任务：让 TA 的手机「继续过日子」（增量更新）==');
      b.writeln('距上次更新后，${character.name} 和「我」又经历了新的事（见上面最新的记忆/对话）。');
      b.writeln('请只产出**少量**新增内容，模拟这段时间 TA 手机里自然多出来的东西：');
      b.writeln('· newMoments：0~2 条新动态，取材于最近真实发生的事，禁止与旧内容雷同；');
      b.writeln('· newNotes：0~1 条新备忘/心事，写 TA 最近藏起来的真实想法；');
      b.writeln('· newUserMessages：0~4 条 TA 发给「我」的新消息（延续你俩最近的对话语气）。');
      b.writeln('· 时间铁律：这些都是"距上次更新到现在"这段最近时间里新增的，'
          'time / date 必须是最近的过去（如"$_todayHint"、"昨天"、"刚刚"），'
          '要比上面"已有的近期内容"更新、更靠近"现在"，绝不能早于旧内容或晚于"现在"。');
      b.writeln('宁少勿滥：没有值得记的就返回空数组。所有内容必须从记忆/人设衍生。');
      b.writeln('只输出 JSON：');
      b.writeln(
          '{"newMoments":[{"content":"","time":"","likes":0,"comments":[{"name":"","content":""}]}],'
          '"newNotes":[{"title":"","body":"","date":"","aboutUser":true}],'
          '"newUserMessages":[{"fromOwner":true,"content":"","time":""}]}');

      final data = await _callJson(b.toString(), maxTokens: 1400);

      // ---- 追加动态 ----
      var momentIdx = existingMoments.length;
      for (final x in _asList(data?['newMoments'])) {
        final m = _asMap(x);
        final content = _str(m['content']);
        if (content.isEmpty) continue;
        final comments = _asList(m['comments'])
            .map((c) {
              final cm = _asMap(c);
              final who = _str(cm['name']);
              final txt = _str(cm['content']);
              if (txt.isEmpty) return '';
              return who.isEmpty ? txt : '$who：$txt';
            })
            .where((s) => s.trim().isNotEmpty)
            .join('\n');
        await _storage.saveVpMoment(VpMoment(
          id: _uuid.v4(),
          phoneId: phone.id,
          characterId: character.id,
          content: content,
          timeLabel: _str(m['time']),
          likes: _int(m['likes']),
          comments: comments,
          orderIndex: momentIdx++,
        ));
      }

      // ---- 追加备忘 ----
      var noteIdx = existingNotes.length;
      for (final x in _asList(data?['newNotes'])) {
        final m = _asMap(x);
        final body = _str(m['body']);
        if (body.isEmpty) continue;
        await _storage.saveVpNote(VpNote(
          id: _uuid.v4(),
          phoneId: phone.id,
          characterId: character.id,
          title: _str(m['title']),
          body: body,
          dateLabel: _str(m['date']),
          aboutUser: m['aboutUser'] == true,
          orderIndex: noteIdx++,
        ));
      }

      // ---- 给「我」的聊天线追加消息 ----
      final newMsgs = _asList(data?['newUserMessages']);
      if (newMsgs.isNotEmpty && userChat != null) {
        final existingMsgs = await _storage.getVpChatMessages(userChat.id);
        var msgIdx = existingMsgs.length;
        String lastContent = userChat.lastPreview;
        for (final x in newMsgs) {
          final mm = _asMap(x);
          final content = _str(mm['content']);
          if (content.isEmpty) continue;
          await _storage.saveVpChatMessage(VpChatMessage(
            id: _uuid.v4(),
            chatId: userChat.id,
            fromOwner: mm['fromOwner'] == true || mm['self'] == true,
            content: content,
            timeLabel: _str(mm['time']),
            orderIndex: msgIdx++,
          ));
          lastContent = content;
        }
        // 刷新聊天线预览
        await _storage.saveVpChat(VpChat(
          id: userChat.id,
          phoneId: userChat.phoneId,
          characterId: userChat.characterId,
          contactId: userChat.contactId,
          title: userChat.title,
          lastPreview: lastContent,
          orderIndex: userChat.orderIndex,
        ));
      }

      final baseline =
          await _storage.countVisibleChatMessages(character.id, userId);
      final now = DateTime.now();
      final updated = phone.copyWith(
        lastAdvanceMsgCount: baseline,
        lastAdvanceAt: now,
        updatedAt: now,
      );
      await _storage.saveVirtualPhone(updated);
      return updated;
    } catch (e, st) {
      debugPrint('VirtualPhoneGenerator.advanceLife failed: $e\n$st');
      return phone;
    }
  }

  // ============ 记忆锚点上下文 ============

  static const List<String> _weekdayCn = [
    '周一', '周二', '周三', '周四', '周五', '周六', '周日'
  ];

  /// "今天"的口语提示（如"今天(6月3日)"），供各模块 prompt 复用。
  String get _todayHint {
    final now = DateTime.now();
    return '今天(${now.month}月${now.day}日)';
  }

  /// 构建「当前时间锚点」——所有模块共享的时间基准。
  /// 让 LLM 知道"现在"是哪一天几点星期几，从而所有 time/date 标签
  /// 都相对这个"现在"倒推，与现实和剧情时序保持一致。
  String _buildTimeAnchor() {
    final now = DateTime.now();
    final y = now.year;
    final mo = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final wd = _weekdayCn[(now.weekday - 1).clamp(0, 6)];
    String period;
    final h = now.hour;
    if (h < 5) {
      period = '凌晨';
    } else if (h < 9) {
      period = '早晨';
    } else if (h < 12) {
      period = '上午';
    } else if (h < 14) {
      period = '中午';
    } else if (h < 18) {
      period = '下午';
    } else if (h < 23) {
      period = '晚上';
    } else {
      period = '深夜';
    }

    final b = StringBuffer();
    b.writeln('== 当前时间锚点（所有时间/日期标签必须以此为基准）==');
    b.writeln('“现在”是：$y年$mo月$d日 $wd $period $hh:$mm。');
    b.writeln('铁律（时间一致性）：');
    b.writeln('· 所有 time / date 字段都表示"过去发生"的时点，绝不能晚于上面的“现在”；');
    b.writeln('· 用相对且贴近现实的口语标签，例如："今天 $hh:$mm 前的某刻"、"昨天晚上"、"$wd上午"、"三天前"、"上周六"、"$mo月${(now.day - 2).clamp(1, 28)}日"；');
    b.writeln('· 越近期的内容排在越前面，时间要连贯、符合剧情推进顺序，不要出现未来时间或自相矛盾的先后关系；');
    b.writeln('· 如果记忆/对话里提到了具体的相对时间（如"明天考试"），要换算成相对"现在"的正确说法后再写。');
    b.writeln();
    return b.toString();
  }

  /// 汇总「已成型的记忆库 + 真实单聊历史 + 关系状态 + 人设」，
  /// 作为所有手机模块共享的衍生依据。返回结构化文本 + 是否记忆稀缺标记。
  Future<_MemoryContext> _buildMemoryContext(
    AICharacter c,
    String userId,
    String userNickname,
  ) async {
    final b = StringBuffer();

    // ---- 时间锚点（放最前，让所有后续内容都以"现在"为参照）----
    b.write(_buildTimeAnchor());

    // ---- 人设（固定成型的角色体系）----
    b.writeln('== 角色人设（固定，不可违背）==');
    b.writeln('姓名：${c.name}');
    if ((c.gender ?? '').isNotEmpty) b.writeln('性别：${c.gender}');
    b.writeln('性格：${c.personality}');
    b.writeln('核心渴望：${c.coreDesire}');
    b.writeln('道德底线：${c.moralBoundary}');
    if ((c.backgroundStory ?? '').isNotEmpty) {
      b.writeln('背景故事：${c.backgroundStory}');
    }
    if ((c.worldSetting ?? '').isNotEmpty) b.writeln('世界观：${c.worldSetting}');
    if ((c.languageStyle ?? '').isNotEmpty) b.writeln('语言风格：${c.languageStyle}');
    if ((c.catchphrases ?? '').isNotEmpty) b.writeln('口头禅：${c.catchphrases}');
    final nick = userNickname.isEmpty ? '亲爱的' : userNickname;
    b.writeln('TA 对「我」（用户）的称呼：$nick');
    b.writeln();

    var hasMemory = false;

    // ---- 记忆库：关系档案（已分好组：喜好/共同经历/情绪/最近状态）----
    try {
      final profile =
          await _memory.buildRelationshipProfile(character: c, userId: userId);
      if (profile.trim().isNotEmpty) {
        hasMemory = true;
        b.writeln('== 记忆库 · 关系档案（TA 记得关于「我」的事，必须作为衍生依据）==');
        b.writeln(profile.trim());
        b.writeln();
      }
    } catch (e) {
      debugPrint('VP _buildMemoryContext relationshipProfile: $e');
    }

    // ---- 记忆库：永久记忆 / 滚动摘要 ----
    try {
      final summary =
          await _memory.getRollingSummary(characterId: c.id, userId: userId);
      if (summary != null && summary.trim().isNotEmpty) {
        hasMemory = true;
        b.writeln('== 记忆库 · 永久记忆档案 ==');
        b.writeln(summary.trim());
        b.writeln();
      }
    } catch (e) {
      debugPrint('VP _buildMemoryContext rollingSummary: $e');
    }

    // ---- 记忆库：原始记忆条目（里程碑/情绪/喜好作为素材锚点）----
    try {
      final memories = await _storage.getMemories(
        characterId: c.id,
        userId: userId,
        limit: 40,
      );
      final anchors = memories
          .where((m) =>
              m.type == MemoryType.milestone ||
              m.type == MemoryType.emotion ||
              m.type == MemoryType.preference ||
              m.type == MemoryType.reflection)
          .map((m) => m.content.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (anchors.isNotEmpty) {
        hasMemory = true;
        b.writeln('== 记忆库 · 记忆要点（可引用的真实素材，禁止编造无关内容）==');
        for (final a in anchors.take(15)) {
          b.writeln('· $a');
        }
        b.writeln();
      }
    } catch (e) {
      debugPrint('VP _buildMemoryContext getMemories: $e');
    }

    // ---- 真实单聊历史摘录 + 关系状态 ----
    try {
      final sessions = await _storage.getChatSessionsByCharacterId(c.id);
      final mine = sessions.where((s) => s.userId == userId).toList();
      if (mine.isNotEmpty) {
        // 取亲密度最高（关系最主线）的一段会话
        mine.sort((a, b) => b.intimacyLevel.compareTo(a.intimacyLevel));
        final main = mine.first;
        final stage = relationshipStage(main.intimacyLevel);
        b.writeln('== 关系状态 ==');
        b.writeln('当前关系阶段：$stage（亲密度 ${main.intimacyLevel}/100）');
        b.writeln();

        final excerpt = await _recentDialogueExcerpt(main, nick, c.name);
        if (excerpt.isNotEmpty) {
          hasMemory = true;
          b.writeln('== 真实单聊摘录（TA 私下如何和「我」说话 · 语气与事实来源）==');
          b.writeln(excerpt);
          b.writeln();
        }
      }
    } catch (e) {
      debugPrint('VP _buildMemoryContext chatExcerpt: $e');
    }

    return _MemoryContext(text: b.toString(), hasMemory: hasMemory);
  }

  /// 取一段真实对白摘录（最近 ~24 条可见消息），标注说话人。
  Future<String> _recentDialogueExcerpt(
    ChatSession session,
    String userNick,
    String characterName,
  ) async {
    final all = await _storage.getChatMessages(session.id, limit: 2000);
    final visible = all
        .where((m) => !m.isSystem && !m.isHidden && !m.isGhost)
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    if (visible.isEmpty) return '';
    final tail = visible.length > 24 ? visible.sublist(visible.length - 24) : visible;
    final now = DateTime.now();
    final b = StringBuffer();
    for (final m in tail) {
      final who = m.isUser ? userNick : characterName;
      final line = m.content.trim().replaceAll('\n', ' ');
      final clipped = line.length > 120 ? '${line.substring(0, 120)}…' : line;
      b.writeln('[${_relativeTimeLabel(m.createdAt, now)}] $who：$clipped');
    }
    return b.toString().trim();
  }

  /// 把绝对时间转成相对"现在"的口语标签，帮助 LLM 建立剧情时序。
  static String _relativeTimeLabel(DateTime t, DateTime now) {
    final diff = now.difference(t);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (diff.inMinutes < 60 && diff.inMinutes >= 0) {
      return '刚刚';
    }
    // 按自然日判断"今天/昨天/前天"
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(t.year, t.month, t.day);
    final dayGap = today.difference(that).inDays;
    if (dayGap == 0) return '今天 $hh:$mm';
    if (dayGap == 1) return '昨天 $hh:$mm';
    if (dayGap == 2) return '前天 $hh:$mm';
    if (dayGap > 0 && dayGap < 7) return '$dayGap天前';
    if (dayGap >= 7 && dayGap < 14) return '上周';
    if (dayGap >= 14 && dayGap < 30) return '${(dayGap / 7).floor()}周前';
    if (dayGap >= 30) return '${(dayGap / 30).floor()}个月前';
    return '${t.month}月${t.day}日';
  }

  // ============ 分模块生成 ============

  static const String _systemPrompt =
      '你是一名擅长角色塑造的编剧，正在为一个虚构角色设计「TA 私人手机里的内容」。'
      '这是纯粹的虚构创作，所有内容都出自你的想象，不涉及任何真实的人或设备。'
      '铁律一（素材约束）：你所写的一切都必须从我提供的【角色人设 + 记忆库 + 真实单聊摘录】中衍生，'
      '严禁脱离这些材料凭空捏造无关的人、事、喜好或经历；'
      '记忆材料不足时宁缺毋滥，可以少写，绝不允许用随机无关内容凑数。'
      '铁律二（时间一致性）：严格遵守我给出的【当前时间锚点】，'
      '所有 time / date 字段都必须是相对"现在"的过去时点，不得晚于"现在"、不得出现未来日期、'
      '不同条目之间的先后顺序要连贯合理、贴合剧情推进，绝不允许时间错乱或与现实季节/星期矛盾。'
      '你必须只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块。';

  /// 统一的一次性 LLM 调用 + JSON 解析。
  Future<Map<String, dynamic>?> _callJson(String userPrompt,
      {int maxTokens = 1600}) async {
    final raw = await _ai.sendStoryMessage(
      messages: [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      overrideMaxTokens: maxTokens,
    );
    return _extractJson(raw);
  }

  // ---- 1) 通讯录 ----
  Future<List<VpContact>> _genContacts(
    String phoneId,
    AICharacter c,
    _MemoryContext ctx,
    String userNickname,
  ) async {
    final nick = userNickname.isEmpty ? '亲爱的' : userNickname;
    final b = StringBuffer();
    b.writeln(ctx.text);
    b.writeln('== 任务：生成通讯录 ==');
    b.writeln('依据上面的人设与记忆，虚构出 ${c.name} 手机通讯录里的联系人。');
    b.writeln('· 优先收录记忆库/单聊摘录中真实出现过的人物与关系；');
    b.writeln('· 其余名额用符合角色背景（家人/朋友/同事/世界观中的人物）的联系人补足；');
    b.writeln('· 必须有且仅有一个 isUser=true 的联系人，代表「我」，姓名用「$nick」；');
    b.writeln('· 数量 4~8 个；记忆很少时可只写 3~4 个，不要硬凑。');
    b.writeln('note 字段写这个人对 TA 意味着什么（要贴合记忆/人设，禁止无关编造）。');
    b.writeln('只输出 JSON：');
    b.writeln(
        '{"contacts":[{"name":"","relation":"","note":"","isUser":false,"pinned":false}]}');

    final saved = <VpContact>[];
    try {
      final data = await _callJson(b.toString(), maxTokens: 1200);
      final list = _asList(data?['contacts']);
      for (var i = 0; i < list.length; i++) {
        final m = _asMap(list[i]);
        final name = _str(m['name']);
        if (name.isEmpty) continue;
        final contact = VpContact(
          id: _uuid.v4(),
          phoneId: phoneId,
          characterId: c.id,
          name: name,
          relation: _str(m['relation']),
          note: _str(m['note']),
          isUser: m['isUser'] == true,
          pinned: m['pinned'] == true,
          orderIndex: i,
        );
        await _storage.saveVpContact(contact);
        saved.add(contact);
      }
    } catch (e) {
      debugPrint('VP _genContacts: $e');
    }
    return saved;
  }

  // ---- 2) 聊天记录 ----
  Future<void> _genChats(
    String phoneId,
    AICharacter c,
    _MemoryContext ctx,
    List<VpContact> contacts,
    String userNickname,
  ) async {
    final nick = userNickname.isEmpty ? '亲爱的' : userNickname;
    final names = contacts
        .where((x) => x.name.isNotEmpty)
        .map((x) => x.isUser ? '${x.name}（就是「我」）' : x.name)
        .join('、');
    final b = StringBuffer();
    b.writeln(ctx.text);
    b.writeln('== 已生成的通讯录联系人 ==');
    b.writeln(names.isEmpty ? '（无）' : names);
    b.writeln();
    b.writeln('== 任务：生成聊天记录 ==');
    b.writeln('虚构 ${c.name} 与上述联系人之间的 2~4 段聊天记录，每段 4~8 条消息。');
    b.writeln('· 聊天对象必须来自上面的通讯录；');
    b.writeln('· 至少一段是与「我」（$nick）的对话，语气/事实要与「真实单聊摘录」保持一致，');
    b.writeln('  体现 TA 私下如何跟我说话、如何看待我，可自然引用记忆库里的共同经历；');
    b.writeln('· 其它段落要呼应角色的人设与记忆，禁止无关剧情；');
    b.writeln('· fromOwner=true 表示 ${c.name} 本人发的，false 表示对方发的；');
    b.writeln('· time 字段：每条消息的时间标签必须基于开头的【当前时间锚点】倒推，'
        '同一段对话内时间要递增连贯（如"昨天 21:03"→"昨天 21:05"），越近的对话排越前；');
    b.writeln('· 记忆很少时可只写 1~2 段，不要硬凑。');
    b.writeln('只输出 JSON（title 为聊天对象名）：');
    b.writeln(
        '{"chats":[{"title":"","messages":[{"fromOwner":true,"content":"","time":""}]}]}');

    try {
      final data = await _callJson(b.toString(), maxTokens: 2200);
      final list = _asList(data?['chats']);
      for (var i = 0; i < list.length; i++) {
        final m = _asMap(list[i]);
        final msgs = _asList(m['messages']);
        if (msgs.isEmpty) continue;
        final chatId = _uuid.v4();
        final lastPreview = _str(_asMap(msgs.last)['content']);
        var title = _str(m['title']);
        if (title.isEmpty) title = _str(m['name']);
        await _storage.saveVpChat(VpChat(
          id: chatId,
          phoneId: phoneId,
          characterId: c.id,
          contactId: '',
          title: title,
          lastPreview: lastPreview,
          orderIndex: i,
        ));
        for (var j = 0; j < msgs.length; j++) {
          final mm = _asMap(msgs[j]);
          final content = _str(mm['content']);
          if (content.isEmpty) continue;
          await _storage.saveVpChatMessage(VpChatMessage(
            id: _uuid.v4(),
            chatId: chatId,
            fromOwner: mm['fromOwner'] == true || mm['self'] == true,
            content: content,
            timeLabel: _str(mm['time']),
            orderIndex: j,
          ));
        }
      }
    } catch (e) {
      debugPrint('VP _genChats: $e');
    }
  }

  // ---- 3) 备忘 / 心事 ----
  Future<void> _genNotes(
    String phoneId,
    AICharacter c,
    _MemoryContext ctx,
    String userNickname,
  ) async {
    final b = StringBuffer();
    b.writeln(ctx.text);
    b.writeln('== 任务：生成私密备忘/日记 ==');
    b.writeln('虚构 ${c.name} 写在备忘录里的 2~5 条私密心事。');
    b.writeln('· 每条都要能对应到记忆库里的具体喜好/情绪/里程碑，或真实单聊里发生过的事；');
    b.writeln('· 至少一条 aboutUser=true（关于「我」的），写 TA 藏起来没说出口的真实想法；');
    b.writeln('· date 字段：每条备忘的日期标签基于【当前时间锚点】倒推，'
        '是写下这条心事的过去日期（如"昨天"、"$_todayHint"、"上周三"），不得晚于"现在"，越近的排越前；');
    b.writeln('· 严禁写与记忆/人设无关的空泛内容；记忆很少时可只写 1~2 条。');
    b.writeln('只输出 JSON：');
    b.writeln('{"notes":[{"title":"","body":"","date":"","aboutUser":false}]}');

    try {
      final data = await _callJson(b.toString(), maxTokens: 1400);
      final list = _asList(data?['notes']);
      for (var i = 0; i < list.length; i++) {
        final m = _asMap(list[i]);
        final body = _str(m['body']);
        if (body.isEmpty) continue;
        await _storage.saveVpNote(VpNote(
          id: _uuid.v4(),
          phoneId: phoneId,
          characterId: c.id,
          title: _str(m['title']),
          body: body,
          dateLabel: _str(m['date']),
          aboutUser: m['aboutUser'] == true,
          orderIndex: i,
        ));
      }
    } catch (e) {
      debugPrint('VP _genNotes: $e');
    }
  }

  // ---- 4) 动态 ----
  Future<void> _genMoments(
    String phoneId,
    AICharacter c,
    _MemoryContext ctx,
    String userNickname,
  ) async {
    final b = StringBuffer();
    b.writeln(ctx.text);
    b.writeln('== 任务：生成社交动态（类似朋友圈）==');
    b.writeln('虚构 ${c.name} 发过的 3~6 条动态，文字为主。');
    b.writeln('· 取材于记忆库里的共同经历/最近状态/记住的情绪，或角色人设中的生活；');
    b.writeln('· 可以有隐晦提及「我」的动态（不点名），呼应你们之间发生过的事；');
    b.writeln('· 点赞数虚构合理数字，评论可留空或来自通讯录里的人；');
    b.writeln('· time 字段：每条动态的发布时间基于【当前时间锚点】倒推，'
        '是过去发出的（如"$_todayHint 中午"、"昨天"、"三天前"），不得晚于"现在"，越近的排越前；');
    b.writeln('· 禁止与记忆/人设无关的随机内容；记忆很少时可只写 2~3 条。');
    b.writeln('只输出 JSON：');
    b.writeln(
        '{"moments":[{"content":"","time":"","likes":0,"comments":[{"name":"","content":""}]}]}');

    try {
      final data = await _callJson(b.toString(), maxTokens: 1600);
      final list = _asList(data?['moments']);
      for (var i = 0; i < list.length; i++) {
        final m = _asMap(list[i]);
        final content = _str(m['content']);
        if (content.isEmpty) continue;
        final comments = _asList(m['comments'])
            .map((x) {
              final cm = _asMap(x);
              final who = _str(cm['name']);
              final txt = _str(cm['content']);
              if (txt.isEmpty) return '';
              return who.isEmpty ? txt : '$who：$txt';
            })
            .where((s) => s.trim().isNotEmpty)
            .join('\n');
        await _storage.saveVpMoment(VpMoment(
          id: _uuid.v4(),
          phoneId: phoneId,
          characterId: c.id,
          content: content,
          timeLabel: _str(m['time']),
          likes: _int(m['likes']),
          comments: comments,
          orderIndex: i,
        ));
      }
    } catch (e) {
      debugPrint('VP _genMoments: $e');
    }
  }

  // ============ 工具 ============

  /// 从模型输出中提取第一个完整 JSON 对象（容忍 ```json 围栏与前后噪声）。
  static Map<String, dynamic>? _extractJson(String raw) {
    var s = raw.trim();
    // 去掉 markdown 代码围栏
    if (s.startsWith('```')) {
      s = s.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      final end = s.lastIndexOf('```');
      if (end != -1) s = s.substring(0, end);
      s = s.trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    final jsonStr = s.substring(start, end + 1);
    try {
      final decoded = jsonDecode(jsonStr);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<dynamic> _asList(dynamic v) => v is List ? v : const [];

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  static String _str(dynamic v) => v == null ? '' : v.toString().trim();

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// 共享的记忆锚点上下文：拼好的材料文本 + 是否含有效记忆。
class _MemoryContext {
  final String text;
  final bool hasMemory;
  const _MemoryContext({required this.text, required this.hasMemory});
}
