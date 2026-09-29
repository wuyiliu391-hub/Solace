/// 文本分段工具 — 纯函数，将 AI 回复拆分为多气泡消息
///
/// 职责：
/// - 按段落/句子/字符数分割 AI 回复
/// - 处理 STICKER 标签
///
/// 从 AIService 提取，保持与原逻辑 100% 一致。
class TextSplitter {
  const TextSplitter._();

  /// 将完整 AI 回复拆分为多条消息气泡
  ///
  /// [autoParagraph] 为 false 时整条回复作为一个气泡
  static List<String> splitIntoMessages(
    String response, {
    required bool autoParagraph,
  }) {
    if (response.isEmpty) return ['嗯，让我想想该怎么回答你。'];

    if (!autoParagraph) {
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

  /// TTS 专用分割（与 splitIntoMessages 逻辑一致，maxGroupLength 可配置）
  static List<String> splitIntoTtsChunks(
    String text, {
    int maxGroupLength = 80,
  }) {
    if (text.isEmpty) return [];
    return _splitTextPart(text, maxGroupLength: maxGroupLength);
  }

  // ──────────────── 私有辅助方法 ────────────────

  static List<String> _splitTextPart(
    String text, {
    required int maxGroupLength,
  }) {
    final rawParts = <String>[];
    final paragraphs = text.split(RegExp(r'\n+'));

    for (var paragraph in paragraphs) {
      paragraph = paragraph.trim();
      if (paragraph.isEmpty) continue;

      if (paragraph.length <= maxGroupLength) {
        rawParts.add(paragraph);
        continue;
      }

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

      for (final g in grouped) {
        if (g.length > maxGroupLength * 1.5) {
          rawParts.addAll(_forceSplit(g, maxGroupLength));
        } else {
          rawParts.add(g);
        }
      }
    }

    return _mergeShortParts(rawParts, maxGroupLength);
  }

  static List<String> _splitIntoSentences(String text) {
    final sentences = <String>[];
    final currentSentence = StringBuffer();
    bool insideQuote = false; // 追踪是否在引号对内部，防止引号内分句导致对白断裂

    for (int j = 0; j < text.length; j++) {
      currentSentence.write(text[j]);

      // 追踪引号边界：左引号进入对白，右引号退出对白
      if (text[j] == '\u201C' || text[j] == '「' || text[j] == '『') {
        insideQuote = true;
      } else if (text[j] == '\u201D' || text[j] == '」' || text[j] == '』') {
        insideQuote = false;
      }

      // 句号、感叹号、问号为自然断句点；分号和冒号不作为分句标点（中文语境下它们连接相关内容）
      final isEndPunctuation =
          ['。', '！', '？', '!', '?'].contains(text[j]);
      final isEllipsis = text[j] == '…' &&
          j + 2 < text.length &&
          text[j + 1] == '…' &&
          text[j + 2] == '…';
      final isNewline = text[j] == '\n';

      // 引号内部不分割，确保对白完整性；最小分句长度8字符，避免过多小气泡
      final shouldSplit =
          (isEndPunctuation || isEllipsis || isNewline) &&
              currentSentence.length >= 8 &&
              !insideQuote;

      if (shouldSplit && j + 1 < text.length) {
        final next = text[j + 1];
        if (![
          '。', '！', '？', '，', ',', '、', '；', ';',
          '：', ':', '"', '"', '」', '…', '\n'
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

  static List<String> _forceSplit(String text, int maxLength) {
    final result = <String>[];
    var remaining = text;

    while (remaining.length > maxLength) {
      var cutIndex = maxLength;
      bool foundCut = false;

      // 从 maxLength 向前扫描，寻找引号外的分割点
      for (int i = maxLength;
          i > maxLength - 30 && i > 0;
          i--) {
        if ([
          '。', '！', '？', '!', '?', '；', ';',
          '，', ',', '、', '…', '\n'
        ].contains(remaining[i])) {
          // 检查该位置是否在引号内部
          bool inside = false;
          for (int k = 0; k <= i; k++) {
            if (remaining[k] == '\u201C' || remaining[k] == '「' || remaining[k] == '『') {
              inside = !inside;
            } else if (remaining[k] == '\u201D' || remaining[k] == '」' || remaining[k] == '』') {
              inside = !inside;
            }
          }
          if (!inside) {
            cutIndex = i + 1;
            foundCut = true;
            break;
          }
        }
      }

      // 如果在引号外找不到分割点，尝试在左引号处分割（让引号对整体移到下一个气泡）
      if (!foundCut) {
        for (int i = maxLength; i > maxLength - 30 && i > 0; i--) {
          if (remaining[i] == '\u201C' || remaining[i] == '「' || remaining[i] == '『') {
            cutIndex = i;
            foundCut = true;
            break;
          }
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

  static List<String> _mergeShortParts(
    List<String> parts,
    int maxGroupLength,
  ) {
    if (parts.length <= 1) return parts;

    const shortThreshold = 40;
    final result = <String>[];
    final buffer = StringBuffer();

    for (final part in parts) {
      if (part.length < shortThreshold &&
          buffer.length + part.length < maxGroupLength) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(part);
      } else {
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
}
