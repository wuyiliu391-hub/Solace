// 库级共享常量（原类内 static 值字段，拆分提升为顶层，全库可见）
part of '../chat_bloc.dart';

// ── 预编译正则（避免每条消息重复编译）──
final RegExp _stickerTagRe =
    RegExp(r'\[STICK\w*:([^\]]+)\]', caseSensitive: false);

final RegExp _stickerFullLineRe =
    RegExp(r'^\[STICK\w*:([^\]]+)\]$', caseSensitive: false);


/// 作息陪伴 — AI「想让你休息」的意图标记。
/// 注意：这只是 AI 的「提议」，是否真的锁屏由本地闸（WellbeingService.evaluate）
/// 依据用户本地设定的就寝时段/使用时长规则独立判定，AI 无法绕过本地闸。
final RegExp _restSuggestRe =
    RegExp(r'\[rest_suggest\]', caseSensitive: false);

/// 实时增量微记忆（不走 LLM）——补「刚说的事」连续性。
/// 放宽触发：关键词命中 **或** 信息密度足够的长句，避免极少数用户永远写不进库。
const Duration _microCooldown = Duration(minutes: 3);

final RegExp _microUserRegex = RegExp(
  r'(?:我在|我住|我家|我下周|我明天|我后天|我今天|我昨天|我要去|我想|'
  r'我考了|我过了|我升|我辞职|我搬家|我生日|我叫|我属|我是|'
  r'我喜欢|我不喜欢|我讨厌|我习惯|我常|我一般|我觉得|我认为|'
  r'约定|说好|答应|以后会|记得|别忘|跟你说|告诉你|'
  r'下周|明天|后天|周末|下班|上班|学校|公司|家里)',
  caseSensitive: false,
);

final RegExp _microAiRegex = RegExp(
  r'(?:那你|我知道了|记住了|以后|你说过|你喜欢|你在|我会记|记下来)',
  caseSensitive: false,
);

final List<String> _microIgnoreSubstrings = [
  '好的好的',
  '哈哈哈哈',
  '嗯嗯嗯',
  '嗯嗯',
  '哈哈哈',
  '呵呵呵',
  'www',
  '哈哈哈',
];


final RegExp _july15EasterEggPattern = RegExp(
  r'(?:0?7\s*月\s*(?:15|十五)\s*(?:日|号)?|七\s*月\s*(?:十\s*五|十五)\s*(?:日|号)?|0?7\s*[./\-_]\s*15|0715)',
  caseSensitive: false,
);


/// 是否含语C动作/旁白括号（全角或半角，括号内有内容）
final RegExp _actionBracketPattern = RegExp(r'（[^（）]+）|\([^()]+\)');
