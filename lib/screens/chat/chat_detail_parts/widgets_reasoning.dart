// 顶层组件拆分（同库 part）
part of '../chat_detail_screen.dart';

class _ReasoningSection extends StatefulWidget {
  final String reasoning;

  const _ReasoningSection({required this.reasoning});

  @override
  State<_ReasoningSection> createState() => _ReasoningSectionState();
}


class _ReasoningSectionState extends State<_ReasoningSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(width: 2),
              Text(
                '思考过程',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              widget.reasoning,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.45),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        if (!_expanded) const SizedBox(height: 4),
      ],
    );
  }
}


class _WebSearchSection extends StatefulWidget {
  final Map<String, dynamic> trace;

  const _WebSearchSection({required this.trace});

  @override
  State<_WebSearchSection> createState() => _WebSearchSectionState();
}


class _WebSearchSectionState extends State<_WebSearchSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = widget.trace['query'] as String? ?? '';
    final rawResults = widget.trace['results'];
    final results = rawResults is List ? rawResults : const [];
    final summary = results.isEmpty
        ? '已搜索：$query，未获得可用结果'
        : '已搜索：$query，共${results.length} 个结果';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: colorScheme.primary.withOpacity(0.75),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.public_rounded,
                size: 14,
                color: colorScheme.primary.withOpacity(0.75),
              ),
              const SizedBox(width: 4),
              Text(
                '联网搜索',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary.withOpacity(0.78),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.55),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in results.take(5))
                  if (item is Map)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatSearchResult(item),
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.50),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        if (!_expanded) const SizedBox(height: 4),
      ],
    );
  }

  String _formatSearchResult(Map item) {
    final title = item['title']?.toString() ?? '无标题';
    final url = item['url']?.toString() ?? '';
    final snippet = item['snippet']?.toString() ?? '';
    final text = snippet.isEmpty ? title : '$title\n$snippet';
    return url.isEmpty ? text : '$text\n$url';
  }
}

// ─── 番外小剧场回看面板 ───
