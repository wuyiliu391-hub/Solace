import 'dart:math';
import 'package:solace/models/group_chat_session.dart';

/// 群聊发言人选择上下文（对标 ST group-chats.js 各 activate 函数入参）
class SpeakerContext {
  /// 群成员 AI 角色 id（有序，ST members）
  final List<String> memberIds;

  /// 禁言成员 id（ST disabled_members）
  final List<String> disabledMemberIds;

  /// 自用户最后一条消息以来的角色发言序列（ST activatePooledOrder 的 spokenSinceUser）
  final List<String> historySpeakerIds;

  /// 最后一条消息发言者角色 id（用户消息则为 null）
  final String? lastMessageSpeakerId;

  /// 角色 id → 健谈度 0~1（ST talkativeness，默认 0.5）
  final Map<String, double> talkativeness;

  /// 是否允许同一角色连续发言（ST allow_self_responses）
  final bool allowSelfResponses;

  /// 用户输入文本（提及检测用，ST input）
  final String userInput;

  /// 是否用户输入触发（ST isUserInput）
  final bool isUserInput;

  /// 手动点名角色 id（ST force_chid / impersonate）
  final String? forceCharacterId;

  /// 角色 id → 名称（提及检测用）
  final Map<String, String> memberNames;

  final Random random;

  const SpeakerContext({
    required this.memberIds,
    this.disabledMemberIds = const [],
    this.historySpeakerIds = const [],
    this.lastMessageSpeakerId,
    this.talkativeness = const {},
    this.allowSelfResponses = false,
    this.userInput = '',
    this.isUserInput = false,
    this.forceCharacterId,
    this.memberNames = const {},
    required this.random,
  });

  List<String> get enabledMemberIds =>
      memberIds.where((m) => !disabledMemberIds.contains(m)).toList();
}

/// 选择本次发言角色列表（ST generateGroupWrapper 的 activatedMembers）
List<String> selectSpeakers({
  required GroupActivationStrategy strategy,
  required SpeakerContext ctx,
}) {
  final members = ctx.enabledMemberIds;
  if (members.isEmpty) return [];

  switch (strategy) {
    case GroupActivationStrategy.list:
      return _activateListOrder(members);
    case GroupActivationStrategy.pooled:
      return _activatePooledOrder(members, ctx);
    case GroupActivationStrategy.natural:
      return _activateNaturalOrder(members, ctx);
    case GroupActivationStrategy.manual:
      return _activateImpersonate(members, ctx);
  }
}

/// ST activateListOrder：按成员列表顺序全员激活
List<String> _activateListOrder(List<String> members) {
  return List.of(members);
}

/// ST activateImpersonate：随机取一个成员（forceCharacterId 优先）
List<String> _activateImpersonate(List<String> members, SpeakerContext ctx) {
  final forced = ctx.forceCharacterId;
  if (forced != null && members.contains(forced)) {
    return [forced];
  }
  if (members.isEmpty) return [];
  return [members[ctx.random.nextInt(members.length)]];
}

/// ST activatePooledOrder：优先未发言者，全部说过排除最后发言者
List<String> _activatePooledOrder(List<String> members, SpeakerContext ctx) {
  String? activated;
  final haveNotSpoken =
      members.where((m) => !ctx.historySpeakerIds.contains(m)).toList();
  if (haveNotSpoken.isNotEmpty) {
    activated = haveNotSpoken[ctx.random.nextInt(haveNotSpoken.length)];
  }
  if (activated == null) {
    final lastAvatar = members.length > 1 &&
            ctx.lastMessageSpeakerId != null &&
            ctx.historySpeakerIds.isNotEmpty
        ? ctx.lastMessageSpeakerId
        : null;
    final pool = lastAvatar != null && members.contains(lastAvatar)
        ? members.where((m) => m != lastAvatar).toList()
        : members;
    activated = pool[ctx.random.nextInt(pool.length)];
  }
  return [activated];
}

/// ST activateNaturalOrder：提及检测 + 话痨概率 roll + 随机兜底
List<String> _activateNaturalOrder(List<String> members, SpeakerContext ctx) {
  final activated = <String>[];
  // 禁止与最后一条消息同角色连续发言（除非 allowSelfResponses）
  String? banned = !ctx.isUserInput && ctx.lastMessageSpeakerId != null
      ? ctx.lastMessageSpeakerId
      : null;
  if (ctx.allowSelfResponses) banned = null;

  // 提及检测：输入文本包含角色名（长度>=2）则激活该角色
  if (ctx.userInput.isNotEmpty) {
    for (final m in members) {
      if (m == banned) continue;
      final name = ctx.memberNames[m] ?? m;
      if (name.length >= 2 && ctx.userInput.contains(name)) {
        if (!activated.contains(m)) activated.add(m);
      }
    }
  }

  // 话痨概率 roll（打乱顺序，排除禁言者）
  final shuffled = List.of(members)..shuffle(ctx.random);
  final chattyMembers = <String>[];
  for (final m in shuffled) {
    if (m == banned) continue;
    final t = ctx.talkativeness[m] ?? 0.5;
    if (ctx.random.nextDouble() <= t) {
      if (!activated.contains(m)) activated.add(m);
    }
    if (t > 0) chattyMembers.add(m);
  }

  // 兜底：没人激活时随机选（优先 talkativeness>0 池，排除禁言者）
  if (activated.isEmpty) {
    final pool = chattyMembers.isNotEmpty ? chattyMembers : members;
    final candidates = pool.where((m) => m != banned).toList();
    final source = candidates.isNotEmpty ? candidates : pool;
    int retries = 0;
    while (activated.isEmpty && retries < source.length) {
      final picked = source[ctx.random.nextInt(source.length)];
      if (!activated.contains(picked)) activated.add(picked);
      retries++;
    }
  }

  return activated.toSet().toList();
}
