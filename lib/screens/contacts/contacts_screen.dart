import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/persona_evolution_service.dart';
import '../../services/memory_engine.dart';
import '../../services/permission_service.dart';
import '../chat/chat_detail_screen.dart';
import '../../blocs/chat/chat_bloc.dart';
import '../../services/ai_service.dart';
import '../../services/bridge/ai_service_adapter.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<AICharacter> _characters = [];
  bool _isLoading = true;
  StreamSubscription? _chatSub;

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCharacters() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final characters = await storage.getAllAICharacters();
    setState(() {
      _characters = characters;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,

      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _characters.isEmpty
              ? _buildEmptyState(context)
              : _buildCharacterList(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有好友',
            style: TextStyle(
              fontSize: 18,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右上角 + 添加你的第一个好友',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterList(BuildContext context) {
    return ListView.builder(
      itemCount: _characters.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildHeader(context, '我的好友 (${_characters.length})');
        }
        final character = _characters[index - 1];
        return _CharacterTile(
          character: character,
          onTap: () => _startChat(character),
          onLongPress: () => _showCharacterOptions(context, character),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
    );
  }

  void _showCharacterOptions(BuildContext context, AICharacter character) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('修改备注'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditRemarkDialog(context, character);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('自定义头像'),
              onTap: () {
                Navigator.pop(ctx);
                _changeAvatar(context, character);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.visibility_off, color: Colors.orange),
              title: const Text('隐藏联系人'),
              onTap: () {
                Navigator.pop(ctx);
                _hideCharacter(context, character);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除联系人'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteCharacter(context, character);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRemarkDialog(BuildContext context, AICharacter character) {
    final controller = TextEditingController(text: character.userAlias ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改备注'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入你对TA的称呼',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final alias = controller.text.trim();
              final updated = character.copyWith(
                userAlias: alias.isEmpty ? null : alias,
                updatedAt: DateTime.now(),
              );
              final storage = RepositoryProvider.of<LocalStorageRepository>(context);
              await storage.saveAICharacter(updated);
              _loadCharacters();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeAvatar(BuildContext context, AICharacter character) async {
    final hasPermission = await PermissionService.requestStoragePermission();
    if (!hasPermission) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final persistentPath = await _copyToPersistentPath(pickedFile.path, character.id);
      final updated = character.copyWith(
        avatarUrl: persistentPath,
        updatedAt: DateTime.now(),
      );
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      await storage.saveAICharacter(updated);

      // Update chat sessions' avatar for this character
      try {
        final authBloc = context.read<AuthBloc>();
        if (authBloc.state is AuthAuthenticated) {
          final userId = (authBloc.state as AuthAuthenticated).user.id;
          final sessions = await storage.getChatSessions(userId);
          for (var session in sessions) {
            if (session.aiCharacterId == character.id) {
              final updatedSession = session.copyWith(
                aiCharacterAvatar: persistentPath,
                updatedAt: DateTime.now(),
              );
              await storage.saveChatSession(updatedSession);
            }
          }
          // Refresh chat list
          _refreshChatList();
        }
      } catch (e) {
        debugPrint('更新聊天会话头像失败: $e');
      }

      _loadCharacters();
    }
  }

  Future<String> _copyToPersistentPath(String sourcePath, String characterId) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/ai_avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      final destPath = '${avatarDir.path}/$characterId.$ext';
      await source.copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('复制头像失败: $e');
      return sourcePath;
    }
  }

  void _hideCharacter(BuildContext context, AICharacter character) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final updated = character.copyWith(isHidden: true, updatedAt: DateTime.now());
    await storage.saveAICharacter(updated);
    _loadCharacters();
    _refreshChatList();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已隐藏联系人')),
      );
    }
  }

  void _deleteCharacter(BuildContext context, AICharacter character) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除联系人'),
        content: Text('确定要永久删除"${character.userNickname ?? character.name}"吗？\n\n这将删除其所有聊天记录和记忆。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final storage = RepositoryProvider.of<LocalStorageRepository>(context);
              await storage.deleteAICharacterCascade(character.id);
              _loadCharacters();
              _refreshChatList();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已删除"${character.userNickname ?? character.name}"')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _startChat(AICharacter character) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final user = (context.read<AuthBloc>().state as AuthAuthenticated).user;

    final sessions = await storage.getChatSessions(user.id);
    final existingSession = sessions.where((s) => s.aiCharacterId == character.id).firstOrNull;

    if (existingSession != null) {
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(session: existingSession),
          ),
        );
        // 从聊天详情返回后刷新联系人列表（头像、别名等可能已变更）
        if (mounted) _loadCharacters();
      }
      return;
    }

    final chatBloc = ChatBloc(
      storage,
      AIService(storage),
    );

    _chatSub?.cancel();
    _chatSub = chatBloc.stream.listen((state) {
      if (state is ChatSessionCreated) {
        _chatSub?.cancel();
        _chatSub = null;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailScreen(session: state.session),
            ),
          ).then((_) => chatBloc.close());
        } else {
          chatBloc.close();
        }
      }
    });

    chatBloc.add(ChatCreateSession(userId: user.id, character: character));
  }

  void _refreshChatList() {
    try {
      final authBloc = context.read<AuthBloc>();
      if (authBloc.state is AuthAuthenticated) {
        final userId = (authBloc.state as AuthAuthenticated).user.id;
        context.read<ChatBloc>().add(ChatLoadSessions(userId));
      }
    } catch (e) {
      debugPrint('刷新聊天列表失败: $e');
    }
  }
}

class _CharacterTile extends StatelessWidget {
  final AICharacter character;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CharacterTile({
    required this.character,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = character.userAlias ?? character.name;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outline.withOpacity(0.1),
            ),
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(context),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((character.userAlias?.isNotEmpty) == true) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${character.name})',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    character.personality,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = character.userAlias ?? character.name;

    if (character.avatarUrl == null || character.avatarUrl!.isEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: colorScheme.primaryContainer,
        child: Text(
          displayName.isNotEmpty ? displayName.substring(0, 1) : '?',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (character.avatarUrl!.startsWith('/') ||
        character.avatarUrl!.startsWith('C:') ||
        character.avatarUrl!.contains('\\')) {
      return CircleAvatar(
        radius: 28,
        backgroundImage: FileImage(File(character.avatarUrl!)),
        onBackgroundImageError: (error, stackTrace) {},
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundImage: NetworkImage(character.avatarUrl!),
      onBackgroundImageError: (error, stackTrace) {},
    );
  }
}
