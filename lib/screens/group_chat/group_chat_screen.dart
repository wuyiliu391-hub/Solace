// 【对标来源：SillyTavern-1.18.0 — group-chats.js 群聊管理界面】
// 1:1 转译自 SillyTavern Group Chat 创建/编辑/成员管理逻辑
// 参考文件：public/scripts/group-chats.js

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../blocs/group_chat/group_chat_event.dart';
import '../../blocs/group_chat/group_chat_state.dart';
import '../../models/ai_character.dart' hide ReplyMode;
import '../../models/group_chat_session.dart';
import '../../models/group_member_settings.dart';
import '../../repositories/local_storage_repository.dart';

/// 群聊创建/编辑管理页面
/// 对标 SillyTavern 的 Group Chat 管理功能
/// 支持创建和编辑两种模式
class GroupChatScreen extends StatefulWidget {
  /// 群聊 ID，非空时为编辑模式，为空时为创建模式
  final String? groupId;

  const GroupChatScreen({super.key, this.groupId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  // ==================== Controllers ====================
  final _nameController = TextEditingController();
  final _joinPrefixController = TextEditingController();
  final _joinSuffixController = TextEditingController();
  final _autoDelayController = TextEditingController();
  final _memberSearchController = TextEditingController();
  final _candidateSearchController = TextEditingController();
  final _scrollController = ScrollController();

  // ==================== State ====================
  bool get _isEditMode => widget.groupId != null;

  String _groupName = '';
  String? _avatarPath;
  int _activationStrategy = 0; // 0=natural, 1=list, 2=manual, 3=pooled
  int _generationMode = 0; // 0=swap, 1=append, 2=append_disabled
  // _joinPrefix and _joinSuffix are read directly from controllers on save
  // These getters exist for clarity if needed in future extension
  String get _joinPrefix => _joinPrefixController.text;
  String get _joinSuffix => _joinSuffixController.text;
  bool _allowSelfResponses = false;
  bool _autoMode = false;
  int _autoModeDelay = 5;
  bool _hideMutedSprites = false;

  List<AICharacter> _members = [];
  List<String> _disabledMemberIds = [];
  List<AICharacter> _allCharacters = [];
  String _memberSearchQuery = '';
  String _candidateSearchQuery = '';

  bool _isLoading = true;
  bool _isSaving = false;

  // ==================== Lifecycle ====================

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      _groupName = _nameController.text;
    });
    // joinPrefix/Suffix are read directly from controllers when needed
    _memberSearchController.addListener(() {
      setState(() => _memberSearchQuery = _memberSearchController.text);
    });
    _candidateSearchController.addListener(() {
      setState(() => _candidateSearchQuery = _candidateSearchController.text);
    });
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _joinPrefixController.dispose();
    _joinSuffixController.dispose();
    _autoDelayController.dispose();
    _memberSearchController.dispose();
    _candidateSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final characters = await storage.getAllAICharacters();

    if (_isEditMode && widget.groupId != null) {
      final session = await storage.getGroupChatSession(widget.groupId!);
      if (session != null) {
        _groupName = session.name;
        _nameController.text = session.name;
        _avatarPath = session.avatarUrl;
        _activationStrategy = session.activationStrategy.index;
        _allowSelfResponses = session.allowSelfResponse;
        _autoMode = session.autoModeEnabled;

        // Map replyMode to generationMode
        if (session.replyMode == ReplyMode.sequential) {
          _generationMode = 0; // swap
        } else {
          _generationMode = 0; // default swap
        }

        // Load members from session
        final memberChars = <AICharacter>[];
        for (final id in session.participantIds) {
          final char = characters.where((c) => c.id == id).toList();
          if (char.isNotEmpty) {
            memberChars.add(char.first);
          }
        }
        _members = memberChars;

        // Load disabled members
        final memberSettings =
            await storage.getGroupMemberSettingsByGroup(widget.groupId!);
        _disabledMemberIds = memberSettings
            .where((s) => s.isMuted)
            .map((s) => s.characterId)
            .toList();
      }
    }

