import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/ai_character.dart';
import '../models/virtual_phone/virtual_phone.dart';
import '../models/virtual_phone/vp_contact.dart';
import '../models/virtual_phone/vp_chat.dart';
import '../models/virtual_phone/vp_note.dart';
import '../models/virtual_phone/vp_moment.dart';
import '../repositories/local_storage_repository.dart';
import 'ai_service.dart';

/// 虚拟手机生成器
///
/// 依据 AI 角色的人设/背景，让 LLM 一次性虚构出「这台手机里的世界」：
/// 通讯录、几段聊天、私密备忘、社交动态。全部是创作内容，纯本地存储，
/// 不读取任何真实设备数据，不上传任何数据。
class VirtualPhoneGenerator {
  final AIService _ai;
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();

  VirtualPhoneGenerator({
    required AIService aiService,
    required LocalStorageRepository storage,
  })  : _ai = aiService,
        _storage = storage;

  /// 首次进入 / 手动刷新：全量重新生成整台手机内容。
  ///
  /// 返回生成完成后的 [VirtualPhone]（status=ready 或 failed）。
  Future<VirtualPhone> generateAll({
    required VirtualPhone phone,
    required AICharacter character,
    required String userNickname,
  }) async {
    // 标记生成中
    var current = phone.copyWith(status: 'generating', updatedAt: DateTime.now());
    await _storage.saveVirtualPhone(current);

    try {
      final prompt = _buildPrompt(character, userNickname);
      final raw = await _ai.sendStoryMessage(
        messages: [
          {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        overrideMaxTokens: 4096,
      );

      final data = _extractJson(raw);
      if (data == null) {
        throw const FormatException('无法从模型输出中解析 JSON');
      }

      // 清空旧内容后落库
      await _storage.clearVirtualPhoneContent(phone.id);
      await _persist(phone.id, character.id, data);

      current = current.copyWith(
        status: 'ready',
        ownerName: character.name,
        generatedAt: DateTime.now(),
        updatedAt: DateTime.now(),
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

  // ============ 落库 ============

  Future<void> _persist(
      String phoneId, String characterId, Map<String, dynamic> data) async {
    // ---- 联系人 ----
    final contacts = _asList(data['contacts']);
    for (var i = 0; i < contacts.length; i++) {
      final m = _asMap(contacts[i]);
      await _storage.saveVpContact(VpContact(
        id: _uuid.v4(),
        phoneId: phoneId,
        characterId: characterId,
        name: _str(m['name']),
        relation: _str(m['relation']),
        note: _str(m['note']),
        isUser: m['isUser'] == true,
        pinned: m['pinned'] == true,
        orderIndex: i,
      ));
    }

    // ---- 聊天线 + 消息 ----
    final chats = _asList(data['chats']);
    for (var i = 0; i < chats.length; i++) {
      final m = _asMap(chats[i]);
      final chatId = _uuid.v4();
      final msgs = _asList(m['messages']);
      final lastPreview =
          msgs.isNotEmpty ? _str(_asMap(msgs.last)['content']) : '';
      await _storage.saveVpChat(VpChat(
        id: chatId,
        phoneId: phoneId,
        characterId: characterId,
        contactId: '',
        title: _str(m['title'].toString().isEmpty ? m['name'] : m['title']),
        lastPreview: lastPreview,
        orderIndex: i,
      ));
      for (var j = 0; j < msgs.length; j++) {
        final mm = _asMap(msgs[j]);
        await _storage.saveVpChatMessage(VpChatMessage(
          id: _uuid.v4(),
          chatId: chatId,
          fromOwner: mm['fromOwner'] == true || mm['self'] == true,
          content: _str(mm['content']),
          timeLabel: _str(mm['time']),
          orderIndex: j,
        ));
      }
    }

    // ---- 备忘录 ----
    final notes = _asList(data['notes']);
    for (var i = 0; i < notes.length; i++) {
      final m = _asMap(notes[i]);
      await _storage.saveVpNote(VpNote(
        id: _uuid.v4(),
        phoneId: phoneId,
        characterId: characterId,
        title: _str(m['title']),
        body: _str(m['body']),
        dateLabel: _str(m['date']),
        aboutUser: m['aboutUser'] == true,
        orderIndex: i,
      ));
    }

    // ---- 动态 ----
    final moments = _asList(data['moments']);
    for (var i = 0; i < moments.length; i++) {
      final m = _asMap(moments[i]);
      final comments = _asList(m['comments'])
          .map((c) {
            final cm = _asMap(c);
            final who = _str(cm['name']);
            final txt = _str(cm['content']);
            return who.isEmpty ? txt : '$who：$txt';
          })
          .where((s) => s.trim().isNotEmpty)
          .join('\n');
      await _storage.saveVpMoment(VpMoment(
        id: _uuid.v4(),
        phoneId: phoneId,
        characterId: characterId,
        content: _str(m['content']),
        timeLabel: _str(m['time']),
        likes: _int(m['likes']),
        comments: comments,
        orderIndex: i,
      ));
    }
  }

  // ============ Prompt ============

  static const String _systemPrompt =
      '你是一名擅长角色塑造的编剧。你要为一个虚构角色设计「TA 的私人手机里都有什么」。'
      '这是纯粹的创作/虚构任务，所有内容都是你想象出来的，不涉及任何真实的人或设备。'
      '你必须只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块。';

  String _buildPrompt(AICharacter c, String userNickname) {
    final b = StringBuffer();
    b.writeln('请依据下面这个角色的人设，虚构出 TA 私人手机里的内容。');
    b.writeln('== 角色人设 ==');
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
    b.writeln();
    b.writeln('用户（也就是「我」，与该角色是直接的亲密关系）的昵称是：'
        '${userNickname.isEmpty ? "亲爱的" : userNickname}');
    b.writeln();
    b.writeln('== 生成要求 ==');
    b.writeln('1. contacts：5~8 个通讯录联系人，要贴合角色的人生经历（家人/朋友/同事等），');
    b.writeln('   其中必须有且仅有一个 isUser=true 的联系人，代表「我」（用上面的用户昵称）。');
    b.writeln('2. chats：3~4 段聊天记录，每段是该角色与某个联系人的对话，各含 4~8 条消息。');
    b.writeln('   其中至少一段是与「我」（用户）的聊天，要体现 TA 私下里怎么和我说话、怎么看待我。');
    b.writeln('   fromOwner=true 表示该角色本人发的，false 表示对方发的。');
    b.writeln('3. notes：3~5 条私密备忘/日记，写 TA 的真实心事；至少一条 aboutUser=true（关于我）。');
    b.writeln('4. moments：4~6 条社交动态（类似朋友圈），文字为主，含虚构点赞数与少量评论。');
    b.writeln('所有内容都要符合角色性格、语气和背景，像是真的从 TA 手机里翻出来的。');
    b.writeln();
    b.writeln('只输出如下结构的 JSON：');
    b.writeln(_schemaHint);
    return b.toString();
  }

  static const String _schemaHint = '''
{
  "contacts": [
    {"name": "", "relation": "", "note": "", "isUser": false, "pinned": false}
  ],
  "chats": [
    {"title": "", "messages": [{"fromOwner": true, "content": "", "time": ""}]}
  ],
  "notes": [
    {"title": "", "body": "", "date": "", "aboutUser": false}
  ],
  "moments": [
    {"content": "", "time": "", "likes": 0, "comments": [{"name": "", "content": ""}]}
  ]
}''';

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
