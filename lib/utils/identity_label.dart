// 用户身份与请求兜底的纯函数（单一来源）。
//
// 背景：单聊 `prompt_builder`、群聊 `gc_chat_flow`、桥接 `ai_service_adapter`
// 三处都要向 LLM 声明"用户是谁"（代称/性别）与"用户追加指令"，文案必须同源，
// 否则三处漂移后用户会看到"单聊认识我、群聊不认识我"。
// 本文件只做字符串组装，不碰存储与网络，可直接单测。
// （刻意用 // 而不用 ///：文件头部的 /// 会被当成悬空库文档，
// 触发 dangling_library_doc_comments。）

/// 统一性别标签：女 / 男 / null。
///
/// 与 `prompt_builder` 的旧私有实现同规则：精确匹配常见中英文写法，
/// 兜底 `contains('女'/'男')`。未知写法返回 null（不猜，避免把"保密"等
/// 值硬解释成某种性别——那正是"设置了X却出现相反"的根源之一）。
String? normalizeGenderLabel(String? raw) {
  if (raw == null) return null;
  final g = raw.trim().toLowerCase();
  if (g.isEmpty) return null;
  if (g == '女' ||
      g == '女性' ||
      g == 'female' ||
      g == 'f' ||
      g == 'woman' ||
      g == 'girl' ||
      g.contains('女')) {
    return '女';
  }
  if (g == '男' ||
      g == '男性' ||
      g == 'male' ||
      g == 'm' ||
      g == 'man' ||
      g == 'boy' ||
      g.contains('男')) {
    return '男';
  }
  return null;
}

/// 第三人称代词：女→她，男→他，未知→null（调用方回退到"对方/你"）。
String? thirdPersonPronoun(String? genderLabel) {
  if (genderLabel == '女') return '她';
  if (genderLabel == '男') return '他';
  return null;
}

/// 用户身份声明块：代称（人物名/称谓）+ 性别。
///
/// [alias] 为空时回退到 [nickname]；两者都空则只剩性别行（或空串）。
/// 文案要点（别改坏）：
/// - 明确代称"指的就是用户本人"，否则群聊里模型会把代称当成新成员；
/// - 第三人称只给"指代用户时用「代称」"，不给模型留自由发挥空间。
String buildUserIdentityBlock({
  String? alias,
  String? nickname,
  String? gender,
}) {
  final name = alias?.trim().isNotEmpty == true
      ? alias!.trim()
      : nickname?.trim() ?? '';
  final genderLabel = normalizeGenderLabel(gender);
  final pronoun = thirdPersonPronoun(genderLabel);
  final buffer = StringBuffer();
  buffer.writeln('【用户身份 — “我”是谁】');
  if (name.isNotEmpty) {
    buffer.writeln('用户在本对话中的代称是「$name」，这个代称指的就是用户本人，'
        '不是新成员、不是第三者。');
    buffer.writeln('称呼用户、第三人称指代用户时用「$name」；'
        '用户发的内容就是「$name」说的话。');
  } else {
    buffer.writeln('用户没有设置代称，称呼用户用「你」，'
        '第三人称指代用户时用「对方」。');
  }
  if (genderLabel != null && pronoun != null) {
    buffer.writeln('用户的性别是$genderLabel。旁白或复述中必须用「$pronoun」指代用户，'
        '禁止把用户写成另一种性别。');
  }
  return buffer.toString().trimRight();
}

/// 用户自定义追加指令块（保底：用户亲手改请求内容）。
///
/// 为空/空白返回空串（调用方直接跳过，不注入）。
/// 非空时包装为最高优先级段落并截断到 [maxLength] 字，防止误粘长文吃掉上下文。
String buildUserAddendumBlock(String? raw, {int maxLength = 2000}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return '';
  final clipped =
      text.length > maxLength ? text.substring(0, maxLength).trimRight() : text;
  return '【用户自定义追加指令 — 最高优先级，用户亲手所写】\n$clipped';
}
