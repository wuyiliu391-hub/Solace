import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/chat_session.dart';
import '../../utils/age_extractor.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/permission_service.dart';


class CreateCharacterScreen extends StatefulWidget {
  const CreateCharacterScreen({super.key});

  @override
  State<CreateCharacterScreen> createState() => _CreateCharacterScreenState();
}

class _CreateCharacterScreenState extends State<CreateCharacterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _personalityController = TextEditingController();
  final _coreDesireController = TextEditingController();
  final _moralBoundaryController = TextEditingController();
  final _backgroundStoryController = TextEditingController();
  final _worldSettingController = TextEditingController();
  final _languageStyleController = TextEditingController();
  final _tabooTopicsController = TextEditingController();
  final _userNicknameController = TextEditingController();
  final _userPersonaController = TextEditingController();
  final _catchphrasesController = TextEditingController();
  final _openingLineController = TextEditingController();
  final _characterTagController = TextEditingController();
  final _scrollController = ScrollController();

  String? _selectedAvatar;
  String _gender = '女';
  bool _isLoading = false;
  List<DialogueExample> _dialogueExamples = [];

  /// 当前正在编辑的模块索引（null = 未进入编辑模式）
  int? _editingSection;
  final _editingScrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    _editingScrollController.dispose();
    _nameController.dispose();
    _personalityController.dispose();
    _coreDesireController.dispose();
    _moralBoundaryController.dispose();
    _backgroundStoryController.dispose();
    _worldSettingController.dispose();
    _languageStyleController.dispose();
    _tabooTopicsController.dispose();
    _userNicknameController.dispose();
    _userPersonaController.dispose();
    _catchphrasesController.dispose();
    _openingLineController.dispose();
    _characterTagController.dispose();
    super.dispose();
  }

  /// 进入编辑模式 — 键盘弹出时只显示当前模块
  void _enterEditMode(int section) {
    if (_editingSection != section) {
      setState(() => _editingSection = section);
    }
  }

  /// 退出编辑模式 — 键盘收起时恢复完整列表
  void _exitEditMode() {
    if (_editingSection != null) {
      setState(() => _editingSection = null);
    }
  }

  Future<void> _createCharacter() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final userId = _getCurrentUserId();

      final character = AICharacter(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        gender: _gender,
        avatarUrl: _selectedAvatar,
        personality: _personalityController.text.trim(),
        coreDesire: _coreDesireController.text.trim(),
        moralBoundary: _moralBoundaryController.text.trim(),
        backgroundStory: _backgroundStoryController.text.trim().isNotEmpty
            ? _backgroundStoryController.text.trim()
            : null,
        createdAt: DateTime.now(),
        worldSetting: _worldSettingController.text.trim().isNotEmpty
            ? _worldSettingController.text.trim()
            : null,
        languageStyle: _languageStyleController.text.trim(),
        tabooTopics: _tabooTopicsController.text.trim().isNotEmpty
            ? _tabooTopicsController.text.trim()
            : null,
        userNickname: _userNicknameController.text.trim().isNotEmpty
            ? _userNicknameController.text.trim()
            : null,
        userPersona: _userPersonaController.text.trim().isNotEmpty
            ? _userPersonaController.text.trim()
            : null,
        catchphrases: _catchphrasesController.text.trim().isNotEmpty
            ? _catchphrasesController.text.trim()
            : null,
        openingLine: _openingLineController.text.trim().isNotEmpty
            ? _openingLineController.text.trim()
            : null,
        characterTag: _characterTagController.text.trim().isNotEmpty
            ? _characterTagController.text.trim()
            : null,
        dialogueExamples: _dialogueExamples,
        interactionConfig: const AIInteractionConfig(),
        age: AgeExtractor.extract(_backgroundStoryController.text.trim()) ??
            AgeExtractor.extract(_personalityController.text.trim()),
      );

      await storage.saveAICharacter(character);

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

  void _addDialogueExample() {
    if (_dialogueExamples.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加5个示例对话')),
      );
      return;
    }
    setState(() {
      _dialogueExamples.add(const DialogueExample(
        userMessage: '',
        aiResponse: '',
      ));
    });
  }

  void _removeDialogueExample(int index) {
    setState(() {
      _dialogueExamples.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 50;
    final isEditing = _editingSection != null && keyboardOpen;

    // 监听键盘收起 → 自动退出编辑模式
    if (!keyboardOpen && _editingSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _exitEditMode());
    }

    return PopScope(
      canPop: !isEditing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isEditing) {
          _exitEditMode();
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(isEditing ? _sectionTitles[_editingSection!] : '添加好友'),
          centerTitle: true,
          elevation: 0,
          leading: isEditing
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    _exitEditMode();
                    FocusScope.of(context).unfocus();
                  },
                )
              : null,
        ),
        body: isEditing
            ? _buildEditingMode(context, _editingSection!)
            : Form(
                key: _formKey,
                child: ListView(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(
                      left: 16, right: 16, top: 16, bottom: 600),
                  children: [
                    _buildAvatarSection(context),
                    const SizedBox(height: 16),

                    // 基本信息 — 默认展开
                    _buildCollapsibleSection(
                      context,
                      title: '基本信息',
                      icon: Icons.person_outline,
                      initiallyExpanded: true,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          onTap: () => _enterEditMode(0),
                          decoration: InputDecoration(
                            labelText: '名字',
                            hintText: '给你的好友取一个名字',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入名字';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Text('性别',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                                child: _buildGenderChip('女', Icons.female)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildGenderChip('男', Icons.male)),
                          ],
                        ),
                      ],
                    ),

                    // 性格设定 — 默认展开
                    _buildCollapsibleSection(
                      context,
                      title: '性格设定',
                      icon: Icons.psychology_outlined,
                      initiallyExpanded: true,
                      children: [
                        TextFormField(
                          onTap: () => _enterEditMode(1),
                          controller: _personalityController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: '性格描述',
                            hintText: '例如：温柔体贴，有些内向，喜欢倾听...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入性格描述';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),

                    // 关于TA — 默认展开
                    _buildCollapsibleSection(
                      context,
                      title: '关于TA',
                      icon: Icons.favorite_outline,
                      initiallyExpanded: true,
                      children: [
                        TextFormField(
                          onTap: () => _enterEditMode(2),
                          controller: _coreDesireController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'TA的心愿',
                            hintText: 'TA最想要什么？',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入TA的心愿';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(2),
                          controller: _moralBoundaryController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'TA的原则',
                            hintText: 'TA绝对不会做什么？',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '请输入TA的原则';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),

                    // 说话习惯 — 默认收起
                    _buildCollapsibleSection(
                      context,
                      title: '说话习惯（可选）',
                      icon: Icons.chat_bubble_outline,
                      initiallyExpanded: false,
                      children: [
                        TextFormField(
                          onTap: () => _enterEditMode(3),
                          controller: _catchphrasesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: '习惯用语',
                            hintText: '例如："真的吗？"、"哈哈哈"、"我觉得..."',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(3),
                          controller: _openingLineController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: '开场白',
                            hintText: 'TA第一次打招呼时会说什么？',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // TA的故事 — 默认收起
                    _buildCollapsibleSection(
                      context,
                      title: 'TA的故事（可选）',
                      icon: Icons.auto_stories_outlined,
                      initiallyExpanded: false,
                      children: [
                        TextFormField(
                          onTap: () => _enterEditMode(4),
                          controller: _backgroundStoryController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: 'TA的故事',
                            hintText: 'TA有什么样的过去？',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 高级设置 — 默认收起
                    _buildCollapsibleSection(
                      context,
                      title: '高级设置（可选）',
                      icon: Icons.tune,
                      initiallyExpanded: false,
                      children: [
                        TextFormField(
                          onTap: () => _enterEditMode(5),
                          controller: _worldSettingController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: '世界观设定',
                            hintText: 'TA生活在什么样的世界？现代都市、古代、未来...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(5),
                          controller: _languageStyleController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: '语言风格',
                            hintText: '例如：温柔体贴、活泼俏皮、幽默风趣...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(5),
                          controller: _tabooTopicsController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: '禁忌话题',
                            hintText: 'TA不会主动提起或深入讨论的话题...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(5),
                          controller: _characterTagController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: '外貌设定',
                            hintText: '发色、瞳色、脸型、体型、服饰等，如：银色长发、紫色瞳孔、瓜子脸、白色连衣裙',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(5),
                          controller: _userNicknameController,
                          decoration: InputDecoration(
                            labelText: '对用户的称呼',
                            hintText: 'TA怎么称呼你？例如：朋友、小伙伴、同学...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          onTap: () => _enterEditMode(5),
                          controller: _userPersonaController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: '你的人设（可选）',
                            hintText: '你在TA眼中是什么样的？例如：一个喜欢画画的大学生...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '示例对话',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _addDialogueExample,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('添加示例'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '添加示例对话可以让AI更好地模仿TA的说话方式',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._dialogueExamples.asMap().entries.map((entry) {
                          return _buildDialogueExampleCard(
                              entry.key, colorScheme);
                        }),
                      ],
                    ),

                    const SizedBox(height: 16),
                    _buildTipCard(context),
                    const SizedBox(height: 24),
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
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.onPrimary,
                                  ),
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
              ),
      ),
    );
  }

  static const _sectionTitles = [
    '基本信息',
    '性格设定',
    '关于TA',
    '说话习惯',
    'TA的故事',
    '高级设置',
  ];

  /// 编辑模式：只显示当前模块，铺满键盘上方空间
  Widget _buildEditingMode(BuildContext context, int section) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget content;

    switch (section) {
      case 0: // 基本信息
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '名字',
                hintText: '给你的好友取一个名字',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Text('性别',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildGenderChip('女', Icons.female)),
                const SizedBox(width: 12),
                Expanded(child: _buildGenderChip('男', Icons.male)),
              ],
            ),
          ],
        );
        break;
      case 1: // 性格设定
        content = TextFormField(
          controller: _personalityController,
          autofocus: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: '性格描述',
            hintText: '例如：温柔体贴，有些内向，喜欢倾听...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 2: // 关于TA
        content = Column(
          children: [
            TextFormField(
              controller: _coreDesireController,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: 'TA的心愿',
                hintText: 'TA最想要什么？',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _moralBoundaryController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: 'TA的原则',
                hintText: 'TA绝对不会做什么？',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
        break;
      case 3: // 说话习惯
        content = Column(
          children: [
            TextFormField(
              controller: _catchphrasesController,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: '习惯用语',
                hintText: '例如："真的吗？"、"哈哈哈"、"我觉得..."',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _openingLineController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: '开场白',
                hintText: 'TA第一次打招呼时会说什么？',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
        break;
      case 4: // TA的故事
        content = TextFormField(
          controller: _backgroundStoryController,
          autofocus: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: 'TA的故事',
            hintText: 'TA有什么样的过去？',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        break;
      case 5: // 高级设置
        content = Column(
          children: [
            TextFormField(
              controller: _worldSettingController,
              autofocus: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: '世界观设定',
                hintText: 'TA生活在什么样的世界？现代都市、古代、未来...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _languageStyleController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: '语言风格',
                hintText: '例如：温柔体贴、活泼俏皮、幽默风趣...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tabooTopicsController,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: '禁忌话题',
                hintText: 'TA不会主动提起或深入讨论的话题...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userNicknameController,
              decoration: InputDecoration(
                labelText: '对用户的称呼',
                hintText: 'TA怎么称呼你？',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );
        break;
      default:
        content = const SizedBox.shrink();
    }

    return SingleChildScrollView(
      controller: _editingScrollController,
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }

  Widget _buildCollapsibleSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool initiallyExpanded,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.15),
          ),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(icon, color: colorScheme.primary, size: 22),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          iconColor: colorScheme.primary,
          collapsedIconColor: colorScheme.onSurface.withOpacity(0.4),
          children: children,
        ),
      ),
    );
  }

  Widget _buildAvatarSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
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
              child: _selectedAvatar != null && _selectedAvatar!.isNotEmpty
                  ? Image.file(
                      File(_selectedAvatar!),
                      fit: BoxFit.cover,
                      width: 100,
                      height: 100,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildDefaultAvatar(context);
                      },
                    )
                  : _buildDefaultAvatar(context),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _pickAvatar(context),
            icon: Icon(Icons.camera_alt, size: 16, color: colorScheme.primary),
            label: Text(
              _selectedAvatar != null ? '更换头像' : '选择头像',
              style: TextStyle(color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _nameController.text.isNotEmpty
              ? _nameController.text.substring(0, 1)
              : '?',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildGenderChip(String label, IconData icon) {
    final selected = _gender == label;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _gender = label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
                size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogueExampleCard(int index, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '示例 ${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: colorScheme.error),
                onPressed: () => _removeDialogueExample(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: '用户说...',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (value) {
              if (_dialogueExamples.length > index) {
                _dialogueExamples[index] = DialogueExample(
                  userMessage: value,
                  aiResponse: _dialogueExamples[index].aiResponse,
                );
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'TA回复...',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (value) {
              if (_dialogueExamples.length > index) {
                _dialogueExamples[index] = DialogueExample(
                  userMessage: _dialogueExamples[index].userMessage,
                  aiResponse: value,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '设计建议',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '好的伙伴应该有清晰的性格和健康的价值观。设定原则是保护你们关系的重要防线。\n\n'
            '高级设置中的世界观、语言风格、示例对话可以让TA更加生动真实，建议认真填写。',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.6),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '选择头像',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                Icons.photo_library,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.camera_alt,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_selectedAvatar != null && _selectedAvatar!.isNotEmpty)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('清除头像'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedAvatar = null;
                  });
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      bool hasPermission = false;

      if (source == ImageSource.camera) {
        hasPermission = await PermissionService.hasCameraPermission();
        if (!hasPermission) {
          hasPermission = await PermissionService.requestCameraPermission();
        }
      } else {
        hasPermission = await PermissionService.hasStoragePermission();
        if (!hasPermission) {
          hasPermission = await PermissionService.requestStoragePermission();
        }
      }

      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要权限才能选择图片')),
          );
        }
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final persistentPath = await _copyToPersistentPath(pickedFile.path);
        setState(() {
          _selectedAvatar = persistentPath;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择失败: $e')),
        );
      }
    }
  }

  Future<String> _copyToPersistentPath(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/ai_avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
      // Generate a unique filename for new characters
      final filename = const Uuid().v4();
      final destPath = '${avatarDir.path}/$filename.$ext';
      await source.copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('复制头像失败: $e');
      return sourcePath;
    }
  }
}
