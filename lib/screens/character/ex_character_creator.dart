import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ex_persona_analyzer.dart';

class ExCharacterCreator extends StatefulWidget {
  const ExCharacterCreator({super.key});

  @override
  State<ExCharacterCreator> createState() => _ExCharacterCreatorState();
}

class _ExCharacterCreatorState extends State<ExCharacterCreator> {
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _chatHistoryController = TextEditingController();
  String _gender = 'female';
  bool _isLoading = false;
  bool _analyzed = false;
  AICharacter? _result;

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _descriptionController.dispose();
    _chatHistoryController.dispose();
    super.dispose();
  }

  bool get _canAnalyze =>
      _nameController.text.trim().isNotEmpty &&
      (_descriptionController.text.trim().isNotEmpty ||
          _chatHistoryController.text.trim().isNotEmpty);

  void tapHaptic() {
    // placeholder for haptic feedback
  }

  Future<void> _startAnalysis() async {
    if (!_canAnalyze) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少填写名字，并提供描述或聊天记录')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _analyzed = false;
      _result = null;
    });

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final analyzer = ExPersonaAnalyzer(storage);
      final character = await analyzer.analyze(
        name: _nameController.text.trim(),
        gender: _gender,
        relationshipContext: _relationshipController.text.trim(),
        userDescription: _descriptionController.text.trim(),
        chatHistory: _chatHistoryController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _result = character;
          _analyzed = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分析失败: $e')),
        );
      }
    }
  }

  String? _getCurrentUserId() {
    try {
      final authBloc = context.read<AuthBloc>();
      final state = authBloc.state;
      if (state is AuthAuthenticated) {
        return state.user.id;
      }
    } catch (e) {
      debugPrint('获取当前用户ID失败: $e');
    }
    return null;
  }

  Future<void> _saveCharacter() async {
    if (_result == null) return;

    setState(() => _isLoading = true);

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final character = _result!;

      await storage.saveAICharacter(character);

      final userId = _getCurrentUserId();
      if (userId != null) {
        final now = DateTime.now();
        final session = ChatSession(
          id: const Uuid().v4(),
          userId: userId,
          aiCharacterId: character.id,
          aiCharacterName: character.name,
          aiCharacterAvatar: character.avatarUrl,
          lastMessage: '我们已经是好友了，开始聊天吧！',
          lastMessageTime: now,
          createdAt: now,
          updatedAt: now,
        );
        await storage.saveChatSession(session);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${character.name} 为好友')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('从回忆创建'),
        centerTitle: true,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: _analyzed && _result != null
              ? _buildResultView(colorScheme)
              : _buildInputView(colorScheme),
        ),
      ),
    );
  }

  List<Widget> _buildInputView(ColorScheme colorScheme) {
    return [
      _buildSectionHeader('基本信息', colorScheme),
      const SizedBox(height: 12),
      TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: 'TA 的名字 *',
          hintText: '输入你对 TA 的称呼',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _gender,
        decoration: InputDecoration(
          labelText: '性别',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: const [
          DropdownMenuItem(value: 'female', child: Text('女')),
          DropdownMenuItem(value: 'male', child: Text('男')),
          DropdownMenuItem(value: 'other', child: Text('其他')),
        ],
        onChanged: (v) => setState(() => _gender = v ?? 'female'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _relationshipController,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: '关系背景（可选）',
          hintText: '如：在一起两年，大学同学，异地半年',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 24),
      _buildSectionHeader('上传材料', colorScheme),
      const SizedBox(height: 12),
      TextField(
        controller: _chatHistoryController,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: '聊天记录（可选）',
          hintText: '粘贴你们的聊天记录，越真实越像 TA',
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 24),
      _buildSectionHeader('你的描述', colorScheme),
      const SizedBox(height: 12),
      TextField(
        controller: _descriptionController,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: '描述 TA 的性格',
          hintText: 'TA 是什么样的人？口头禅？吵架模式？让你印象最深的事？',
          alignLabelWithHint: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 32),
      SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _canAnalyze && !_isLoading ? _startAnalysis : null,
          icon: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(
            _isLoading ? 'AI 分析中...' : '开始分析',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _buildResultView(ColorScheme colorScheme) {
    final c = _result!;
    return [
      Center(
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: Center(
            child: Text(
              c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'AI 分析完成',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
      Text(
        '以下是 AI 根据材料还原的性格画像，你可以微调后再保存',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
      const SizedBox(height: 24),
      _buildEditableCard('性格', c.personality, colorScheme, (v) {
        setState(() => _result = c.copyWith(personality: v));
      }),
      const SizedBox(height: 12),
      _buildEditableCard('心愿', c.coreDesire, colorScheme, (v) {
        setState(() => _result = c.copyWith(coreDesire: v));
      }),
      const SizedBox(height: 12),
      _buildEditableCard('原则', c.moralBoundary, colorScheme, (v) {
        setState(() => _result = c.copyWith(moralBoundary: v));
      }),
      if (c.languageStyle != null) ...[
        const SizedBox(height: 12),
        _buildEditableCard('说话风格', c.languageStyle!, colorScheme, (v) {
          setState(() => _result = c.copyWith(languageStyle: v));
        }),
      ],
      if (c.backgroundStory != null) ...[
        const SizedBox(height: 12),
        _buildEditableCard('共同记忆', c.backgroundStory!, colorScheme, (v) {
          setState(() => _result = c.copyWith(backgroundStory: v));
        }),
      ],
      if (c.tabooTopics != null) ...[
        const SizedBox(height: 12),
        _buildEditableCard('不聊话题', c.tabooTopics!, colorScheme, (v) {
          setState(() => _result = c.copyWith(tabooTopics: v));
        }),
      ],
      if (c.userNickname != null) ...[
        const SizedBox(height: 12),
        _buildEditableCard('TA 对你的称呼', c.userNickname!, colorScheme, (v) {
          setState(() => _result = c.copyWith(userNickname: v));
        }),
      ],
      const SizedBox(height: 24),
      SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: _isLoading ? null : _saveCharacter,
          icon: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.favorite),
          label: Text(
            _isLoading ? '保存中...' : '保存并添加好友',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: () => setState(() {
          _analyzed = false;
          _result = null;
        }),
        child: const Text('重新分析'),
      ),
      const SizedBox(height: 32),
    ];
  }

  Widget _buildEditableCard(
    String title,
    String content,
    ColorScheme colorScheme,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showEditDialog(title, content, onChanged),
                child: Icon(Icons.edit, size: 16, color: colorScheme.primary),
              ),
            ],
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

  void _showEditDialog(
    String title,
    String currentValue,
    ValueChanged<String> onChanged,
  ) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 $title'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text, ColorScheme colorScheme) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface.withOpacity(0.6),
      ),
    );
  }
}
