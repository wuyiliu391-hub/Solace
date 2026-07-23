// 创建群聊页面（对标 ChatListScreen._showCreateOptions 模式）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../models/ai_character.dart';
import '../../blocs/auth/auth_bloc.dart';

class GroupChatCreateScreen extends StatefulWidget {
  const GroupChatCreateScreen({super.key});

  @override
  State<GroupChatCreateScreen> createState() => _GroupChatCreateScreenState();
}

class _GroupChatCreateScreenState extends State<GroupChatCreateScreen> {
  final TextEditingController _nameController = TextEditingController();
  final List<String> _selectedMemberIds = [];
  final List<String> _selectedAiCharacterIds = [];
  bool _isLoadingCharacters = true;
  List<AICharacter> _allCharacters = [];

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  Future<void> _loadCharacters() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final chars = await storage.getAllAICharacters();
    if (mounted) {
      setState(() {
        _allCharacters = chars;
        _isLoadingCharacters = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('创建群聊'),
        actions: [
          TextButton(
            onPressed: _createGroup,
            child: const Text('创建', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: _isLoadingCharacters
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 群名称输入
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: '输入群聊名称',
                      prefixIcon: Icon(Icons.group, color: colorScheme.primary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // AI 角色选择
                Expanded(
                  child: _buildCharacterSelection(colorScheme),
                ),
              ],
            ),
    );
  }

  Widget _buildCharacterSelection(ColorScheme colorScheme) {
    if (_allCharacters.isEmpty) {
      return Center(
        child: Text(
          '暂无可用角色\n请先在发现页添加角色',
          textAlign: TextAlign.center,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
        ),
      );
    }

    return ListView.separated(
      itemCount: _allCharacters.length,
      separatorBuilder: (context, index) => Divider(
        height: 0.5,
        indent: 60,
        color: colorScheme.outline.withOpacity(0.15),
      ),
      itemBuilder: (context, index) {
        final character = _allCharacters[index];
        final isSelected = _selectedAiCharacterIds.contains(character.id);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: character.avatarUrl != null && character.avatarUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      character.avatarUrl!,
                      fit: BoxFit.cover,
                      width: 32,
                      height: 32,
                      errorBuilder: (_, __, ___) => Text(
                        character.name.isNotEmpty
                            ? character.name.substring(0, 1)
                            : '?',
                        style: TextStyle(color: colorScheme.primary),
                      ),
                    ),
                  )
                : Text(
                    character.name.isNotEmpty
                        ? character.name.substring(0, 1)
                        : '?',
                    style: TextStyle(color: colorScheme.primary),
                  ),
          ),
          title: Text(
            character.userAlias ?? character.name,
            style: TextStyle(fontSize: 15),
          ),
          trailing: Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.2),
          ),
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedAiCharacterIds.remove(character.id);
              } else {
                _selectedAiCharacterIds.add(character.id);
              }
            });
          },
        );
      },
    );
  }

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入群聊名称')),
      );
      return;
    }

    if (_selectedAiCharacterIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一个 AI 角色')),
      );
      return;
    }

    final authBloc = context.read<AuthBloc>();
    String userId = 'local_user';
    if (authBloc.state is AuthAuthenticated) {
      userId = (authBloc.state as AuthAuthenticated).user.id;
    }

    // 用户自动加入
    final memberIds = List<String>.from(_selectedAiCharacterIds);
    if (!memberIds.contains(userId)) {
      memberIds.add(userId);
    }

    final bloc = context.read<GroupChatBloc>();
    bloc.add(GroupChatCreate(
      userId: userId,
      name: _nameController.text.trim(),
      memberIds: memberIds,
      aiCharacterIds: List<String>.from(_selectedAiCharacterIds),
    ));

    // 监听创建结果
    final state = await bloc.stream.firstWhere(
      (s) => s is GroupChatCreated || s is GroupChatError,
      orElse: () => bloc.state,
    );

    if (state is GroupChatCreated && mounted) {
      Navigator.pop(context, true);
    } else if (state is GroupChatError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: ${state.message}')),
      );
    }
  }
}
