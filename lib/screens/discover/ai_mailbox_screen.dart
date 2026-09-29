import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/ai_letter.dart';
import '../../models/chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_letter_prompt_builder.dart';
import '../../services/ai_service.dart';
import '../../utils/message_sanitizer.dart';

class AIMailboxScreen extends StatefulWidget {
  const AIMailboxScreen({super.key});

  @override
  State<AIMailboxScreen> createState() => _AIMailboxScreenState();
}

class _AIMailboxScreenState extends State<AIMailboxScreen> {
  var _letters = <AILetter>[];
  var _loading = true;
  var _loadingMore = false;
  var _generating = false;
  static const int _pageSize = 30;
  var _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadLetters().then((_) => _processPendingReplies());
  }

  String? get _userId {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  String get _recipientName {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.user.nickname : '你';
  }

  Future<void> _loadLetters() async {
    final userId = _userId;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final storage = context.read<LocalStorageRepository>();
    final letters = await storage.getAILetters(
      userId: userId,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _letters = letters;
      _loading = false;
      _hasMore = letters.length >= _pageSize;
    });
  }

  Future<void> _loadMoreLetters() async {
    if (!_hasMore || _loadingMore) return;
    final userId = _userId;
    if (userId == null) return;

    setState(() => _loadingMore = true);
    final storage = context.read<LocalStorageRepository>();
    final more = await storage.getAILetters(
      userId: userId,
      limit: _pageSize,
      offset: _letters.length,
    );
    if (!mounted) return;
    setState(() {
      _letters.addAll(more);
      _loadingMore = false;
      _hasMore = more.length >= _pageSize;
    });
  }

  Future<void> _selectCharacterAndGenerate() async {
    if (_generating) return;
    final userId = _userId;
    if (userId == null) return;

    final storage = context.read<LocalStorageRepository>();
    final characters = await storage.getAllAICharacters();
    if (!mounted) return;
    final visibleCharacters = characters.where((c) => !c.isHidden).toList();

    if (visibleCharacters.isEmpty) {
      _showSnack('请先创建一个 AI 角色');
      return;
    }

    // 只有一个角色时直接生成
    if (visibleCharacters.length == 1) {
      await _generateLetter(visibleCharacters.first);
      return;
    }

    // 多个角色时弹出选择器
    final cs = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<AICharacter>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                '选择谁给你写信',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: visibleCharacters.length,
                itemBuilder: (context, index) {
                  final c = visibleCharacters[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: cs.primary.withOpacity(0.12),
                                child: c.avatarUrl != null &&
                                        c.avatarUrl!.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          c.avatarUrl!,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(
                                              Icons.person,
                                              color: cs.primary),
                                        ),
                                      )
                                    : Icon(Icons.person, color: cs.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    if (c.personality.isNotEmpty)
                                      Text(
                                        c.personality,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  size: 16, color: cs.outlineVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      await _generateLetter(selected);
    }
  }

  Future<void> _generateLetter(AICharacter character) async {
    if (_generating) return;
    final userId = _userId;
    if (userId == null) return;

    setState(() => _generating = true);
    // 让 UI 先刷新到"正在写信..."状态，避免卡顿感
    await Future.delayed(Duration.zero);
    try {
      final storage = context.read<LocalStorageRepository>();

      final config = await storage.getActiveAIConfig();
      if (config == null || config.apiKey.trim().isEmpty) {
        _showSnack('请先配置可用的 AI 模型');
        return;
      }

      final chatHistory = await _loadRecentChatHistory(storage, character);
      final memories = await storage.getMemories(
        characterId: character.id,
        userId: userId,
        limit: 30,
      );
      final prompt = AILetterPromptBuilder.buildIncomingLetterPrompt(
        character: character,
        recipientName: _recipientName,
        memories: memories,
        chatHistory: chatHistory,
      );
      final content = MessageSanitizer.sanitizeForContent(
        await AIService(storage).sendMessage(
          character: character,
          userId: userId,
          userMessage: prompt,
          chatHistory: chatHistory,
          memories: memories,
          intimacyLevel: _sourceIntimacyLevel,
          overrideMaxTokens: 8192, // 写信不限制长度，给足 token
        ),
      );

      if (content.trim().isEmpty) {
        _showSnack('来信生成失败，请稍后重试');
        return;
      }

      final now = DateTime.now();
      final letter = AILetter(
        id: 'letter_${now.millisecondsSinceEpoch}',
        userId: userId,
        characterId: character.id,
        characterName: character.name,
        characterAvatar: character.avatarUrl,
        recipientName: _recipientName,
        title: '给$_recipientName的一封信',
        content: content,
        sourceChatId: _sourceChatId,
        createdAt: now,
      );
      await storage.saveAILetter(letter);
      await _loadLetters();
      _showSnack('收到一封新的来信');
    } catch (e) {
      _showSnack('来信生成失败：$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  String? _sourceChatId;
  var _sourceIntimacyLevel = 0;

  Future<List<ChatMessage>> _loadRecentChatHistory(
    LocalStorageRepository storage,
    AICharacter character,
  ) async {
    _sourceChatId = null;
    _sourceIntimacyLevel = 0;
    final sessions = await storage.getChatSessionsByCharacterId(character.id);
    if (sessions.isEmpty) return [];

    final sorted = List.of(sessions)
      ..sort((a, b) {
        final at = a.lastMessageTime ?? a.updatedAt ?? a.createdAt;
        final bt = b.lastMessageTime ?? b.updatedAt ?? b.createdAt;
        return bt.compareTo(at);
      });
    final session = sorted.first;
    _sourceChatId = session.id;
    _sourceIntimacyLevel = session.intimacyLevel;

    return storage.getChatMessages(session.id, limit: 20);
  }

  Future<void> _showDeleteDialog(AILetter letter) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '删除来信',
          style: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text('确定要删除 ${letter.characterName} 的来信吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: cs.primary),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final storage = context.read<LocalStorageRepository>();
      await storage.deleteAILetter(letter.id);
      await _loadLetters();
      _showSnack('已删除');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static const int _maxLetterLength = 800;

  Future<void> _showWriteLetterSheet() async {
    final userId = _userId;
    if (userId == null) return;

    final storage = context.read<LocalStorageRepository>();
    final characters = await storage.getAllAICharacters();
    final visibleCharacters = characters.where((c) => !c.isHidden).toList();

    if (visibleCharacters.isEmpty) {
      _showSnack('请先创建一个 AI 角色');
      return;
    }

    // 选择收信角色
    AICharacter? targetCharacter;
    if (visibleCharacters.length == 1) {
      targetCharacter = visibleCharacters.first;
    } else {
      targetCharacter = await _pickCharacter(visibleCharacters);
    }
    if (targetCharacter == null || !mounted) return;

    // 弹出写信面板
    final cs = Theme.of(context).colorScheme;
    final titleController =
        TextEditingController(text: '给${targetCharacter.name}的一封信');
    final contentController = TextEditingController();
    final titleFocus = FocusNode();
    final contentFocus = FocusNode();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottom = MediaQuery.of(ctx).viewInsets.bottom;
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 拖拽条
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: cs.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '写给 ${targetCharacter!.name}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          final content = contentController.text.trim();
                          if (content.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('请输入信件内容')),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          await _saveUserLetter(
                            character: targetCharacter!,
                            title: title.isEmpty
                                ? '给${targetCharacter.name}的一封信'
                                : title,
                            content: content,
                          );
                        },
                        child: Text('寄出',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            )),
                      ),
                    ],
                  ),
                ),
                Divider(height: 0.5, color: cs.outlineVariant),
                // 信件标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: TextField(
                    controller: titleController,
                    focusNode: titleFocus,
                    style: TextStyle(fontSize: 16, color: cs.onSurface),
                    decoration: InputDecoration(
                      hintText: '信件标题（可选）',
                      hintStyle: TextStyle(color: cs.onSurfaceVariant),
                      border: InputBorder.none,
                    ),
                    maxLength: 40,
                    buildCounter: (_,
                            {required currentLength,
                            required isFocused,
                            required maxLength}) =>
                        const SizedBox(),
                  ),
                ),
                Divider(
                    height: 0.5,
                    color: cs.outlineVariant,
                    indent: 20,
                    endIndent: 20),
                // 信件正文
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: TextField(
                      controller: contentController,
                      focusNode: contentFocus,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                          fontSize: 16, height: 1.7, color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: '写下你想说的话...',
                        hintStyle: TextStyle(
                            color: cs.onSurfaceVariant.withOpacity(0.6)),
                        border: InputBorder.none,
                      ),
                      maxLength: _maxLetterLength,
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              required maxLength}) =>
                          Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '$currentLength / $maxLength',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                maxLength != null && currentLength > maxLength
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                ),
                SizedBox(height: bottom > 0 ? bottom : 16),
              ],
            ),
          );
        },
      ),
    );

    titleController.dispose();
    contentController.dispose();
    titleFocus.dispose();
    contentFocus.dispose();
  }

  Future<AICharacter?> _pickCharacter(List<AICharacter> characters) async {
    final cs = Theme.of(context).colorScheme;
    return showModalBottomSheet<AICharacter>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                '选择收信人',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: characters.length,
                itemBuilder: (context, index) {
                  final c = characters[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: cs.primary.withOpacity(0.12),
                                child: c.avatarUrl != null &&
                                        c.avatarUrl!.isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          c.avatarUrl!,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Icon(
                                              Icons.person,
                                              color: cs.primary),
                                        ),
                                      )
                                    : Icon(Icons.person, color: cs.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  size: 16, color: cs.outlineVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveUserLetter({
    required AICharacter character,
    required String title,
    required String content,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final storage = context.read<LocalStorageRepository>();
      final now = DateTime.now();
      final letter = AILetter(
        id: 'letter_${now.millisecondsSinceEpoch}',
        userId: userId,
        characterId: character.id,
        characterName: character.name,
        characterAvatar: character.avatarUrl,
        recipientName: character.name,
        title: title,
        content: content,
        isFromUser: true,
        needsReply: true,
        createdAt: now,
      );
      await storage.saveAILetter(letter);
      await _loadLetters();
      _showSnack('信已寄出，下次打开信箱时会收到回信');
    } catch (e) {
      _showSnack('寄信失败：$e');
    }
  }

  Future<void> _processPendingReplies() async {
    final userId = _userId;
    if (userId == null) return;

    final storage = context.read<LocalStorageRepository>();
    final pending = await storage.getPendingReplyLetters(userId);
    if (pending.isEmpty) return;

    // 逐封处理待回信
    for (final userLetter in pending) {
      if (!mounted) return;

      final character = await storage.getAICharacter(userLetter.characterId);
      if (character == null) {
        await storage.markAILetterReplied(userLetter.id);
        continue;
      }

      final config = await storage.getActiveAIConfig();
      if (config == null || config.apiKey.trim().isEmpty) continue;

      try {
        final chatHistory = await _loadRecentChatHistory(storage, character);
        final memories = await storage.getMemories(
          characterId: character.id,
          userId: userId,
          limit: 30,
        );

        final prompt = AILetterPromptBuilder.buildReplyPrompt(
          character: character,
          senderName: _recipientName,
          userLetterTitle: userLetter.title,
          userLetterContent: userLetter.content,
          memories: memories,
          chatHistory: chatHistory,
        );

        final content = MessageSanitizer.sanitizeForContent(
          await AIService(storage).sendMessage(
            character: character,
            userId: userId,
            userMessage: prompt,
            chatHistory: chatHistory,
            memories: memories,
            intimacyLevel: _sourceIntimacyLevel,
          ),
        );

        if (content.trim().isEmpty) {
          await storage.markAILetterReplied(userLetter.id);
          continue;
        }

        final now = DateTime.now();
        final replyLetter = AILetter(
          id: 'letter_${now.millisecondsSinceEpoch}',
          userId: userId,
          characterId: character.id,
          characterName: character.name,
          characterAvatar: character.avatarUrl,
          recipientName: _recipientName,
          title: '想对你说的话',
          content: content,
          sourceChatId: _sourceChatId,
          createdAt: now,
        );
        await storage.saveAILetter(replyLetter);
        await storage.markAILetterReplied(userLetter.id);
      } catch (_) {
        // 失败时跳过，下次再试
        continue;
      }
    }

    // 全部处理完后刷新列表
    if (mounted) await _loadLetters();
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.year}/${time.month}/${time.day}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('信箱'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '写一封信给 TA',
            onPressed: _showWriteLetterSheet,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '让 TA 写一封信',
            onPressed: _generating ? null : _selectCharacterAndGenerate,
            icon: _generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_unread_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _letters.isEmpty
              ? _emptyState(cs)
              : RefreshIndicator(
                  onRefresh: _loadLetters,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: _letters.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == _letters.length) {
                        // 加载更多
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : TextButton.icon(
                                    onPressed: _loadMoreLetters,
                                    icon: const Icon(Icons.expand_more, size: 18),
                                    label: Text(
                                      '加载更多信件',
                                      style: TextStyle(color: cs.primary),
                                    ),
                                  ),
                          ),
                        );
                      }
                      final letter = _letters[index];
                      return _letterCard(cs, letter);
                    },
                  ),
                ),
    );
  }

  Widget _emptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mail_outline_rounded,
                size: 72, color: cs.primary.withOpacity(0.45)),
            const SizedBox(height: 16),
            Text('还没有收到来信',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('点右上角，让 TA 给你写一封私密的信。',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _generating ? null : _selectCharacterAndGenerate,
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(_generating ? '正在写信...' : '生成一封来信'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letterCard(ColorScheme cs, AILetter letter) {
    final isUserLetter = letter.isFromUser;
    final iconData = isUserLetter ? Icons.send_rounded : Icons.mail_rounded;
    final iconBg = isUserLetter
        ? cs.primaryContainer.withOpacity(0.5)
        : cs.primary.withOpacity(0.12);
    final iconColor = isUserLetter ? cs.primary : cs.primary;
    final senderLabel =
        isUserLetter ? '你 → ${letter.characterName}' : letter.characterName;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AILetterDetailScreen(letterId: letter.id),
            ),
          );
          _loadLetters();
        },
        onLongPress: () => _showDeleteDialog(letter),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: iconBg,
                child: Icon(iconData, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            letter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: letter.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (!letter.isRead && !isUserLetter)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$senderLabel · ${_formatTime(letter.createdAt)}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      letter.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        height: 1.45,
                        color: cs.onSurface.withOpacity(0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AILetterDetailScreen extends StatefulWidget {
  final String letterId;
  const AILetterDetailScreen({super.key, required this.letterId});

  @override
  State<AILetterDetailScreen> createState() => _AILetterDetailScreenState();
}

class _AILetterDetailScreenState extends State<AILetterDetailScreen> {
  AILetter? _letter;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLetter();
  }

  Future<void> _loadLetter() async {
    final storage = context.read<LocalStorageRepository>();
    final letter = await storage.getAILetter(widget.letterId);
    if (letter != null && !letter.isRead) {
      await storage.markAILetterRead(letter.id);
    }
    if (!mounted) return;
    setState(() {
      _letter = letter?.copyWith(isRead: true, readAt: DateTime.now());
      _loading = false;
    });
  }

  Future<void> _deleteLetter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除来信'),
        content: const Text('确定要删除这封来信吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final storage = context.read<LocalStorageRepository>();
    await storage.deleteAILetter(widget.letterId);
    if (mounted) Navigator.pop(context);
  }

  String _formatDate(DateTime time) {
    return '${time.year}年${time.month}月${time.day}日 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final letter = _letter;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(letter?.title ?? '来信'),
        centerTitle: true,
        actions: [
          if (letter != null)
            IconButton(
              tooltip: '删除',
              onPressed: _deleteLetter,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : letter == null
              ? const Center(child: Text('这封信不存在'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: letter.isFromUser
                              ? cs.primaryContainer.withOpacity(0.5)
                              : cs.primary.withOpacity(0.12),
                          child: Icon(
                            letter.isFromUser
                                ? Icons.send_rounded
                                : Icons.mail_rounded,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                letter.isFromUser
                                    ? '你 → ${letter.characterName}'
                                    : '来自 ${letter.characterName}',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface),
                              ),
                              const SizedBox(height: 3),
                              Text(_formatDate(letter.createdAt),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: SelectableText(
                        letter.content,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        letter.isFromUser
                            ? '—— ${letter.recipientName}'
                            : '—— ${letter.characterName}',
                        style: TextStyle(
                            fontSize: 15,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
    );
  }
}
