import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solace/services/log_service.dart';

class LogViewerScreen extends StatefulWidget {
  final String? chatId;
  const LogViewerScreen({super.key, this.chatId});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  final LogService _log = LogService.instance;
  final Set<LogLevel> _visibleLevels = {LogLevel.info, LogLevel.warn, LogLevel.error};
  String? _moduleFilter;
  String _searchText = '';
  bool _autoScroll = true;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<LogEntry> _applyFilters(List<LogEntry> entries) {
    var result = entries;
    if (widget.chatId != null) {
      result = result.where((e) => e.chatId == widget.chatId).toList();
    }
    result = result.where((e) => _visibleLevels.contains(e.level)).toList();
    if (_moduleFilter != null) {
      result = result.where((e) => e.module == _moduleFilter).toList();
    }
    if (_searchText.isNotEmpty) {
      final q = _searchText.toLowerCase();
      result = result.where((e) => e.message.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color _levelColor(LogLevel level, ColorScheme cs) {
    switch (level) {
      case LogLevel.debug:
        return cs.onSurface.withOpacity(0.5);
      case LogLevel.info:
        return cs.onSurface;
      case LogLevel.warn:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatId != null ? '聊天日志' : '全局日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制日志',
            onPressed: () {
              final all = _log.getAll();
              final filtered = _applyFilters(all);
              final text = filtered.map((e) => e.toFormattedString()).join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: () {
              _log.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清空')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(cs),
          Expanded(child: _buildLogList(cs)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme cs) {
    final moduleChips = ['Bloc', 'Storage', 'Transfer', 'AI', 'UI', 'System'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: '搜索日志...',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            style: TextStyle(fontSize: 13, color: cs.onSurface),
            onChanged: (v) => setState(() => _searchText = v),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _levelFilterChip(LogLevel.info, 'INFO', Colors.green, cs),
                _levelFilterChip(LogLevel.warn, 'WARN', Colors.orange, cs),
                _levelFilterChip(LogLevel.error, 'ERROR', Colors.red, cs),
                const VerticalDivider(width: 8),
                for (final m in moduleChips) _moduleChip(m, cs),
                if (widget.chatId != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ActionChip(
                      label: Text('${widget.chatId!.length > 8 ? widget.chatId!.substring(0, 8) : widget.chatId}',
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      onPressed: null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelFilterChip(LogLevel level, String label, Color color, ColorScheme cs) {
    final selected = _visibleLevels.contains(level);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : color)),
        selected: selected,
        onSelected: (v) {
          setState(() {
            if (v) { _visibleLevels.add(level); }
            else { _visibleLevels.remove(level); }
          });
        },
        visualDensity: VisualDensity.compact,
        selectedColor: color.withOpacity(0.7),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _moduleChip(String module, ColorScheme cs) {
    final selected = _moduleFilter == module;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FilterChip(
        label: Text(module, style: TextStyle(fontSize: 11, color: selected ? Colors.white : cs.onSurface)),
        selected: selected,
        onSelected: (v) => setState(() => _moduleFilter = v ? module : null),
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primary,
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _buildLogList(ColorScheme cs) {
    return StreamBuilder<List<LogEntry>>(
      stream: _log.stream,
      builder: (context, snapshot) {
        final entries = _applyFilters(snapshot.data ?? _log.getAll());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_autoScroll && _scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
        if (entries.isEmpty) {
          return Center(
            child: Text('暂无日志', style: TextStyle(color: cs.onSurface.withOpacity(0.4))),
          );
        }
        return ListView.builder(
          controller: _scrollController,
          itemCount: entries.length + 1,
          itemBuilder: (context, index) {
            if (index == entries.length) {
              return const SizedBox(height: 4);
            }
            final entry = entries[index];
            final color = _levelColor(entry.level, cs);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              child: InkWell(
                onTap: () => Clipboard.setData(ClipboardData(text: entry.toFormattedString())),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        logLevelNames[entry.level]!.padRight(5),
                        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        entry.module,
                        style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.message,
                        style: TextStyle(fontSize: 11, color: color, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
