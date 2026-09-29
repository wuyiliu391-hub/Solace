import 'package:flutter/foundation.dart';

import '../config/business_rules.dart';
import '../models/moment.dart';
import '../repositories/local_storage_repository.dart';

/// 朋友圈/动态「闭环」上下文服务。
///
/// 把角色在朋友圈里做过的事（发过的动态、评论/回复过的内容）和
/// 看到的事（用户发的、TA 可见的动态）汇总成一段 prompt 片段，
/// 注入单聊与群聊，让角色真的「知道自己做了什么、说了什么、看到了什么」，
/// 从而能在聊天里自然承接（例如：「你看到了啊？那条仅你可见」）。
class MomentContextService {
  final LocalStorageRepository _storage;

  MomentContextService(this._storage);

  /// 该角色是否能看到某条动态（可见范围 + 拉黑名单）。
  static bool canCharacterSeeMoment(
    Moment moment,
    String characterId,
    int intimacyLevel,
  ) {
    if (moment.blockedUserIds.contains(characterId)) return false;
    switch (moment.visibility) {
      case MomentVisibility.public:
        return true;
      case MomentVisibility.private:
        return false;
      case MomentVisibility.intimate:
        return intimacyLevel >= IntimacyRules.intimateVisibilityThreshold;
      case MomentVisibility.normal:
        return intimacyLevel >= IntimacyRules.normalVisibilityThreshold;
    }
  }

  /// 构建「该角色最近在朋友圈/动态里的动态与见闻」上下文。
  ///
  /// 输出三部分（按需裁剪，控制 token 预算）：
  /// 1. 自己最近发过的动态
  /// 2. 自己在别人动态下评论/回复过的内容
  /// 3. 用户最近发的、该角色可见的动态
  Future<String> buildCharacterMomentContext({
    required String characterId,
    required String characterName,
    required String userId,
    int intimacyLevel = 0,
    int maxOwnPosts = 2,
    int maxComments = 3,
    int maxSeenUserPosts = 3,
  }) async {
    final b = StringBuffer();
    var wroteAny = false;

    // 只读取普通朋友圈（source=0）动态：这是 AI 发动态/评论的主阵地
    final List<Moment> recent;
    try {
      recent = await _storage.getAllMoments();
    } catch (e) {
      debugPrint('MomentContext 读取动态失败: $e');
      return '';
    }
    if (recent.isEmpty) return '';

    // ── 1) 自己发过的动态 ──
    final ownPosts = recent
        .where((m) => m.userId == characterId)
        .take(maxOwnPosts)
        .toList();
    if (ownPosts.isNotEmpty) {
      b.writeln('· 你最近发过这些动态：');
      for (final m in ownPosts) {
        final text = m.content.replaceAll('\n', ' ').trim();
        if (text.isEmpty) continue;
        b.writeln('  - 「$text」${_visibilityNote(m.visibility)}');
      }
      wroteAny = true;
    }

    // ── 2) 自己在别人动态下评论/回复过 ──
    final commentsByMe = <String>[];
    for (final m in recent) {
      if (commentsByMe.length >= maxComments) break;
      for (final c in m.comments) {
        if (c.userId != characterId) continue;
        if (commentsByMe.length >= maxComments) break;
        final parentText = m.content.replaceAll('\n', ' ').trim();
        final myText = c.content.replaceAll('\n', ' ').trim();
        if (myText.isEmpty) continue;
        final target = (c.replyToUserName != null && c.replyToUserName!.isNotEmpty)
            ? '回复${c.replyToUserName}'
            : '评论';
        commentsByMe.add(
            '  - 你在「${_clip(parentText, 40)}」下$target：$myText');
      }
    }
    if (commentsByMe.isNotEmpty) {
      if (wroteAny) b.writeln();
      b.writeln('· 你在朋友圈说过的话：');
      for (final line in commentsByMe) {
        b.writeln(line);
      }
      wroteAny = true;
    }

    // ── 3) 用户最近发的、该角色可见的动态 ──
    final userPosts = recent
        .where((m) =>
            m.userId == userId &&
            canCharacterSeeMoment(m, characterId, intimacyLevel))
        .take(maxSeenUserPosts)
        .toList();
    if (userPosts.isNotEmpty) {
      if (wroteAny) b.writeln();
      b.writeln('· 你最近看到的${_userRef(characterName)}动态：');
      for (final m in userPosts) {
        final text = m.content.replaceAll('\n', ' ').trim();
        if (text.isEmpty) continue;
        b.writeln('  - 「${_clip(text, 50)}」');
      }
      wroteAny = true;
    }

    if (!wroteAny) return '';

    return '''
【你在朋友圈/动态的最近经历 — 这是你真实做过、真实看到过的事】
这些是你自己发过的动态、说过的评论、以及你看到的${_userRef(characterName)}的动态，不是编造的。
${b.toString().trim()}
如果聊天里提到相关话题，你可以自然地提起或回应（例如承认你发过、解释可见范围、接住对方的动态）；没提到就不必刻意说。''';
  }

  static String _userRef(String characterName) =>
      characterName.trim().isEmpty ? '对方' : characterName.trim();

  static String _visibilityNote(MomentVisibility v) {
    switch (v) {
      case MomentVisibility.private:
        return '（仅自己可见）';
      case MomentVisibility.intimate:
        return '（仅亲密的人可见）';
      case MomentVisibility.normal:
        return '（好友可见）';
      case MomentVisibility.public:
        return '';
    }
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}