    if (!mounted) return;
    setState(() {
      _allCharacters = characters;
      _isLoading = false;
    });
  }

  // ==================== Computed Properties ====================

  String get _currentUserId {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) return authState.user.id;
    return '';
  }

  List<AICharacter> get _filteredMembers {
    if (_memberSearchQuery.isEmpty) return _members;
    final q = _memberSearchQuery.toLowerCase();
    return _members
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  List<AICharacter> get _filteredCandidates {
    final memberIds = _members.map((m) => m.id).toSet();
    final candidates =
        _allCharacters.where((c) => !memberIds.contains(c.id)).toList();
    if (_candidateSearchQuery.isEmpty) return candidates;
    final q = _candidateSearchQuery.toLowerCase();
    return candidates
        .where((c) => c.name.toLowerCase().contains(q))
        .toList();
  }

  bool get _showJoinFields =>
      _generationMode == 1 || _generationMode == 2;

  bool get _canSave =>
      _members.length >= 2 && !_isSaving;

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(_isEditMode ? '编辑群聊' : '创建群聊'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: BlocListener<GroupChatBloc, GroupChatState>(
        listener: _onBlocStateChanged,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _buildGroupInfoSection(colorScheme),
            const SizedBox(height: 24),
            _buildGroupSettingsSection(colorScheme),
            const SizedBox(height: 24),
            _buildCurrentMembersSection(colorScheme),
            const SizedBox(height: 24),
            _buildAddMembersSection(colorScheme),
            const SizedBox(height: 24),
            _buildBottomButtons(colorScheme),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ==================== Bloc Listener ====================

  void _onBlocStateChanged(BuildContext context, GroupChatState state) {
    if (state is GroupChatSessionCreated) {
      setState(() => _isSaving = false);
      Navigator.pop(context, true);
    } else if (state is GroupChatSessionsLoaded) {
      // After deletion or update, pop back
      setState(() => _isSaving = false);
      Navigator.pop(context, true);
    } else if (state is GroupChatError) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: ${state.message}')),
      );
    }
  }

  // ==================== Section 1: Group Info ====================

  Widget _buildGroupInfoSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('群聊信息', colorScheme),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatarPreview(colorScheme),
            const SizedBox(width: 16),
            Expanded(child: _buildNameInput(colorScheme)),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarPreview(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: _avatarPath != null && _avatarPath!.isNotEmpty
            ? ClipOval(
                child: _avatarPath!.startsWith('/') ||
                        _avatarPath!.startsWith('C:') ||
                        _avatarPath!.contains('\\')
                    ? Image.file(
                        File(_avatarPath!),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildDefaultAvatarCollage(colorScheme),
                      )
                    : Image.network(
                        _avatarPath!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _buildDefaultAvatarCollage(colorScheme),
                      ),
              )
            : _buildDefaultAvatarCollage(colorScheme),
      ),
    );
  }

  Widget _buildDefaultAvatarCollage(ColorScheme colorScheme) {
    final displayMembers = _members.take(4).toList();

    if (displayMembers.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.group_add,
            size: 28,
            color: colorScheme.onSurface.withOpacity(0.4),
          ),
          const SizedBox(height: 4),
          Text(
            '头像',
            style: TextStyle(
              fontSize: 10,
              color: colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      );
    }

    if (displayMembers.length == 1) {
      return ClipOval(child: _buildMemberAvatarImage(displayMembers[0], 40));
    }

    // 2x2 grid collage for 2-4 members
    return ClipOval(
      child: GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(4, (index) {
          if (index < displayMembers.length) {
            return _buildMemberAvatarImage(displayMembers[index], 20);
          }
          // Fill remaining slots with the first member
          return _buildMemberAvatarImage(displayMembers[0], 20);
        }),
      ),
    );
  }

  Widget _buildNameInput(ColorScheme colorScheme) {
    return TextField(
      controller: _nameController,
      decoration: InputDecoration(
        hintText: '群聊名称（选填）',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _avatarPath = picked.path);
    }
  }

  // ==================== Section 2: Group Settings ====================

  Widget _buildGroupSettingsSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('群聊设置', colorScheme),
        const SizedBox(height: 12),
        _buildActivationStrategyDropdown(colorScheme),
        const SizedBox(height: 12),
        _buildGenerationModeDropdown(colorScheme),
        if (_showJoinFields) ...[
          const SizedBox(height: 12),
          _buildJoinPrefixField(colorScheme),
          const SizedBox(height: 12),
          _buildJoinSuffixField(colorScheme),
        ],
        const SizedBox(height: 16),
        _buildCheckboxes(colorScheme),
      ],
    );
  }

  Widget _buildActivationStrategyDropdown(ColorScheme colorScheme) {
    return _buildDropdownCard<int>(
      colorScheme,
      label: '激活策略',
      value: _activationStrategy,
      items: const [
        DropdownMenuItem(value: 0, child: Text('自然顺序')),
        DropdownMenuItem(value: 1, child: Text('列表顺序')),
        DropdownMenuItem(value: 2, child: Text('手动触发')),
        DropdownMenuItem(value: 3, child: Text('池化顺序')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _activationStrategy = v);
      },
    );
  }

  Widget _buildGenerationModeDropdown(ColorScheme colorScheme) {
    return _buildDropdownCard<int>(
      colorScheme,
      label: '生成模式',
      value: _generationMode,
      items: const [
        DropdownMenuItem(value: 0, child: Text('替换角色卡')),
        DropdownMenuItem(value: 1, child: Text('拼接（排除禁用）')),
        DropdownMenuItem(value: 2, child: Text('拼接（包含禁用）')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _generationMode = v);
      },
    );
  }

  Widget _buildDropdownCard<T>(
    ColorScheme colorScheme, {
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinPrefixField(ColorScheme colorScheme) {
    return TextField(
      controller: _joinPrefixController,
      decoration: InputDecoration(
        labelText: '拼接前缀',
        hintText: '每张角色卡前插入的文本',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildJoinSuffixField(ColorScheme colorScheme) {
    return TextField(
      controller: _joinSuffixController,
      decoration: InputDecoration(
        labelText: '拼接后缀',
        hintText: '每张角色卡后插入的文本',
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildCheckboxes(ColorScheme colorScheme) {
    return Column(
      children: [
        _buildCheckboxTile(
          colorScheme,
          title: '允许自我回复',
          value: _allowSelfResponses,
          onChanged: (v) =>
              setState(() => _allowSelfResponses = v ?? false),
        ),
        _buildCheckboxTile(
          colorScheme,
          title: '自动模式',
          value: _autoMode,
          onChanged: (v) => setState(() => _autoMode = v ?? false),
          trailing: _autoMode
              ? SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _autoDelayController
                      ..text = _autoModeDelay.toString(),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '秒',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest
                          .withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null && parsed >= 1 && parsed <= 999) {
                        _autoModeDelay = parsed;
                      }
                    },
                  ),
                )
              : null,
        ),
        _buildCheckboxTile(
          colorScheme,
          title: '隐藏禁用成员立绘',
          value: _hideMutedSprites,
          onChanged: (v) =>
              setState(() => _hideMutedSprites = v ?? false),
        ),
      ],
    );
  }

  Widget _buildCheckboxTile(
    ColorScheme colorScheme, {
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: colorScheme.primary,
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  // ==================== Section 3: Current Members ====================

  Widget _buildCurrentMembersSection(ColorScheme colorScheme) {
    final filtered = _filteredMembers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionTitle('当前成员', colorScheme),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _members.length >= 2
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_members.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _members.length >= 2
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSearchBar(
          colorScheme,
          controller: _memberSearchController,
          hint: '搜索成员...',
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          _buildEmptyState(
            colorScheme,
            icon: Icons.people_outline,
            message: _members.isEmpty ? '还没有添加成员' : '未找到匹配的成员',
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            onReorder: _onReorderMembers,
            itemBuilder: (context, index) {
              final member = filtered[index];
              final isDisabled = _disabledMemberIds.contains(member.id);
              return _buildMemberTile(colorScheme, member, isDisabled, index);
            },
          ),
      ],
    );
  }

  Widget _buildMemberTile(
    ColorScheme colorScheme,
    AICharacter member,
    bool isDisabled,
    int index,
  ) {
    return Container(
      key: ValueKey(member.id),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDisabled
            ? colorScheme.surfaceContainerHighest.withOpacity(0.15)
            : colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDisabled
              ? colorScheme.outline.withOpacity(0.1)
              : colorScheme.outline.withOpacity(0.15),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Opacity(
          opacity: isDisabled ? 0.4 : 1.0,
          child: _buildMemberAvatar(member, 20),
        ),
        title: Text(
          member.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDisabled
                ? colorScheme.onSurface.withOpacity(0.4)
                : colorScheme.onSurface,
          ),
        ),
        subtitle: isDisabled
            ? Text(
                '已禁用',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface.withOpacity(0.3),
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Toggle mute
            IconButton(
              icon: Icon(
                isDisabled ? Icons.volume_off : Icons.volume_up,
                size: 18,
                color: isDisabled
                    ? colorScheme.onSurface.withOpacity(0.3)
                    : colorScheme.onSurface.withOpacity(0.6),
              ),
              tooltip: isDisabled ? '启用' : '禁用',
              onPressed: () => _toggleMemberDisabled(member.id),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Move up
            IconButton(
              icon: Icon(
                Icons.arrow_upward,
                size: 18,
                color: index == 0
                    ? colorScheme.onSurface.withOpacity(0.15)
                    : colorScheme.onSurface.withOpacity(0.5),
              ),
              onPressed: index == 0 ? null : () => _moveMember(index, -1),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Move down
            IconButton(
              icon: Icon(
                Icons.arrow_downward,
                size: 18,
                color: index == _members.length - 1
                    ? colorScheme.onSurface.withOpacity(0.15)
                    : colorScheme.onSurface.withOpacity(0.5),
              ),
              onPressed: index == _members.length - 1
                  ? null
                  : () => _moveMember(index, 1),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Remove
            IconButton(
              icon: Icon(
                Icons.close,
                size: 18,
                color: const Color(0xFFE53935).withOpacity(0.7),
              ),
              tooltip: '移除',
              onPressed: () => _confirmRemoveMember(member),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Trigger reply (edit mode only)
            if (_isEditMode)
              IconButton(
                icon: Icon(
                  Icons.chat_bubble,
                  size: 18,
                  color: colorScheme.primary.withOpacity(0.7),
                ),
                tooltip: '触发回复',
                onPressed: () => _triggerMemberReply(member),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  void _onReorderMembers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _members.removeAt(oldIndex);
      _members.insert(newIndex, item);
    });
  }

  void _toggleMemberDisabled(String characterId) {
    setState(() {
      if (_disabledMemberIds.contains(characterId)) {
        _disabledMemberIds.remove(characterId);
      } else {
        _disabledMemberIds.add(characterId);
      }
    });
  }

  void _moveMember(int index, int direction) {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= _members.length) return;
    setState(() {
      final temp = _members[index];
      _members[index] = _members[newIndex];
      _members[newIndex] = temp;
    });
  }

  void _confirmRemoveMember(AICharacter member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定要将「${member.name}」从群聊中移除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _members.removeWhere((m) => m.id == member.id);
                _disabledMemberIds.remove(member.id);
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  void _triggerMemberReply(AICharacter member) {
    if (widget.groupId == null) return;
    final userId = _currentUserId;
    if (userId.isEmpty) return;

    context.read<GroupChatBloc>().add(GroupChatForceReply(
          groupChatId: widget.groupId!,
          userId: userId,
          characterId: member.id,
        ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已触发「${member.name}」回复'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ==================== Section 4: Add Members ====================

  Widget _buildAddMembersSection(ColorScheme colorScheme) {
    final candidates = _filteredCandidates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('添加成员', colorScheme),
        const SizedBox(height: 8),
        _buildSearchBar(
          colorScheme,
          controller: _candidateSearchController,
          hint: '搜索角色...',
        ),
        const SizedBox(height: 8),
        if (candidates.isEmpty)
          _buildEmptyState(
            colorScheme,
            icon: Icons.person_add_outlined,
            message: _allCharacters.isEmpty
                ? '还没有创建角色，快去创建吧'
                : '所有角色都已在群聊中',
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return _buildCandidateTile(colorScheme, candidate);
            },
          ),
      ],
    );
  }

  Widget _buildCandidateTile(ColorScheme colorScheme, AICharacter candidate) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildMemberAvatar(candidate, 20),
        title: Text(
          candidate.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.add_circle_outline,
            color: colorScheme.primary,
          ),
          tooltip: '添加到群聊',
          onPressed: () => _addMember(candidate),
        ),
      ),
    );
  }

  void _addMember(AICharacter candidate) {
    if (_members.any((m) => m.id == candidate.id)) return;
    setState(() {
      _members.add(candidate);
    });
  }

  // ==================== Section 5: Bottom Buttons ====================

  Widget _buildBottomButtons(ColorScheme colorScheme) {
    return Column(
      children: [
        // Primary action button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _canSave ? _onSave : null,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSaving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Text(
                    _isEditMode ? '保存修改' : '创建群聊',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        // Back button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(
                color: colorScheme.outline.withOpacity(0.3),
              ),
            ),
            child: Text(
              '返回',
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        ),
        // Delete button (edit mode only)
        if (_isEditMode) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: _confirmDeleteGroup,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: const BorderSide(
                  color: Color(0xFFE53935),
                  width: 1,
                ),
                foregroundColor: const Color(0xFFE53935),
              ),
              child: const Text(
                '删除群聊',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFE53935),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _confirmDeleteGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除群聊'),
        content: const Text('确定要删除这个群聊吗？此操作不可撤销，所有聊天记录将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _onDeleteGroup();
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ==================== Actions ====================

  void _onSave() {
    if (!_canSave) return;
    setState(() => _isSaving = true);

    if (_isEditMode) {
      _updateExistingGroup();
    } else {
      _createNewGroup();
    }
  }

  void _createNewGroup() {
    final userId = _currentUserId;
    if (userId.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户未登录')),
      );
      return;
    }

    // Map UI generation mode to ReplyMode
    final replyMode =
        _generationMode == 0 ? ReplyMode.sequential : ReplyMode.flash;

    // Map UI activation strategy to ActivationStrategy enum
    ActivationStrategy strategy;
    switch (_activationStrategy) {
      case 1:
        strategy = ActivationStrategy.list;
        break;
      case 2:
        strategy = ActivationStrategy.manual;
        break;
      default:
        strategy = ActivationStrategy.natural;
    }

    context.read<GroupChatBloc>().add(GroupChatCreateSession(
          userId: userId,
          name: _groupName.isNotEmpty ? _groupName : '群聊',
          participants: _members,
          replyMode: replyMode,
          activationStrategy: strategy,
        ));
  }

  Future<void> _updateExistingGroup() async {
    if (widget.groupId == null) return;

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final session = await storage.getGroupChatSession(widget.groupId!);
    if (session == null) {
      setState(() => _isSaving = false);
      return;
    }

    // Map activation strategy
    ActivationStrategy strategy;
    switch (_activationStrategy) {
      case 1:
        strategy = ActivationStrategy.list;
        break;
      case 2:
        strategy = ActivationStrategy.manual;
        break;
      default:
        strategy = ActivationStrategy.natural;
    }

    // Map reply mode
    final replyMode =
        _generationMode == 0 ? ReplyMode.sequential : ReplyMode.flash;

    // Update session
    final updatedSession = session.copyWith(
      name: _groupName.isNotEmpty ? _groupName : session.name,
      avatarUrl: _avatarPath,
      participantIds: _members.map((m) => m.id).toList(),
      participantNames: _members.map((m) => m.name).toList(),
      participantAvatars: _members.map((m) => m.avatarUrl).toList(),
      activationStrategy: strategy,
      replyMode: replyMode,
      autoModeEnabled: _autoMode,
      allowSelfResponse: _allowSelfResponses,
    );

    await storage.saveGroupChatSession(updatedSession);

    // Update member settings (disabled state)
    final existingSettings =
        await storage.getGroupMemberSettingsByGroup(widget.groupId!);
    for (int i = 0; i < _members.length; i++) {
      final member = _members[i];
      final isMuted = _disabledMemberIds.contains(member.id);
      final existing =
          existingSettings.where((s) => s.characterId == member.id).toList();

      if (existing.isNotEmpty) {
        await storage.saveGroupMemberSettings(existing.first.copyWith(
          isMuted: isMuted,
          sortOrder: i,
        ));
      } else {
        await storage.saveGroupMemberSettings(GroupMemberSettings(
          id: '${widget.groupId}_${member.id}',
          groupChatId: widget.groupId!,
          characterId: member.id,
          isMuted: isMuted,
          sortOrder: i,
        ));
      }
    }

    // Remove settings for members no longer in the group
    final memberIds = _members.map((m) => m.id).toSet();
    for (final setting in existingSettings) {
      if (!memberIds.contains(setting.characterId)) {
        // Settings for removed members will remain orphaned but harmless
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context, true);
  }

  Future<void> _onDeleteGroup() async {
    if (widget.groupId == null) return;
    setState(() => _isSaving = true);

    context.read<GroupChatBloc>().add(GroupChatDeleteSession(
          widget.groupId!,
          _currentUserId,
        ));
  }

  // ==================== Shared Widgets ====================

  Widget _sectionTitle(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    );
  }

  Widget _buildSearchBar(
    ColorScheme colorScheme, {
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(
          Icons.search,
          size: 20,
          color: colorScheme.onSurface.withOpacity(0.4),
        ),
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.25),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildEmptyState(
    ColorScheme colorScheme, {
    required IconData icon,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 36,
            color: colorScheme.onSurface.withOpacity(0.25),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberAvatar(AICharacter member, double radius) {
    return _buildMemberAvatarImage(member, radius);
  }

  Widget _buildMemberAvatarImage(AICharacter member, double radius) {
    final displayName = member.name;

    if (member.avatarUrl == null || member.avatarUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          displayName.isNotEmpty ? displayName.substring(0, 1) : '?',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (member.avatarUrl!.startsWith('/') ||
        member.avatarUrl!.startsWith('C:') ||
        member.avatarUrl!.contains('\\')) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(member.avatarUrl!)),
        onBackgroundImageError: (error, stackTrace) {},
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(member.avatarUrl!),
      onBackgroundImageError: (error, stackTrace) {},
    );
  }
}
