import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/pure_ai/pure_ai_chat_bloc.dart';
import '../../blocs/pure_ai/pure_ai_chat_event.dart';
import '../../blocs/pure_ai/pure_ai_chat_state.dart';
import '../../models/pure_ai_session.dart';
import '../../models/pure_ai_message.dart';
import '../../models/chat_message.dart';
import '../../widgets/typing_indicator.dart';
import '../../utils/message_sanitizer.dart';

class PureAIChatScreen extends StatefulWidget {
  const PureAIChatScreen({super.key});

  @override
  State<PureAIChatScreen> createState() => _PureAIChatScreenState();
}

class _PureAIChatScreenState extends State<PureAIChatScreen> {
  PureAISession? _selectedSession;

  @override
  Widget build(BuildContext context) {
    if (_selectedSession != null) {
      return _ChatDetailView(
        session: _selectedSession!,
        onBack: () => setState(() => _selectedSession = null),
      );
    }
    return _SessionListView(
      onSessionSelected: (session) =>
          setState(() => _selectedSession = session),
    );
  }
}

// ==================== 会话列表 ====================

class _SessionListView extends StatelessWidget {
  final void Function(PureAISession) onSessionSelected;

  const _SessionListView({required this.onSessionSelected});

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Hero(
          tag: 'app_icon_ai_assistant',
          child: Text('AI助手'),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              context.read<PureAIChatBloc>().add(
                    PureAICreateSession(userId),
                  );
            },
          ),
        ],
      ),
      body: BlocBuilder<PureAIChatBloc, PureAIChatState>(
        builder: (context, state) {
          if (state is PureAISessionsLoaded) {
            final sessions = state.sessions;
            if (sessions.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text(
                      '点击右上角 + 开始对话',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5)),
                    ),
                  ],
                ),
              );
            }
            return ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return Dismissible(
                  key: Key(session.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    context
                        .read<PureAIChatBloc>()
                        .add(PureAIDeleteSession(session.id));
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child:
                          const Icon(Icons.auto_awesome, color: Colors.white),
                    ),
                    title: Text(session.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      session.lastMessage ?? '新对话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5)),
                    ),
                    trailing: Text(
                      session.lastMessageTime != null
                          ? _formatTime(session.lastMessageTime!)
                          : _formatTime(session.createdAt),
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4)),
                    ),
                    onTap: () {
                      context
                          .read<PureAIChatBloc>()
                          .add(PureAILoadMessages(session.id));
                      onSessionSelected(session);
                    },
                  ),
                );
              },
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inDays > 0) return DateFormat('MM/dd').format(time);
    if (diff.inHours > 0) return '${diff.inHours}小时前';
    if (diff.inMinutes > 0) return '${diff.inMinutes}分钟前';
    return '刚刚';
  }
}

// ==================== 聊天详情 ====================

class _ChatDetailView extends StatefulWidget {
  final PureAISession session;
  final VoidCallback onBack;

  const _ChatDetailView({required this.session, required this.onBack});

  @override
  State<_ChatDetailView> createState() => _ChatDetailViewState();
}

class _ChatDetailViewState extends State<_ChatDetailView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _webSearchEnabled = false;

  @override
  void initState() {
    super.initState();
    context.read<PureAIChatBloc>().add(PureAILoadMessages(widget.session.id));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    context.read<PureAIChatBloc>().add(PureAISendMessage(
          sessionId: widget.session.id,
          userId: userId,
          content: text,
          enableWebSearch: _webSearchEnabled,
        ));

    _controller.clear();
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(widget.session.title),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: BlocConsumer<PureAIChatBloc, PureAIChatState>(
              listener: (context, state) {
                if (state is PureAIMessagesLoaded) {
                  _scrollToBottom();
                }
                if (state is PureAIStreaming) {
                  _scrollToBottom();
                }
              },
              builder: (context, state) {
                List<PureAIMessage> messages = [];
                bool isSending = false;
                bool isStreaming = false;
                String streamingText = '';
                String streamingReasoning = '';

                if (state is PureAIMessagesLoaded) {
                  messages = state.messages;
                } else if (state is PureAIMessageSending) {
                  messages = state.messages;
                  isSending = true;
                } else if (state is PureAIStreaming) {
                  messages = state.messages;
                  isStreaming = true;
                  streamingText = state.streamingText;
                  streamingReasoning = state.reasoning;
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      '开始对话吧',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4)),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount:
                      messages.length + (isSending || isStreaming ? 1 : 0),
                  itemBuilder: (context, index) {
                    // 流式输出气泡
                    if (isStreaming && index == messages.length) {
                      if (streamingText.isEmpty) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const TypingIndicator(),
                          ),
                        );
                      }
                      return _buildStreamingBubble(streamingText,
                          reasoning: streamingReasoning);
                    }

                    if (index == messages.length && isSending) {
                      // AI正在回复指示器
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const TypingIndicator(),
                        ),
                      );
                    }

                    final msg = messages[index];
                    return _buildMessageBubble(msg);
                  },
                );
              },
            ),
          ),
          // 输入栏
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildStreamingBubble(String text, {String reasoning = ''}) {
    final colorScheme = Theme.of(context).colorScheme;
    // UI 兜底清洗
    final cleanText = MessageSanitizer.sanitizeStream(text);
    final cleanReasoning =
        reasoning.isNotEmpty ? MessageSanitizer.sanitizeStream(reasoning) : '';
    final hasReasoning = cleanReasoning.isNotEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasReasoning)
              Text(
                cleanReasoning,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.4),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            if (hasReasoning) const SizedBox(height: 6),
            if (cleanText.isNotEmpty)
              SelectableText(
                cleanText,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 15,
                ),
              ),
            if (!hasReasoning && text.isEmpty) const TypingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(PureAIMessage msg) {
    final isAI = msg.isFromAI;
    final webSearchTrace = msg.metadata?['webSearchTrace'];

    if (msg.type == MessageType.image) {
      return Align(
        alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(msg.content),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 48),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isAI
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAI && webSearchTrace is Map<String, dynamic>)
              _WebSearchSection(trace: webSearchTrace),
            SelectableText(
              msg.content,
              style: TextStyle(
                color: isAI
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onPrimary,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color:
                Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWebSearchToggle(Theme.of(context).colorScheme),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.send,
                    color: Theme.of(context).colorScheme.primary),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebSearchToggle(ColorScheme colorScheme) {
    final enabled = _webSearchEnabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = enabled
        ? colorScheme.primary
        : (isDark ? const Color(0xFF1F1F1F) : Colors.white);
    final fgColor = enabled
        ? Colors.white
        : (isDark
            ? Colors.white.withOpacity(0.72)
            : Colors.black.withOpacity(0.62));
    final borderColor = enabled
        ? colorScheme.primary
        : (isDark
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.10));

    return GestureDetector(
      onTap: () => setState(() => _webSearchEnabled = !_webSearchEnabled),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.24),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_rounded, size: 15, color: fgColor),
            const SizedBox(width: 6),
            Text(
              '联网搜索',
              style: TextStyle(
                color: fgColor,
                fontSize: 13,
                fontWeight: enabled ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
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
        : '已搜索：$query，${results.length} 个结果';

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
