import 'package:solace/models/ai_character.dart';

/// 合并角色卡结果（对标 ST getGroupCharacterCards 的 description/personality/scenario/mesExamples）
class CombinedCard {
  final String description;
  final String personality;
  final String scenario;
  final String mesExamples;
  const CombinedCard({
    required this.description,
    required this.personality,
    required this.scenario,
    required this.mesExamples,
  });
}

/// 群成员名单 + 新群聊提示（对标 ST new_group_chat_prompt: [Start a new group chat. Group members: {{group}}]）
String buildGroupIntroPrompt({
  required String selfName,
  required List<String> memberNames,
  required bool isNewChat,
}) {
  final memberList = memberNames.isEmpty ? selfName : memberNames.join('、');
  final base = '这是一个群聊。你是「$selfName」，群成员有：$memberList。'
      '你在群里发言要自然，像真人聊天一样，语气符合你的性格。'
      '你们在群聊里各自说话、互相接话，但不要代别人发言，也不要复述或引用别人的话。'
      '不要重复别人刚说过的话，不要原样回显上一条消息。'
      '刚才大家聊的内容见历史消息，直接说你要说的话。';
  if (isNewChat) {
    return '$base\n[开始一个新的群聊。群成员: $memberList]';
  }
  return base;
}

/// 群聊 nudge：告诉 LLM 只以指定角色发言（对标 ST group_nudge_prompt）
String buildGroupNudge(String selfName) =>
    '[请只以「$selfName」的身份继续发言。接续上文继续聊，不要重复别人或自己说过的话，不要原样回显上一条消息，直接说新内容。]';

/// 群聊历史消息格式化：自己消息不带前缀，他人消息加 `名字: 内容`
/// （对标 ST openai.js:585 群聊角色名前缀）
String formatGroupMessage({
  required bool isSelf,
  required String senderName,
  required String content,
}) {
  if (isSelf) return content;
  return '$senderName: $content';
}

/// 合并全员角色卡（对标 ST getGroupCharacterCardsLazy，generation_mode APPEND）
CombinedCard buildCombinedCard({
  required List<AICharacter> members,
  required String joinPrefix,
  required String joinSuffix,
}) {
  String collectField(String Function(AICharacter) getter) {
    final values = <String>[];
    for (final c in members) {
      final v = getter(c).trim();
      if (v.isEmpty) continue;
      values.add('$joinPrefix$v$joinSuffix');
    }
    return values.join('\n');
  }

  return CombinedCard(
    description: collectField((c) => _firstNonEmpty([
          c.backgroundStory,
          c.worldSetting,
          c.personality,
        ])),
    personality: collectField((c) => c.personality),
    scenario: collectField((c) => _firstNonEmpty([c.worldSetting])),
    mesExamples: collectField((c) => _buildMesExample(c)),
  );
}

String _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    if (v != null && v.trim().isNotEmpty) return v;
  }
  return '';
}

String _buildMesExample(AICharacter c) {
  final parts = <String>[];
  if (c.openingLine != null && c.openingLine!.trim().isNotEmpty) {
    parts.add('${c.name}: ${c.openingLine}');
  }
  if (c.catchphrases != null && c.catchphrases!.trim().isNotEmpty) {
    parts.add('${c.name}: ${c.catchphrases}');
  }
  if (c.dialogueExamples.isNotEmpty) {
    for (final e in c.dialogueExamples) {
      parts.add('用户: ${e.userMessage}\n${c.name}: ${e.aiResponse}');
    }
  }
  return parts.join('\n');
}
