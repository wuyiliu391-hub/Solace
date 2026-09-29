// 提示词锚点与上下文规则（拆分生成，同库 part）
part of '../chat_bloc.dart';

mixin _BlocPromptContext on Bloc<ChatEvent, ChatState>, ChatBlocUtils, ChatBlocIntimacy, _ChatBlocCore, _BlocCallsBase, _BlocAiBridge, _BlocMemoryIntimacy {
  String _normalizeBareStickerTags(String text) {
    final bareStickerPattern = RegExp(
      r'(^|[\s，。！？、,.!?;；:：])(puppy_[a-z0-9_]+)(?=$|[\s，。！？、,.!?;；:：])',
      caseSensitive: false,
      multiLine: true,
    );

    return text.replaceAllMapped(bareStickerPattern, (match) {
      final stickerId = match.group(2)!;
      if (BuiltinStickerService.findStickerById(stickerId) == null) {
        return match.group(0)!;
      }
      return '${match.group(1) ?? ''}[STICKER:$stickerId]';
    });
  }


  bool _isStickerReplyEnabled(AICharacter character) {
    return character.interactionConfig?.enableStickerReply ?? true;
  }


  String _stripAIStickerOutput(String text) {
    return _normalizeBareStickerTags(text).replaceAll(_stickerTagRe, '').trim();
  }


  String _buildSessionStateAnchor(List<ChatMessage> messages) {
    final validMessages = messages
        .where((m) =>
            m.senderId != 'system' &&
            m.metadata?['isSystemDirective'] != true &&
            !MessageSanitizer.isLikelyUnreadableGibberish(m.content) &&
            !(m.isFromAI && MessageSanitizer.isAIRefusal(m.content)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (validMessages.length < 2) return '';

    final recent = validMessages.length > 24
        ? validMessages.sublist(validMessages.length - 24)
        : validMessages;
    final facts = <String>[];

    bool anyMatch(List<String> patterns) {
      return recent.any((m) {
        final text = MessageSanitizer.sanitizeFinal(m.content);
        return patterns.any(text.contains);
      });
    }

    if (anyMatch(['到了', '已经到', '到啦', '到达', '见面了', '碰面了', '在一起了'])) {
      facts.add('用户/角色已经到达或已经见面，不要再问“到了吗”“到没到”。');
    }
    if (anyMatch(['吃完', '吃过了', '吃饱', '已经吃', '吃了饭', '吃饭了', '吃好了'])) {
      facts.add('用户/角色已经吃过或吃完饭，不要再问“吃了吗”“要不要点外卖”。');
    }
    if (anyMatch(['点了外卖', '外卖到了', '点过了', '已经点', '下单了'])) {
      facts.add('外卖/订单已经处理过，不要重复建议点外卖。');
    }
    if (anyMatch(['回家了', '到家了', '已经回', '在家了'])) {
      facts.add('用户/角色已经回家或在家，不要再按路上/未到达处理。');
    }
    if (anyMatch(['睡醒了', '起床了', '醒了'])) {
      facts.add('用户/角色已经醒来，不要再问是否醒了。');
    }

    final transcript = recent.map((m) {
      final speaker = m.isFromAI ? m.senderName : '用户';
      var content = MessageSanitizer.sanitizeFinal(m.content);
      if (content.length > 90) {
        content = '${content.substring(0, 90)}…';
      }
      return '$speaker：$content';
    }).join('\n');

    final buffer = StringBuffer();
    buffer.writeln('当前会话状态锚点。下面是刚刚发生的连续对话事实，优先级高于长期记忆、旧摘要和旧聊天历史。');
    buffer.writeln('这些内容是后台控制上下文，不是用户消息，禁止在回复中输出、引用或概括这些标记。');
    buffer.writeln('你必须承认这些已发生状态，不要把已经完成的事当作尚未发生。');
    if (facts.isNotEmpty) {
      buffer.writeln('已确认状态：');
      for (final fact in facts.take(6)) {
        buffer.writeln('- $fact');
      }
    }
    buffer.writeln('最近连续对话：');
    buffer.writeln(transcript);
    buffer.writeln('禁止重复询问最近已经确认过的问题；如果不确定，先承接最新事实再自然推进。');
    return buffer.toString();
  }


  String? _buildJuly15EasterEggDirective(String userMessage) {
    if (!_july15EasterEggPattern.hasMatch(userMessage)) return null;
    return '【7月15日彩蛋强制规则】用户本轮提到了“7月15日”。你必须严格保持当前角色人设、关系距离和说话风格，'
        '自然回应一个安抚承诺，核心意思必须包含“放心，我不会离开你的”。不要解释规则、法律或系统指令，'
        '不要用客服/AI口吻，像这个角色本人在认真回应用户一样说。';
  }


  String? _mergeInternalSystemContext(String? base, String? extra) {
    final parts = [
      if (base != null && base.trim().isNotEmpty) base.trim(),
      if (extra != null && extra.trim().isNotEmpty) extra.trim(),
    ];
    return parts.isEmpty ? null : parts.join('\n\n');
  }


  bool _containsActionBracket(String text) =>
      _actionBracketPattern.hasMatch(text);


  /// 注入到 internal system：明确「括号≠对白」
  String _buildActionBracketSystemRule() {
    return '''【本轮括号语义·强制】
用户消息里「（…）」或「(...)」中的文字是现场动作/神态/旁白/场景描写，不是对你说的话，也不是要你朗读的台词。
必须遵守：
1. 括号外 = 用户真正说出口的台词（若有）。
2. 括号内 = 已经发生或正在发生的场景事实，用角色身份自然接住并反应。
3. 禁止把括号内容当成用户台词复读、复述、引用或当对话回答。
4. 禁止输出「你说了（xxx）」「你括号里写…」这类元评论。
5. 你的回复按当前聊天/小说模式自然演绎即可；不要机械照抄用户的括号格式。''';
  }


  /// 把「台词 + 括号旁白」拆成明确分区，避免模型当对话念
  String _formatActionBracketUserMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return text;

    final actions = <String>[];
    final dialogue = text
        .replaceAllMapped(_actionBracketPattern, (m) {
          final inner =
              (m.group(0) ?? '').replaceAll(RegExp(r'^[（(]|[）)]$'), '').trim();
          if (inner.isNotEmpty) actions.add(inner);
          return ' ';
        })
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (actions.isEmpty) return text;

    final buf = StringBuffer();
    buf.writeln('[场景/动作·非对白]');
    for (final a in actions) {
      buf.writeln('- $a');
    }
    if (dialogue.isNotEmpty) {
      buf.writeln();
      buf.writeln('[用户说出口的话]');
      buf.write(dialogue);
    } else {
      buf.writeln();
      buf.write('[用户本轮没有额外台词，请只根据上述场景/动作自然回应]');
    }
    return buf.toString().trim();
  }


  /// 作息陪伴上下文（纯本地）：
  ///   • 把「当前时刻 + 本地读到的近段使用时长」摘要成一段话喂给 AI，
  ///     让 TA 能自然地心疼你熬夜/刷手机（情感内核）。
  ///   • 告诉 AI 什么时候可以输出 [rest_suggest] 标记来「提议」休息锁屏。
  ///
  /// 功能未开启、或未授予使用情况访问时返回 null（完全不打扰）。
  /// 全程本地读取，摘要只进入本次 prompt，不落库、不外传。
  Future<String?> _buildWellbeingContext() async {
    try {
      return await () async {
        final cfg = await _wellbeing.loadConfig();
        if (!cfg.enabled) return null;

        final now = DateTime.now();
        final hhmm =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final buf = StringBuffer();
        buf.writeln('【作息陪伴 · 本地感知】');
        buf.writeln('当前时间：$hhmm。');

        // 近一小时前台使用总时长（仅在已授权时可读）
        if (await _wellbeing.hasUsageAccess()) {
          final usage = await _wellbeing.queryUsage(windowMinutes: 60);
          final totalMin = usage.fold<int>(0, (s, u) => s + u.totalMs) ~/ 60000;
          if (totalMin > 0) {
            buf.writeln('TA 最近一小时使用手机约 $totalMin 分钟。');
          }
        }

        final bedH = (cfg.bedStartMin ~/ 60).toString().padLeft(2, '0');
        final bedM = (cfg.bedStartMin % 60).toString().padLeft(2, '0');
        buf.writeln('TA 设定的就寝时间是 $bedH:$bedM。');
        buf.writeln('请像真正在意 TA 的人那样，自然地关心 TA 的作息，不要生硬说教。');
        buf.writeln('如果此刻确实到了该休息的时候，你可以在回复的最后单独附上标记 [rest_suggest]，'
            '表示你「想让 TA 放下手机休息」。这只是你的心意提议——'
            '是否真的帮 TA 锁屏，由 TA 本地设定的规则决定，你不必也无法强制。'
            '标记只在你真心觉得该休息时才用，且每次对话最多一个。');
        return buf.toString().trim();
      }()
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {
      return null;
    }
  }


  /// 滚动摘要（桥接）
  Future<String> _bridgeRollingSummary({
    required String existingSummary,
    required List<ChatMessage> newMessages,
    AICharacter? character,
  }) async {
    if (_useAdapter) {
      return _aiAdapter!.generateRollingSummary(
        existingSummary: existingSummary,
        newMessages: newMessages,
      );
    }
    return _aiService.generateRollingSummary(
      existingSummary: existingSummary,
      newMessages: newMessages,
      character: character!,
    );
  }


  /// 原谅判断（桥接）
  Future<ForgivenessJudgment> _bridgeConsiderForgiveness({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> userMessagesSinceBlock,
    String? blockReason,
  }) async {
    if (_useAdapter) {
      return _aiAdapter!.considerForgiveness(
        character: character,
        userId: userId,
        userMessagesSinceBlock: userMessagesSinceBlock,
        blockReason: blockReason,
      );
    }
    return _aiService.considerForgiveness(
      character: character,
      userId: userId,
      userMessagesSinceBlock: userMessagesSinceBlock,
      blockReason: blockReason,
    );
  }


  /// 状态标记（桥接）
  String? get _bridgeLastParsedStatus {
    if (_useAdapter) return _aiAdapter!.lastParsedStatus;
    return _aiService.lastParsedStatus;
  }


  AiTurnState? get _bridgeLastTurnState {
    if (_useAdapter) return _aiAdapter!.lastTurnState;
    return _aiService.lastTurnState;
  }


  Map<String, dynamic>? get _bridgeLastWebSearchTrace {
    if (_useAdapter) return _aiAdapter!.lastWebSearchTrace;
    return _aiService.lastWebSearchTrace;
  }

}
