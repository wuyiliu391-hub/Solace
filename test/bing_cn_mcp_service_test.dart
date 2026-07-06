import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/bing_search_result.dart';
import 'package:solace/services/bing_cn_mcp_service.dart';

void main() {
  group('BingCnMcpService', () {
    const service = BingCnMcpService();

    test('只在明确联网或时效需求时触发搜索', () {
      expect(service.shouldSearch('帮我联网查一下今天的新闻'), isTrue);
      expect(service.shouldSearch('Bing 搜索 Flutter 最新版本'), isTrue);
      expect(service.shouldSearch('最近这个政策有什么进展'), isTrue);
      expect(service.shouldSearch('你今天开心吗'), isFalse);
      expect(service.shouldSearch('最近好吗'), isFalse);
      expect(service.shouldSearch('陪我聊聊天'), isFalse);
    });

    test('优化口语查询词并补充时效关键词', () {
      final query = service.buildQuery(
        '搜索一下今天 OpenAI 干了啥',
        now: DateTime(2026, 6, 5),
      );

      expect(query, contains('2026年6月5日'));
      expect(query, contains('OpenAI'));
      expect(query, contains('最新'));
      expect(query, contains('新闻'));
      expect(query, contains('official'));
      expect(query, contains('news'));
      expect(query, isNot(contains('搜索')));
      expect(query, isNot(contains('干了啥')));
    });

    test('解析 Bing 搜索结果 HTML', () {
      const html = '''
<ol id="b_results">
  <li class="b_algo">
    <h2><a href="https://example.com/a?x=1&amp;y=2">示例 &amp; 标题</a></h2>
    <div class="b_caption">
      <p>这是 <strong>第一条</strong> 搜索摘要。</p>
      <cite>example.com/a</cite>
    </div>
  </li>
  <li class="b_algo">
    <h2><a href="https://example.com/b">第二条结果</a></h2>
    <p>第二条摘要&#12290;</p>
  </li>
</ol>
''';

      final results = service.parseSearchResults(html, maxResults: 2);

      expect(results, hasLength(2));
      expect(results.first.title, '示例 & 标题');
      expect(results.first.url, 'https://example.com/a?x=1&y=2');
      expect(results.first.snippet, '这是 第一条 搜索摘要。');
      expect(results.first.displayUrl, 'example.com/a');
      expect(results[1].snippet, '第二条摘要。');
    });

    test('时效查询优先官方和新闻结果，降低百科教程类结果', () {
      final ranked = service.rankResults('OpenAI 2026年6月5日 最新 新闻', const [
        BingSearchResult(
          title: 'OpenAI 官网入口地址：如何轻松找到',
          url: 'https://apifox.com/apiskills/openai-official-portal/',
          snippet: 'OpenAI 教程和入口指南。',
        ),
        BingSearchResult(
          title: 'OpenAI announces new ChatGPT update',
          url: 'https://openai.com/news/example',
          snippet: 'June 5, 2026 release notes and official news.',
        ),
        BingSearchResult(
          title: 'Reuters: OpenAI latest policy news',
          url: 'https://www.reuters.com/technology/openai-example',
          snippet: 'OpenAI news reported today.',
        ),
      ]);

      expect(ranked.first.url, 'https://openai.com/news/example');
      expect(ranked.last.url, contains('apifox.com'));
    });

    test('构建可注入 LLM 的搜索上下文', () {
      final context = service.buildSearchContext(
        '查一下 Flutter 最新消息',
        service.parseSearchResults('''
<li class="b_algo">
  <h2><a href="https://flutter.dev">Flutter</a></h2>
  <p>Flutter 官方网站。</p>
</li>
'''),
      );

      expect(context, hasLength(1));
      expect(context.first['role'], 'system');
      expect(context.first['content'], contains('联网搜索结果'));
      expect(context.first['content'], contains('https://flutter.dev'));
      expect(context.first['content'], contains('用简洁清晰的中文直接回答'));
    });

    test('构建可保存到消息 metadata 的搜索过程', () {
      final results = service.parseSearchResults('''
<li class="b_algo">
  <h2><a href="https://openai.com/news">OpenAI News</a></h2>
  <p>OpenAI 官方新闻。</p>
</li>
''');

      final trace = service.buildSearchTrace('搜索一下 OpenAI 今天消息', results);

      expect(trace['server'], 'bing-cn-mcp');
      expect(trace['query'], contains('OpenAI'));
      expect(trace['searchedAt'], isA<String>());
      expect(trace['results'], isA<List>());
      expect(
          (trace['results'] as List).first['url'], 'https://openai.com/news');
    });
  });
}
