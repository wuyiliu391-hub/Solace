import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/bing_search_result.dart';
import '../utils/response_decoder.dart';

class BingCnMcpService {
  static const serverName = 'bing-cn-mcp';

  const BingCnMcpService();

  bool shouldSearch(String userMessage) {
    final text = userMessage.trim().toLowerCase();
    if (text.isEmpty) return false;

    final directIntent = RegExp(
      r'(联网|上网|搜索|搜一下|查一下|查查|帮我查|帮忙查|必应|bing)',
      caseSensitive: false,
    );
    if (directIntent.hasMatch(text)) return true;

    if (RegExp(r'(最新|新闻|热搜|实时)', caseSensitive: false).hasMatch(text)) {
      return true;
    }

    final recentInfoIntent = RegExp(
      r'(近期|最近).{0,16}(情况|消息|资料|进展|价格|天气|政策|新闻|热搜|发生|怎么样|是什么)',
      caseSensitive: false,
    );
    return recentInfoIntent.hasMatch(text);
  }

  String buildQuery(String userMessage, {DateTime? now}) {
    final current = now ?? DateTime.now();
    var query = userMessage
        .replaceAll(
          RegExp(
            r'(请你|麻烦你|帮我|帮忙|用|给我|一下|联网|上网|搜索|搜|查查|查一下|必应|Bing|bing)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[？?！!，,。；;：:]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    query = _replaceRelativeDates(query, current);
    query = _trimCasualWords(query);

    if (_isFreshnessQuery(userMessage)) {
      query = _appendUniqueTerms(query, const ['最新', '新闻']);
    }

    if (_hasAsciiBrand(query)) {
      query = _appendUniqueTerms(query, const ['official', 'news']);
    }

    return query.isEmpty ? userMessage.trim() : query;
  }

  Future<List<BingSearchResult>> search(
    String userMessage, {
    int maxResults = 5,
    http.Client? client,
  }) async {
    final query = buildQuery(userMessage);
    if (query.isEmpty) return const [];

    final uri = Uri.https('cn.bing.com', '/search', {
      'q': query,
      'mkt': 'zh-CN',
      'setlang': 'zh-CN',
      'cc': 'CN',
    });

    debugPrint('[BingSearch] 开始搜索: query="$query"');
    debugPrint('[BingSearch] URL: $uri');

    try {
      // 使用 dart:io HttpClient，自动处理 gzip 解压
      final ioClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..autoUncompress = true;
      final request = await ioClient.getUrl(uri);
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/125.0 Safari/537.36');
      request.headers.set('Accept',
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      request.headers.set('Accept-Language', 'zh-CN,zh;q=0.9,en;q=0.6');
      request.headers.set('Accept-Encoding', 'gzip, deflate');

      final response = await request.close().timeout(
            const Duration(seconds: 15),
          );

      debugPrint('[BingSearch] 响应状态: ${response.statusCode}');
      debugPrint(
          '[BingSearch] Content-Encoding: ${response.headers.value('content-encoding')}');
      debugPrint(
          '[BingSearch] Content-Type: ${response.headers.value('content-type')}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[BingSearch] HTTP 错误: ${response.statusCode}');
        ioClient.close();
        return const [];
      }

      final bytes = await response.fold<List<int>>(
        <int>[],
        (prev, chunk) => [...prev, ...chunk],
      );
      ioClient.close();

      debugPrint('[BingSearch] 响应字节数: ${bytes.length}');

      final html = await ResponseDecoder.decode(
        response.headers.value('content-type'),
        bytes,
      );

      debugPrint('[BingSearch] HTML 长度: ${html.length}');
      if (html.length < 200) {
        debugPrint('[BingSearch] HTML 内容过短，可能被反爬: $html');
      }

      final parsed = parseSearchResults(html, maxResults: maxResults * 3);
      debugPrint('[BingSearch] 解析到 ${parsed.length} 条结果');

      final ranked = rankResults(query, parsed);
      final freshness = _isFreshnessQuery(query);
      final qualityResults = freshness
          ? ranked
              .where((result) =>
                  _scoreResult(query, result, freshness: freshness) >= 3)
              .toList()
          : ranked;
      final finalResults = qualityResults.take(maxResults).toList();
      debugPrint('[BingSearch] 最终返回 ${finalResults.length} 条结果');
      return finalResults;
    } catch (e, stackTrace) {
      debugPrint('[BingSearch] 搜索异常: $e');
      debugPrint('[BingSearch] 堆栈: $stackTrace');
      return const [];
    }
  }

  List<BingSearchResult> parseSearchResults(
    String html, {
    int maxResults = 5,
  }) {
    if (html.isEmpty || maxResults <= 0) return const [];

    final results = <BingSearchResult>[];
    final blocks = RegExp(
      r'<li[^>]+class="[^"]*\bb_algo\b[^"]*"[^>]*>([\s\S]*?)</li>',
      caseSensitive: false,
    ).allMatches(html);

    for (final blockMatch in blocks) {
      final block = blockMatch.group(1) ?? '';
      final linkMatch = RegExp(
        r'<h2[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      ).firstMatch(block);
      if (linkMatch == null) continue;

      final url = _decodeHtml(linkMatch.group(1) ?? '').trim();
      final title = _cleanHtml(linkMatch.group(2) ?? '');
      final snippet = _cleanHtml(
        RegExp(r'<p[^>]*>([\s\S]*?)</p>', caseSensitive: false)
                .firstMatch(block)
                ?.group(1) ??
            '',
      );
      final displayUrl = _cleanHtml(
        RegExp(
              r'<cite[^>]*>([\s\S]*?)</cite>',
              caseSensitive: false,
            ).firstMatch(block)?.group(1) ??
            '',
      );

      if (title.isEmpty || url.isEmpty || url.startsWith('javascript:')) {
        continue;
      }

      results.add(BingSearchResult(
        title: title,
        url: url,
        snippet: snippet,
        displayUrl: displayUrl,
      ));

      if (results.length >= maxResults) break;
    }

    return results;
  }

  List<BingSearchResult> rankResults(
    String query,
    List<BingSearchResult> results,
  ) {
    final freshness = _isFreshnessQuery(query);
    final scored = results
        .map((result) => _ScoredSearchResult(
              result: result,
              score: _scoreResult(query, result, freshness: freshness),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((item) => item.result).toList();
  }

  List<Map<String, String>> buildSearchContext(
    String userMessage,
    List<BingSearchResult> results,
  ) {
    final query = buildQuery(userMessage);
    final buffer = StringBuffer()
      ..writeln('【联网搜索结果 — 最高优先级指令】')
      ..writeln()
      ..writeln('[WARN] 用户刚刚开启了联网搜索，提出了一个需要实时信息的问题。')
      ..writeln('[WARN] 你现在必须切换为"信息助手"模式：直接、准确地回答用户的问题。')
      ..writeln()
      ..writeln('【必须遵守的规则】')
      ..writeln('1. 必须依据下方搜索结果回答，不要编造或猜测')
      ..writeln('2. 用简洁清晰的中文直接回答问题，先给出核心答案')
      ..writeln('3. 可以在回答末尾简要提到信息来源')
      ..writeln('4. 如果搜索结果不足以回答，明确说"搜索结果中没有找到相关信息"')
      ..writeln('5. 不要把搜索结果当成"别人说的话"来角色扮演')
      ..writeln('6. 不要用角色口吻包装搜索结果，直接用信息助手的语气回答')
      ..writeln()
      ..writeln('用户问题：$userMessage')
      ..writeln('搜索关键词：$query')
      ..writeln()
      ..writeln(results.isEmpty
          ? '搜索状态：本次已经执行联网搜索，但没有解析到可用结果。请直接告诉用户"搜索结果中没有找到相关信息"，不要继续角色扮演，也不要假装知道答案。'
          : '以下是搜索结果：');

    for (var i = 0; i < results.length; i++) {
      final item = results[i];
      buffer
        ..writeln()
        ..writeln('${i + 1}. ${item.title}')
        ..writeln('摘要：${item.snippet.isEmpty ? '无摘要' : item.snippet}')
        ..writeln('链接：${item.url}');
    }

    return [
      {
        'role': 'system',
        'content': buffer.toString().trim(),
      },
    ];
  }

  Map<String, dynamic> buildSearchTrace(
    String userMessage,
    List<BingSearchResult> results,
  ) {
    return {
      'server': serverName,
      'query': buildQuery(userMessage),
      'searchedAt': DateTime.now().toIso8601String(),
      'results': results
          .map((result) => {
                'title': result.title,
                'url': result.url,
                'snippet': result.snippet,
                'displayUrl': result.displayUrl,
              })
          .toList(),
    };
  }

  int _scoreResult(
    String query,
    BingSearchResult result, {
    required bool freshness,
  }) {
    final haystack =
        '${result.title} ${result.snippet} ${result.url} ${result.displayUrl}'
            .toLowerCase();
    var score = 0;

    for (final token in _queryTokens(query)) {
      if (haystack.contains(token.toLowerCase())) score += 2;
    }

    if (RegExp(r'(新闻|最新|发布|公告|更新|news|release|announc)', caseSensitive: false)
        .hasMatch(haystack)) {
      score += freshness ? 5 : 2;
    }
    if (RegExp(r'(官方|official|openai\.com|microsoft\.com|google\.com)',
            caseSensitive: false)
        .hasMatch(haystack)) {
      score += 4;
    }
    if (RegExp(r'(reuters|apnews|bloomberg|theverge|techcrunch|36kr|财联社)',
            caseSensitive: false)
        .hasMatch(haystack)) {
      score += 3;
    }
    if (RegExp(r'(202[0-9]|今天|昨日|昨天|小时前|分钟前|刚刚|june|may|april)',
            caseSensitive: false)
        .hasMatch(haystack)) {
      score += freshness ? 4 : 1;
    }
    if (freshness &&
        RegExp(r'(百科|baike|zhidao|教程|指南|入口|登录|下载)', caseSensitive: false)
            .hasMatch(haystack)) {
      score -= 6;
    }

    return score;
  }

  Iterable<String> _queryTokens(String query) {
    return query
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2)
        .take(12);
  }

  bool _isFreshnessQuery(String text) {
    return RegExp(
      r'(今天|今日|昨天|昨日|明天|最新|新闻|热搜|实时|近期|最近|发生|进展|发布|公告|更新|干了啥|做了啥)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _hasAsciiBrand(String query) {
    return RegExp(r'\b[A-Za-z][A-Za-z0-9._-]{2,}\b').hasMatch(query);
  }

  String _replaceRelativeDates(String query, DateTime now) {
    final today = _formatDate(now);
    final yesterday = _formatDate(now.subtract(const Duration(days: 1)));
    final tomorrow = _formatDate(now.add(const Duration(days: 1)));
    return query
        .replaceAll(RegExp(r'(今天|今日)'), today)
        .replaceAll(RegExp(r'(昨天|昨日)'), yesterday)
        .replaceAll(RegExp(r'明天'), tomorrow);
  }

  String _trimCasualWords(String query) {
    return query
        .replaceAll(RegExp(r'(干了啥|做了啥|发生了什么|有什么|是啥|是什么)'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _appendUniqueTerms(String query, List<String> terms) {
    var result = query;
    for (final term in terms) {
      if (!result.toLowerCase().contains(term.toLowerCase())) {
        result = '$result $term'.trim();
      }
    }
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  String _cleanHtml(String html) {
    final withoutTags = html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    return _decodeHtml(withoutTags).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _decodeHtml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final codePoint = int.tryParse(match.group(1) ?? '');
      if (codePoint == null) return match.group(0) ?? '';
      return String.fromCharCode(codePoint);
    }).replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final codePoint = int.tryParse(match.group(1) ?? '', radix: 16);
      if (codePoint == null) return match.group(0) ?? '';
      return String.fromCharCode(codePoint);
    });
  }
}

class _ScoredSearchResult {
  final BingSearchResult result;
  final int score;

  const _ScoredSearchResult({
    required this.result,
    required this.score,
  });
}
