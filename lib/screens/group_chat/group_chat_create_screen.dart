// 创建群聊页面（对标 ChatListScreen._showCreateOptions 模式）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../models/ai_character.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../utils/character_color.dart';
import '../../utils/avatar_resolver.dart';
import '../../widgets/avatar_picker.dart';

class GroupChatCreateScreen extends StatefulWidget {
  const GroupChatCreateScreen({super.key});

  @override
  State<GroupChatCreateScreen> createState() => _GroupChatCreateScreenState();
}

class _GroupChatCreateScreenState extends State<GroupChatCreateScreen> {
  final TextEditingController _nameController = TextEditingController();
  // Removed unused _selectedMemberIds - group chats use AI character IDs only
  // final List<String> _selectedMemberIds = [];
  final List<String> _selectedAiCharacterIds = [];
  String? _avatarUrl;
  bool _isLoadingCharacters = true;
  List<AICharacter> _allCharacters = [];

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  Future<void> _loadCharacters() async {
    // Use context.read instead of RepositoryProvider.of to avoid adding listeners during init
    final storage = context.read<LocalStorageRepository>();
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
                // 群头像（可选，选图自动存持久目录防丢失）
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: AvatarPicker(
                      currentAvatar: _avatarUrl,
                      onAvatarSelected: (path) =>
                          setState(() => _avatarUrl = path),
                      size: 80,
                    ),
                  ),
                ),
                _buildSelectedBar(colorScheme),
                // AI 角色选择（已选排前，可拖拽排序）
                Expanded(
                  child: _buildCharacterSelection(colorScheme),
                ),
              ],
            ),
    );
  }

  Widget _buildSelectedBar(ColorScheme colorScheme) {
    if (_selectedAiCharacterIds.isEmpty) return const SizedBox.shrink();
    final byId = {for (final c in _allCharacters) c.id: c};
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedAiCharacterIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final c = byId[_selectedAiCharacterIds[index]];
          if (c == null) return const SizedBox.shrink();
          final color = characterColor(
              colorHex: c.colorHex, name: c.name, cs: colorScheme);
          return Chip(
            avatar: _avatarWidget(c, colorScheme),
            label: Text(c.name, style: const TextStyle(fontSize: 12)),
            onDeleted: () =>
                setState(() => _selectedAiCharacterIds.remove(c.id)),
            deleteIconColor: colorScheme.onSurfaceVariant,
          );
        },
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

    final selected = _selectedAiCharacterIds.toSet();
    final byId = {for (final c in _allCharacters) c.id: c};
    final ordered = [
      ..._selectedAiCharacterIds.map((id) => byId[id]).whereType<AICharacter>(),
      ..._allCharacters.where((c) => !selected.contains(c.id)),
    ];

    return ReorderableListView.builder(
      itemCount: ordered.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final moved = ordered.removeAt(oldIndex);
          ordered.insert(newIndex, moved);
          _selectedAiCharacterIds
            ..clear()
            ..addAll(ordered
                .where((c) => selected.contains(c.id))
                .map((c) => c.id));
        });
      },
      itemBuilder: (context, index) {
        final character = ordered[index];
        final isSelected = selected.contains(character.id);
        return ListTile(
          key: ValueKey(character.id),
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: _avatarWidget(character, colorScheme),
          ),
          title: Text(
            character.userAlias ?? character.name,
            style: const TextStyle(fontSize: 15),
          ),
          trailing: Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurface.withOpacity(0.2),
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

  /// 角色头像（AvatarResolver 正确分派本地文件/asset/网络，失败回退首字圆）
  Widget _avatarWidget(AICharacter c, ColorScheme cs) {
    final image = AvatarResolver.imageWidget(
      c.avatarUrl,
      width: 32,
      height: 32,
      fit: BoxFit.cover,
      onError: () => Text(
        c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
        style: TextStyle(color: cs.primary),
      ),
    );
    return image ??
        Text(
          c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
          style: TextStyle(color: cs.primary),
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
      avatarUrl: _avatarUrl,
      memberIds: memberIds,
      aiCharacterIds: List<String>.from(_selectedAiCharacterIds),
    ));

    // 一次性监听创建结果（修复：原 listen 永不取消，叠加在全局单例上导致多次 pop）
    final subscription = bloc.stream.firstWhere(
      (state) => state is GroupChatCreated || state is GroupChatError,
    );
    subscription.then((state) {
      if (!mounted) return;
      if (state is GroupChatCreated) {
        Navigator.pop(context, true);
      } else if (state is GroupChatError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: ${state.message}')),
        );
      }
    });
  }
}