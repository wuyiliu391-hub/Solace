import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../data/character_templates.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import 'create_character_screen.dart';

class TemplateSelectionScreen extends StatefulWidget {
  const TemplateSelectionScreen({super.key});

  @override
  State<TemplateSelectionScreen> createState() => _TemplateSelectionScreenState();
}

class _TemplateSelectionScreenState extends State<TemplateSelectionScreen> {
  bool _isLoading = false;

  Future<void> _selectTemplate(CharacterTemplate template) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => _TemplateCustomizationScreen(template: template),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _createCustomCharacter() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateCharacterScreen(),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Hero(
          tag: 'app_icon_create_character',
          child: Text('选择角色模板'),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '快速创建',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 12),
          ...CharacterTemplates.templates.map((template) => _buildTemplateCard(template, colorScheme)),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _createCustomCharacter,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('自定义创建'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(CharacterTemplate template, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _selectTemplate(template),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    template.name.isNotEmpty ? template.name.substring(0, 1) : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.personality,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
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
      ),
    );
  }
}

class _TemplateCustomizationScreen extends StatefulWidget {
  final CharacterTemplate template;

  const _TemplateCustomizationScreen({required this.template});

  @override
  State<_TemplateCustomizationScreen> createState() => _TemplateCustomizationScreenState();
}

class _TemplateCustomizationScreenState extends State<_TemplateCustomizationScreen> {
  final _nameController = TextEditingController();
  String? _selectedAvatar;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.template.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createCharacter() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入名字')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      
      // 获取当前用户ID
      String? userId;
      try {
        final authState = context.read<AuthBloc>().state;
        if (authState is AuthAuthenticated) {
          userId = authState.user.id;
        }
      } catch (e) {
        debugPrint('获取用户ID失败: $e');
      }
      
      final character = widget.template.toAICharacter(
        id: const Uuid().v4(),
        customName: _nameController.text.trim(),
        avatarUrl: _selectedAvatar,
      );

      await storage.saveAICharacter(character);

      // 创建聊天会话
      if (userId != null) {
        final now = DateTime.now();
        final session = ChatSession(
          id: const Uuid().v4(),
          userId: userId,
          aiCharacterId: character.id,
          aiCharacterName: character.name,
          aiCharacterAvatar: character.avatarUrl,
          lastMessage: character.openingLine ?? '我们已经是好友了，开始聊天吧！',
          lastMessageTime: now,
          createdAt: now,
          updatedAt: now,
        );
        await storage.saveChatSession(session);
        debugPrint('已创建角色和会话: ${character.name}');
      } else {
        debugPrint('警告：无法获取用户ID，未创建会话');
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${character.name} 为好友')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('创建${widget.template.name}'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _nameController.text.isNotEmpty
                              ? _nameController.text.substring(0, 1)
                              : (widget.template.name.isNotEmpty ? widget.template.name.substring(0, 1) : '?'),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    // 可选：添加头像选择功能
                  },
                  child: Text(
                    '选择头像（可选）',
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '名字',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          _buildInfoCard('性格', widget.template.personality, colorScheme),
          const SizedBox(height: 12),
          _buildInfoCard('心愿', widget.template.coreDesire, colorScheme),
          const SizedBox(height: 12),
          _buildInfoCard('原则', widget.template.moralBoundary, colorScheme),
          if (widget.template.backgroundStory != null) ...[
            const SizedBox(height: 12),
            _buildInfoCard('故事', widget.template.backgroundStory!, colorScheme),
          ],
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createCharacter,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '添加好友',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String content, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}
