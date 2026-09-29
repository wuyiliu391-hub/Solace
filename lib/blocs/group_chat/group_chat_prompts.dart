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
      '你在群里发言要自然，像真人在一个连续场景里接话，语气符合你的性格。'
      '你们在群聊里各自说话、互相接话，但不要代别人发言，也不要复述或引用别人的话。'
      '不要重复别人刚说过的话，不要原样回显上一条消息。'
      '刚才大家聊的内容见历史消息，直接说你要说的话。'
      '群聊回复要适合移动端阅读：动作、环境或内心独白可以单独成段，对白使用中文引号，内心独白使用全角括号；不要把所有角色写成同一种格式。';
  if (isNewChat) {
    return '$base\n[开始一个新的群聊。群成员: $memberList]';
  }
  return base;
}

/// 群聊 nudge：告诉 LLM 只以指定角色发言（对标 ST group_nudge_prompt）
String buildGroupNudge(String selfName) =>
    '[请只以「$selfName」的身份继续发言。接续上文继续聊，不要重复别人或自己说过的话，不要原样回显上一条消息，直接说新内容。]';

/// 每个成员单独生成时的身份与声线锚点。
/// 群共享记忆只能提供共同事实，不能把成员写成同一个说话的人。
String buildMemberVoicePrompt({
  required AICharacter self,
  required List<AICharacter> otherMembers,
  required List<String> recentReplies,
  List<String> avoidReplies = const [],
}) {
  String value(String? text) => text?.trim() ?? '';
  final others = otherMembers.map((member) {
    final style = value(member.languageStyle);
    final trait = member.personality.trim();
    return '- ${member.name}${style.isNotEmpty ? '：$style' : trait.isNotEmpty ? '：$trait' : ''}';
  }).join('\n');
  final recent = recentReplies.isEmpty
      ? '（本轮暂无其他角色回复）'
      : recentReplies.map((reply) => '- $reply').join('\n');
  final avoid = avoidReplies.isEmpty
      ? ''
      : '\n\n本次生成明确禁止复用的候选内容（换一个观点或推进方向）：\n${avoidReplies.map((reply) => '- $reply').join('\n')}';
  final style = value(self.languageStyle);
  final catchphrases = value(self.catchphrases);
  final examples = self.dialogueExamples
      .take(2)
      .map((example) =>
          '用户：${example.userMessage}\n${self.name}：${example.aiResponse}')
      .join('\n');

  return '''
【你的群聊身份不可替代】
你只能作为「${self.name}」发言，不是群聊旁白，也不是其他成员的混合人格。
你的性格：${self.personality}
${style.isEmpty ? '' : '你的语言风格：$style'}
${catchphrases.isEmpty ? '' : '你的习惯用语：$catchphrases'}
${self.currentStatus == null || self.currentStatus!.trim().isEmpty ? '' : '你此刻状态：${self.currentStatus!.trim()}'}
${examples.isEmpty ? '' : '你的既有说话示例：\n$examples'}

其他成员的声线（只用于区分，绝不可模仿或代说）：
$others

本轮已出现的回复：
$recent
$avoid

必须遵守：
1. 只表达你自己的观察、立场和措辞；不要替其他角色总结、补全或代言。
2. 不得复用本轮其他角色的句式、比喻、结论、开头或口头禅；即使观点相同，也要换成你的角度。
3. 不要用“大家”“我们都觉得”抹平差异。可以不同意、补充细节、转移话题，或选择简短回应。
4. 直接输出你的新消息，不要输出角色名、分析说明或对规则的回应。
''';
}

String normalizeGroupReply(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[\s，。！？、；：,.!?;:"“”‘’（）()【】\[\]{}<>《》…~～\-]+'), '');

/// 面向群聊短消息的保守相似度：短句只判定完全相同，长句按字符 bigram 的 Dice
/// 系数判定，避免“嗯”“好”“我也这么觉得”这类正常短接话被误杀。
bool isDuplicateGroupReply(String candidate, String previous) {
  final a = normalizeGroupReply(candidate);
  final b = normalizeGroupReply(previous);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  if (a.length < 10 || b.length < 10) return false;
  final aBigrams = <String>{
    for (var i = 0; i < a.length - 1; i++) a.substring(i, i + 2),
  };
  final bBigrams = <String>{
    for (var i = 0; i < b.length - 1; i++) b.substring(i, i + 2),
  };
  if (aBigrams.isEmpty || bBigrams.isEmpty) return false;
  final overlap = aBigrams.intersection(bBigrams).length;
  final dice = (2 * overlap) / (aBigrams.length + bBigrams.length);
  return dice >= 0.78;
}

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
