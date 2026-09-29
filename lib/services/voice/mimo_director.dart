// MiMo TTS 导演模式指令生成器。
//
// 官方导演模式三层结构：【角色】【场景】【指导】——角色层固定（由角色
// 人设驱动），场景/指导层从台词文本 + 角色情绪动态生成。
// 输出放入 voiceclone 请求的 role:user 消息。

import '../../models/ai_character.dart';

/// 为角色生成导演模式指令（role:user 内容）。
///
/// [text]：本次要合成的台词（用于推断场景/情绪）。
/// 返回空串表示不传指令（调用方按官方空 user 处理）。
String buildDirectorPrompt(AICharacter? character, String text) {
  if (character == null) return '';

  final gender = character.gender;
  final personality = character.personality.trim();
  final coreDesire = character.coreDesire.trim();
  final background = character.backgroundStory?.trim() ?? '';
  if (personality.isEmpty && background.isEmpty) return '';

  final sb = StringBuffer();
  sb.writeln('角色：${character.name}。');
  if (personality.isNotEmpty) {
    sb.writeln('性格底色：$personality。');
  }
  if (coreDesire.isNotEmpty) {
    sb.writeln('内心渴望：$coreDesire。');
  }
  if (background.isNotEmpty) {
    sb.writeln('背景：$background。');
  }
  sb.writeln('性别倾向：${gender ?? '未知'}。');
  sb.writeln();
  sb.writeln('场景：正在与最亲密的人对话，说出台词："$text"');
  sb.writeln();
  sb.writeln('指导：');
  sb.writeln('- 语气贴合角色性格底色，情绪随台词自然起伏；');
  sb.writeln('- 语速节奏参考台词中的标点（省略号=停顿、破折号=拖音或被打断）；');
  sb.writeln('- 亲密语境下尾音可带轻微气声，情绪激烈处允许哽咽、颤抖、喘息；');
  sb.writeln('- 保持音色身份稳定，不脱离角色声线。');
  return sb.toString();
}