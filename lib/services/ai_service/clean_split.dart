// AIService 清洗/分句/繁简转换：响应清洗、分段、简洁截断等纯文本处理方法。
// 本文件是 ai_service.dart 的 part，与其共同构成一个库。

part of '../ai_service.dart';

mixin AIServiceCleanSplitApi on _AIServiceCore {
  List<String> splitIntoMessages(String response) {
    if (response.isEmpty) return ['嗯，让我想想该怎么回答你。'];

    // 小说模式（完整输出）或自动分段关闭时，整条回复作为一个气泡，不拆成微信式多气泡
    if (_storage.isChatStyleNovelModeEnabled() ||
        !_storage.isAutoParagraphEnabled()) {
      return [response];
    }

    final messages = <String>[];

    // 处理贴纸标签
    final stickerPattern =
        RegExp(r'\[STICK\w*:([^\]]+)\]', caseSensitive: false);
    final parts = response.split(stickerPattern);
    final stickerMatches = stickerPattern.allMatches(response).toList();

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      if (part.isNotEmpty) {
        final textParts = _splitTextPart(part, maxGroupLength: 120);
        messages.addAll(textParts);
      }

      if (i < stickerMatches.length) {
        messages.add('[STICKER:${stickerMatches[i].group(1)}]');
      }
    }

    if (messages.isEmpty) {
      messages.add(response);
    }

    return messages;
  }

  /// 分段文本部分
  List<String> _splitTextPart(String text, {required int maxGroupLength}) {
    final rawParts = <String>[];
    // 优先按段落（换行符）切割
    final paragraphs = text.split(RegExp(r'\n+'));

    for (var paragraph in paragraphs) {
      paragraph = paragraph.trim();
      if (paragraph.isEmpty) continue;

      // 短段落直接保留
      if (paragraph.length <= maxGroupLength) {
        rawParts.add(paragraph);
        continue;
      }

      // 长段落按句子切割
      final sentences = _splitIntoSentences(paragraph);
      final grouped = <String>[];
      final group = StringBuffer();

      for (final sentence in sentences) {
        if (group.isEmpty) {
          group.write(sentence);
        } else if (group.length + sentence.length <= maxGroupLength) {
          group.write(sentence);
        } else {
          grouped.add(group.toString());
          group.clear();
          group.write(sentence);
        }
      }

      if (group.isNotEmpty) {
        grouped.add(group.toString());
      }

      // 兜底：如果某段仍然超过 maxGroupLength，强制按字符数切割
      for (final g in grouped) {
        if (g.length > maxGroupLength * 1.5) {
          rawParts.addAll(_forceSplit(g, maxGroupLength));
        } else {
          rawParts.add(g);
        }
      }
    }

    // 连续短段合并：连续 <40 字的段落合并到接近 maxGroupLength
    return _mergeShortParts(rawParts, maxGroupLength);
  }

  /// 连续短段合并
  List<String> _mergeShortParts(List<String> parts, int maxGroupLength) {
    if (parts.length <= 1) return parts;

    const shortThreshold = 40;
    final result = <String>[];
    final buffer = StringBuffer();

    for (final part in parts) {
      if (part.length < shortThreshold &&
          buffer.length + part.length < maxGroupLength) {
        // 短段落且合并后不超限，追加到 buffer
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(part);
      } else {
        // 长段落或合并后会超限，先 flush buffer
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        result.add(part);
      }
    }

    if (buffer.isNotEmpty) {
      result.add(buffer.toString());
    }

    return result;
  }

  /// 按句子切割文本（引号感知版：防止引号内分句导致对白断裂）
  List<String> _splitIntoSentences(String text) {
    final sentences = <String>[];
    final currentSentence = StringBuffer();
    bool insideQuote = false; // 追踪是否在引号对内部

    for (int j = 0; j < text.length; j++) {
      currentSentence.write(text[j]);

      // 追踪引号边界
      if (text[j] == '“' || text[j] == '「' || text[j] == '『') {
        insideQuote = true;
      } else if (text[j] == '”' || text[j] == '」' || text[j] == '』') {
        insideQuote = false;
      }

      // 句末标点（中英文）
      final isEndPunctuation =
          ['。', '！', '？', '!', '?', '；', ';', '：', ':'].contains(text[j]);
      // 省略号结尾
      final isEllipsis = text[j] == '…' &&
          j + 2 < text.length &&
          text[j + 1] == '…' &&
          text[j + 2] == '…';
      // 换行符
      final isNewline = text[j] == '\n';

      // 引号内部不分割，确保对白完整性
      final shouldSplit = (isEndPunctuation || isEllipsis || isNewline) &&
          currentSentence.length >= 5 &&
          !insideQuote;

      if (shouldSplit && j + 1 < text.length) {
        final next = text[j + 1];
        // 避免在连续标点处切割
        if (![
          '。',
          '！',
          '？',
          '，',
          ',',
          '、',
          '；',
          ';',
          '：',
          ':',
          '"',
          '"',
          '」',
          '…',
          '\n'
        ].contains(next)) {
          sentences.add(currentSentence.toString().trim());
          currentSentence.clear();
        }
      }
    }

    if (currentSentence.isNotEmpty) {
      sentences.add(currentSentence.toString().trim());
    }

    return sentences;
  }

  /// 强制按字符数切割（兜底规则）
  List<String> _forceSplit(String text, int maxLength) {
    final result = <String>[];
    var remaining = text;

    while (remaining.length > maxLength) {
      // 尝试在 maxLength 附近找到合适的切割点
      var cutIndex = maxLength;
      // 往前找标点
      for (int i = maxLength; i > maxLength - 30 && i > 0; i--) {
        if (['。', '！', '？', '!', '?', '；', ';', '，', ',', '、', '…', '\n']
            .contains(remaining[i])) {
          cutIndex = i + 1;
          break;
        }
      }
      result.add(remaining.substring(0, cutIndex).trim());
      remaining = remaining.substring(cutIndex).trim();
    }

    if (remaining.isNotEmpty) {
      result.add(remaining);
    }

    return result;
  }

  String _extractResponseContent(dynamic data) {
    if (data is Map<String, dynamic>) {
      // ─── OpenAI Responses API 格式 ───
      if (data['output_text'] != null && data['output_text'] is String) {
        return data['output_text'] as String;
      }
      if (data['output'] != null && data['output'] is List) {
        final output = data['output'] as List;
        for (final item in output) {
          if (item is Map<String, dynamic>) {
            if (item['type'] == 'message' && item['content'] is List) {
              final contentList = item['content'] as List;
              final texts = <String>[];
              for (final c in contentList) {
                if (c is Map<String, dynamic> && c['text'] != null) {
                  texts.add(c['text'] as String);
                }
              }
              if (texts.isNotEmpty) return texts.join();
            }
            if (item['content'] != null && item['content'] is String) {
              return item['content'] as String;
            }
          }
        }
      }

      // ─── Anthropic Claude 格式 ───
      // content: [{type: 'text', text: '...'}]
      if (data['content'] != null && data['content'] is List) {
        final contentList = data['content'] as List;
        final texts = <String>[];
        for (final c in contentList) {
          if (c is Map<String, dynamic> &&
              c['type'] == 'text' &&
              c['text'] != null) {
            texts.add(c['text'] as String);
          }
        }
        if (texts.isNotEmpty) return texts.join();
      }

      // ─── OpenAI Chat Completions 格式 ───
      if (data['choices'] != null && data['choices'].isNotEmpty) {
        final choice = data['choices'][0];
        if (choice['message'] != null) {
          final msgContent = choice['message']['content'] as String?;
          // content 为空时回退到 reasoning_content（DeepSeek V4 等模型）
          if (msgContent != null && msgContent.trim().isNotEmpty) {
            return msgContent;
          }
          // 兼容不同提供商的 reasoning 字段命名
          final reasoning = (choice['message']['reasoning_content'] ??
              choice['message']['reasoning'] ??
              choice['message']['thinking']) as String?;
          if (reasoning != null && reasoning.trim().isNotEmpty) {
            return reasoning;
          }
          // choice 级别 reasoning（部分提供商将 reasoning 放在 choice 而非 message 内）
          final choiceReasoning = (choice['reasoning_content'] ??
              choice['reasoning'] ??
              choice['thinking']) as String?;
          if (choiceReasoning != null && choiceReasoning.trim().isNotEmpty) {
            return choiceReasoning;
          }
          return msgContent ?? '';
        } else if (choice['text'] != null) {
          return choice['text'] as String? ?? '';
        }
      }

      // ─── 国产 API 常见格式 ───
      if (data['result'] != null && data['result'] is String) {
        return data['result'] as String;
      }
      if (data['data'] != null && data['data'] is Map) {
        final d = data['data'] as Map;
        if (d['text'] != null) return d['text'] as String;
        if (d['content'] != null) return d['content'] as String;
      }
      // 通用 fallback
      if (data['text'] != null) {
        return data['text'] as String? ?? '';
      }
      if (data['response'] != null) {
        return data['response'] as String? ?? '';
      }
      if (data['content'] != null && data['content'] is String) {
        return data['content'] as String;
      }
      // reasoning 字段兜底（思考模型可能只返回 reasoning）
      if (data['reasoning_content'] != null &&
          data['reasoning_content'] is String) {
        return data['reasoning_content'] as String;
      }
      if (data['reasoning'] != null && data['reasoning'] is String) {
        return data['reasoning'] as String;
      }
      if (data['thinking'] != null && data['thinking'] is String) {
        return data['thinking'] as String;
      }
    }

    throw Exception('Invalid response format: ${data.runtimeType}');
  }

  Future<ForgivenessJudgment> considerForgiveness({
    required AICharacter character,
    required String userId,
    required List<ChatMessage> userMessagesSinceBlock,
    String? blockReason,
  }) async {
    try {
      final userMsgSummary =
          userMessagesSinceBlock.take(10).map((m) => m.content).join('\n');

      final blockReasonText = blockReason == 'nsfw'
          ? '对方发送了违规内容'
          : blockReason == 'extreme_sadness'
              ? '对方让你极度难过'
              : blockReason == 'extreme_anger'
                  ? '对方让你极度愤怒'
                  : '对方的行为让你不舒服';

      final prompt = StringBuffer();
      prompt.writeln(
          '你是${character.name}。你的性格是：${const PromptRewriter().rewriteCharacterField(character.personality)}。');
      prompt.writeln('你之前因为「$blockReasonText」而拉黑了对方。');
      prompt.writeln('');
      prompt.writeln('对方被拉黑后发了${userMessagesSinceBlock.length}条消息：');
      prompt.writeln(userMsgSummary);
      prompt.writeln('');
      prompt.writeln('现在你要自己判断：要不要原谅对方？');
      prompt.writeln('考虑因素：');
      prompt.writeln('- 对方的态度是否真诚');
      prompt.writeln('- 你自己现在的心情');
      prompt.writeln('- 你和对方的关系');
      prompt.writeln('- 你想不想继续和对方说话');
      prompt.writeln('');
      prompt.writeln(
          '用JSON格式回复：{"forgive": true/false, "message": "如果原谅，说一句自然的话；不原谅则空字符串"}');
      prompt.writeln('只输出JSON，不要有其他内容。');

      final config = await _storage.getActiveAIConfig();
      if (config == null) {
        return const ForgivenessJudgment(
            shouldForgive: false, forgiveMessage: '');
      }
      final apiKey = config.apiKey;
      String baseUrl = config.baseUrl.trim();
      while (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }
      final url = baseUrl.endsWith('/chat/completions')
          ? Uri.parse(baseUrl)
          : Uri.parse('$baseUrl/chat/completions');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept-Charset': 'utf-8',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': config.modelName,
              'messages': [
                {'role': 'system', 'content': prompt.toString()},
                {'role': 'user', 'content': '请做出你的判断。'},
              ],
              'temperature': 0.8,
              'max_tokens': 200,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = await _decodeBody(
            response.headers['content-type'], response.bodyBytes);
        final data = jsonDecode(body);
        final content = _extractResponseContent(data);

        final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(content);
        if (jsonMatch != null) {
          final parsed = jsonDecode(jsonMatch.group(0)!);
          return ForgivenessJudgment(
            shouldForgive: parsed['forgive'] == true,
            forgiveMessage: (parsed['message'] as String?) ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint('===== AIService.considerForgiveness failed: $e =====');
    }

    return const ForgivenessJudgment(shouldForgive: false, forgiveMessage: '');
  }
}
