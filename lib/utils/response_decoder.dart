import 'dart:convert';

class ResponseDecoder {
  ResponseDecoder._();

  /// 从 API 响应 JSON 中提取文本内容
  /// 兼容 OpenAI / Anthropic / 国产 API / 思考模型等多种格式
  static String extractContent(dynamic data) {
    if (data is! Map<String, dynamic>) return data.toString();

    // ─── OpenAI Responses API 格式 ───
    if (data['output_text'] != null && data['output_text'] is String) {
      return data['output_text'] as String;
    }
    if (data['output'] != null && data['output'] is List) {
      for (final item in data['output'] as List) {
        if (item is Map<String, dynamic>) {
          if (item['type'] == 'message' && item['content'] is List) {
            final texts = <String>[];
            for (final c in item['content'] as List) {
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
    if (data['content'] != null && data['content'] is List) {
      final texts = <String>[];
      for (final c in data['content'] as List) {
        if (c is Map<String, dynamic> &&
            c['type'] == 'text' &&
            c['text'] != null) {
          texts.add(c['text'] as String);
        }
      }
      if (texts.isNotEmpty) return texts.join();
    }

    // ─── OpenAI Chat Completions 格式 ───
    if (data['choices'] != null && (data['choices'] as List).isNotEmpty) {
      final choice = (data['choices'] as List)[0];
      if (choice is Map<String, dynamic> && choice['message'] != null) {
        final msg = choice['message'] as Map<String, dynamic>;
        // 优先非空 content
        final msgContent = msg['content'] as String?;
        if (msgContent != null && msgContent.trim().isNotEmpty) {
          return msgContent;
        }
        // 回退到 reasoning 字段（思考模型）
        for (final key in [
          'reasoning_content',
          'reasoning',
          'thinking',
        ]) {
          final v = msg[key] as String?;
          if (v != null && v.trim().isNotEmpty) return v;
        }
        // choice 级别 reasoning
        for (final key in [
          'reasoning_content',
          'reasoning',
          'thinking',
        ]) {
          final v = choice[key] as String?;
          if (v != null && v.trim().isNotEmpty) return v;
        }
        return msgContent ?? '';
      }
      if (choice is Map<String, dynamic> && choice['text'] != null) {
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
    for (final key in ['text', 'response', 'content']) {
      if (data[key] != null && data[key] is String) {
        return data[key] as String;
      }
    }
    // reasoning 字段兜底
    for (final key in ['reasoning_content', 'reasoning', 'thinking']) {
      if (data[key] != null && data[key] is String) {
        return data[key] as String;
      }
    }

    return '';
  }

  static String extractVisibleContent(dynamic data) {
    if (data is! Map<String, dynamic>) return data.toString();

    if (data['output_text'] is String) {
      return data['output_text'] as String;
    }
    final output = data['output'];
    if (output is List) {
      for (final item in output) {
        if (item is Map<String, dynamic>) {
          final type = item['type'];
          if (type is String &&
              ['reasoning', 'thinking', 'analysis'].contains(type)) {
            continue;
          }
          final content = item['content'];
          if (item['type'] == 'message' && content is List) {
            final texts = <String>[];
            for (final c in content) {
              if (c is Map<String, dynamic> && c['text'] is String) {
                texts.add(c['text'] as String);
              }
            }
            if (texts.isNotEmpty) return texts.join();
          }
          if (content is String && content.trim().isNotEmpty) {
            return content;
          }
        }
      }
    }

    final topContent = data['content'];
    if (topContent is List) {
      final texts = <String>[];
      for (final c in topContent) {
        if (c is Map<String, dynamic> &&
            c['type'] == 'text' &&
            c['text'] is String) {
          texts.add(c['text'] as String);
        }
      }
      if (texts.isNotEmpty) return texts.join();
    }

    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map<String, dynamic>) {
        final message = choice['message'];
        if (message is Map<String, dynamic>) {
          for (final key in ['content', 'text']) {
            final value = message[key];
            if (value is String && value.trim().isNotEmpty) return value;
          }
          return message['content'] as String? ?? '';
        }
        final delta = choice['delta'];
        if (delta is Map<String, dynamic>) {
          for (final key in ['content', 'text']) {
            final value = delta[key];
            if (value is String && value.trim().isNotEmpty) return value;
          }
        }
        final text = choice['text'];
        if (text is String) return text;
      }
    }

    final result = data['result'];
    if (result is String) return result;

    final nestedData = data['data'];
    if (nestedData is Map) {
      for (final key in ['text', 'content']) {
        final value = nestedData[key];
        if (value is String) return value;
      }
    }

    for (final key in ['text', 'response', 'content']) {
      final value = data[key];
      if (value is String) return value;
    }

    return '';
  }

  static Future<String> decode(String? contentType, List<int> bytes) async {
    final charset = _charsetFromContentType(contentType);

    String text;
    if (charset == 'latin-1' || charset == 'iso-8859-1') {
      text = repairText(latin1.decode(bytes));
    } else {
      final utf8Text = utf8.decode(bytes, allowMalformed: true);
      final repaired = repairText(utf8Text);
      text = _scoreText(repaired) > _scoreText(utf8Text) ? repaired : utf8Text;
    }

    // 剥离 SSE 格式（data: 前缀和 [DONE] 标记）
    text = stripSSE(text);
    return text;
  }

  /// 剥离 SSE 流式标记，返回纯 JSON 字符串。
  ///
  /// 兼容以下几种情况：
  /// - `data: {"key":"value"}` → `{"key":"value"}`
  /// - `{"key":"value"}data: [DONE]` → `{"key":"value"}`
  /// - `data: {...}\n\ndata: {...}\n\ndata: [DONE]` → `{...}`
  static String stripSSE(String text) {
    var result = text.trim();

    // 去掉每行开头的 "data: " 前缀
    result = result.replaceAll(RegExp(r'^data:\s*', multiLine: true), '');

    // 去掉 "[DONE]" 标记（可能前后无空格或紧贴 JSON）
    result = result.replaceAll('[DONE]', '');

    // 去掉末尾多余的逗号、换行、空白
    result = result.trim();

    // 如果 body 有多行（多个 SSE 事件），只保留第一个完整 JSON
    final firstBrace = result.indexOf('{');
    final lastBrace = result.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      result = result.substring(firstBrace, lastBrace + 1);
    }

    return result.trim();
  }

  static String repairText(String text) {
    var result = _repairMojibake(text);
    result = _repairKnownGbkMojibake(result);
    return result;
  }

  static String? _charsetFromContentType(String? contentType) {
    if (contentType == null) return null;
    final match =
        RegExp("charset=[\\\"']?([^;\\\"'\\s]+)", caseSensitive: false)
            .firstMatch(contentType);
    return match?.group(1)?.toLowerCase().replaceAll('_', '-');
  }

  /// 修复常见 mojibake：UTF-8 中文被错误按 Latin1/Windows-1252 解读后又进入 Dart 字符串。
  static String _repairMojibake(String text) {
    if (!_looksMojibake(text)) return text;
    try {
      final bytes = latin1.encode(text);
      final decoded = utf8.decode(bytes, allowMalformed: true);
      if (_scoreText(decoded) > _scoreText(text)) return decoded;
    } catch (_) {}
    return text;
  }

  static bool _looksMojibake(String text) {
    return text.contains('�') ||
        RegExp(r'[锟斤拷烫屯]{2,}').hasMatch(text) ||
        RegExp(r'[ÃÂâ]{2,}').hasMatch(text) ||
        // GBK mojibake 特征字符
        RegExp(r'[锛堝垰鎵嶈蛋绁炰簡銆鍐璇鐢浣鏈冨勫]').hasMatch(text) ||
        text.runes.any((rune) =>
            rune < 0x20 && rune != 0x0A && rune != 0x0D && rune != 0x09);
  }

  static String _repairKnownGbkMojibake(String text) {
    if (!RegExp(r'鐢ㄦ埛|浣犲|鍥炲|鍥剧墖|锛|銆|涓€').hasMatch(text)) {
      return text;
    }

    const phraseMap = <String, String>{
      '鐢ㄦ埛': '用户',
      '浣犲ソ': '你好',
      '鍥炲': '回复',
      '鍥剧墖': '图片',
      '鐢ㄦ埛鍙戦€佷簡涓€寮犲浘鐗': '用户发送了一张图片',
      '鍙戦€佷簡': '发送了',
      '涓€寮犲浘鐗': '一张图片',
      '鍝堝搱': '哈哈',
      '杩欎釜': '这个',
      '琛ㄦ儏鍖': '表情包',
      '濂芥湁瓒': '好有趣',
      '锛': '，',
      '銆': '。',
      '涓€': '一',
      '涓': '个',
    };

    var result = text;
    for (final entry in phraseMap.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  static int _scoreText(String text) {
    var score = 0;
    for (final rune in text.runes) {
      if (rune == 0xFFFD) score -= 20;
      if (rune >= 0x4E00 && rune <= 0x9FFF) score += 3;
      if ((rune >= 0x20 && rune <= 0x7E) || rune == 0x0A || rune == 0x0D) {
        score += 1;
      }
      if (rune >= 0x3000 && rune <= 0x303F) score += 2;
      if (rune == 0x00C3 || rune == 0x00C2 || rune == 0x00E2) score -= 4;
    }
    score -= RegExp(r'[锟斤拷烫屯]{2,}').allMatches(text).length * 10;
    score -= RegExp(r'[ÃÂâ]{2,}').allMatches(text).length * 8;
    return score;
  }
}
