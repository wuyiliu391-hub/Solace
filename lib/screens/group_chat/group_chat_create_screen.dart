import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../blocs/group_chat/group_chat_bloc.dart';
import '../../blocs/group_chat/group_chat_event.dart';
import '../../blocs/group_chat/group_chat_state.dart';
import '../../models/ai_character.dart' hide ReplyMode;
import '../../models/group_chat_session.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/scenario_service.dart';

class GroupChatCreateScreen extends StatefulWidget {
  const GroupChatCreateScreen({super.key});

  @override
  State<GroupChatCreateScreen> createState() => _GroupChatCreateScreenState();
}

class _GroupChatCreateScreenState extends State<GroupChatCreateScreen> {
  final _nameController = TextEditingController();
  final List<ScenarioTemplate> _templates = ScenarioService.getTemplates();

  List<AICharacter> _allCharacters = [];
  final List<String> _selectedCharacterIds = [];
  int _currentStep = 0;
  String? _selectedTemplateId;
  String? _customScenario;
  TavernMode _tavernMode = TavernMode.group;
  TavernImmersion _immersion = TavernImmersion.daily;
  TavernInteractionFrequency _interactionFrequency =
      TavernInteractionFrequency.natural;
  ReplyMode _replyMode = ReplyMode.sequential;
  bool _isLoadingCharacters = true;

  @override
  void initState() {
    super.initState();
    _loadCharacters();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCharacters() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final characters = await storage.getAllAICharacters();
      if (!mounted) return;
      setState(() {
        _allCharacters = characters;
        _isLoadingCharacters = false;
      });
    } catch (e, stack) {
      debugPrint('GroupChatCreateScreen load characters failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _allCharacters = [];
        _isLoadingCharacters = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('联系人加载失败：$e')),
      );
    }
  }

  String get _currentUserId {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) return authState.user.id;
    return '';
  }

  bool get _canContinueStepOne => _nameController.text.trim().isNotEmpty;

  bool get _canCreate {
    return _canContinueStepOne && _selectedCharacterIds.length >= 2;
  }

  List<AICharacter> get _selectedParticipants {
    return _selectedCharacterIds
        .map((id) => _allCharacters.where((c) => c.id == id).toList())
        .where((items) => items.isNotEmpty)
        .map((items) => items.first)
        .toList();
  }

  void _onCreate() {
    if (!_canCreate) return;

    final selectedParticipants = _selectedParticipants;

    String? scenario;
    String? scenarioTemplate;

    if (_selectedTemplateId == 'custom') {
      scenario = _customScenario;
    } else if (_selectedTemplateId != null) {
      scenarioTemplate = _selectedTemplateId;
    }

    context.read<GroupChatBloc>().add(GroupChatCreateSession(
          userId: _currentUserId,
          name: _nameController.text.trim(),
          scenario: scenario,
          scenarioTemplate: scenarioTemplate,
          participants: selectedParticipants,
          replyMode: _replyMode,
          tavernMode: _tavernMode,
          immersion: _immersion,
          interactionFrequency: _interactionFrequency,
        ));
  }

  void _showCustomScenarioDialog() {
    final controller = TextEditingController(text: _customScenario ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义场景'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '描述你想要的场景氛围...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _customScenario = controller.text.trim().isEmpty
                    ? null
                    : controller.text.trim();
                _selectedTemplateId = 'custom';
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('创建酒馆'),
        centerTitle: true,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep == 1) {
              setState(() => _currentStep = 0);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: BlocListener<GroupChatBloc, GroupChatState>(
        listener: (context, state) {
          if (state is GroupChatSessionCreated) {
            Navigator.pop(context, state.session);
          } else if (state is GroupChatError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepHeader(colorScheme),
              const SizedBox(height: 24),
              if (_currentStep == 0) ...[
                _buildNameInput(colorScheme),
                const SizedBox(height: 28),
                _buildModeSection(colorScheme),
                const SizedBox(height: 28),
                _buildScenarioSection(colorScheme),
                const SizedBox(height: 36),
                _buildNextButton(colorScheme),
              ] else ...[
                _buildCharacterSection(colorScheme),
                const SizedBox(height: 24),
                _buildInviteOrderSection(colorScheme),
                const SizedBox(height: 28),
                _buildImmersionSection(colorScheme),
                const SizedBox(height: 28),
                _buildInteractionSection(colorScheme),
                const SizedBox(height: 28),
                _buildReplyModeSection(colorScheme),
                const SizedBox(height: 36),
                _buildCreateButton(colorScheme),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${_currentStep + 1}',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStep == 0 ? '第 1 步 / 共 2 步' : '第 2 步 / 共 2 步',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentStep == 0 ? '先定下这间酒馆的样子' : '邀请联系人入场开张',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameInput(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '酒馆名称',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '给你的酒馆起个名字',
            prefixIcon: const Icon(Icons.storefront),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择酒馆玩法',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '@ 点名会作为所有玩法的辅助能力保留',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 12),
        _buildModeCard(
          colorScheme,
          mode: TavernMode.group,
          icon: Icons.groups_rounded,
          title: '群聊',
          subtitle: '大家一起回应你',
        ),
        const SizedBox(height: 10),
        _buildModeCard(
          colorScheme,
          mode: TavernMode.story,
          icon: Icons.auto_stories_rounded,
          title: '剧情',
          subtitle: '像小说一样推进',
        ),
        const SizedBox(height: 10),
        _buildModeCard(
          colorScheme,
          mode: TavernMode.observe,
          icon: Icons.visibility_rounded,
          title: '旁观',
          subtitle: '看他们自己聊',
        ),
      ],
    );
  }

  Widget _buildModeCard(
    ColorScheme colorScheme, {
    required TavernMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _tavernMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tavernMode = mode;
          if (mode == TavernMode.story) {
            _interactionFrequency = TavernInteractionFrequency.gentle;
          } else if (mode == TavernMode.observe) {
            _interactionFrequency = TavernInteractionFrequency.vivid;
          } else {
            _interactionFrequency = TavernInteractionFrequency.natural;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withOpacity(0.55)
              : colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline.withOpacity(0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选择场景',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '选择一个场景模板来营造氛围',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _templates.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index < _templates.length) {
                final template = _templates[index];
                final isSelected = _selectedTemplateId == template.id;
                return _buildScenarioCard(
                  colorScheme,
                  icon: template.icon,
                  name: template.name,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedTemplateId = isSelected ? null : template.id;
                    });
                  },
                );
              }
              final isCustomSelected = _selectedTemplateId == 'custom';
              return _buildScenarioCard(
                colorScheme,
                icon: '',
                name: '自定义',
                isSelected: isCustomSelected,
                subtitle: _customScenario != null ? '已设置' : null,
                onTap: _showCustomScenarioDialog,
                iconWidget: const Icon(Icons.edit, size: 28),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScenarioCard(
    ColorScheme colorScheme, {
    required String icon,
    required String name,
    required bool isSelected,
    String? subtitle,
    required VoidCallback onTap,
    Widget? iconWidget,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.15),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget ?? Text(icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNextButton(ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: _canContinueStepOne
            ? () => setState(() => _currentStep = 1)
            : null,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          _canContinueStepOne ? '下一步：邀请角色' : '先填写酒馆名称',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildCharacterSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '邀请联系人',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _selectedCharacterIds.length >= 2
                    ? colorScheme.primaryContainer
                    : colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_selectedCharacterIds.length} 已选',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _selectedCharacterIds.length >= 2
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '从通讯录里邀请已有角色，选择顺序就是初始发言顺序',
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 12),
        _isLoadingCharacters
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            : _allCharacters.isEmpty
                ? _buildEmptyCharacters(colorScheme)
                : _buildCharacterGrid(colorScheme),
      ],
    );
  }

  Widget _buildEmptyCharacters(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 8),
          Text(
            '还没有可以邀请的角色',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '先创建你的第一个联系人吧',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface.withOpacity(0.45),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/character_create'),
            icon: const Icon(Icons.add),
            label: const Text('去创建角色'),
          ),
        ],
      ),
    );
  }

  Widget _buildCharacterGrid(ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: _allCharacters.length,
      itemBuilder: (context, index) {
        final character = _allCharacters[index];
        final isSelected = _selectedCharacterIds.contains(character.id);
        return _buildCharacterCard(colorScheme, character, isSelected);
      },
    );
  }

  Widget _buildCharacterCard(
    ColorScheme colorScheme,
    AICharacter character,
    bool isSelected,
  ) {
    final displayName = character.userNickname ?? character.name;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedCharacterIds.remove(character.id);
          } else {
            _selectedCharacterIds.add(character.id);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.5)
              : colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _buildAvatar(colorScheme, character, 28),
                if (isSelected)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                displayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface.withOpacity(0.8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ColorScheme colorScheme, AICharacter character, double radius) {
    final displayName = character.userNickname ?? character.name;

    if (character.avatarUrl == null || character.avatarUrl!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.primaryContainer,
        child: Text(
          displayName.isNotEmpty ? displayName.substring(0, 1) : '?',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: radius * 0.7,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (character.avatarUrl!.startsWith('/') ||
        character.avatarUrl!.startsWith('C:') ||
        character.avatarUrl!.contains('\\')) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(character.avatarUrl!)),
        onBackgroundImageError: (error, stackTrace) {},
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(character.avatarUrl!),
      onBackgroundImageError: (error, stackTrace) {},
    );
  }

  Widget _buildInviteOrderSection(ColorScheme colorScheme) {
    final participants = _selectedParticipants;
    if (participants.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发言顺序',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '角色会按你邀请他们的顺序轮流发言',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 12),
          ...participants.asMap().entries.map((entry) {
            final index = entry.key;
            final character = entry.value;
            final name = character.userNickname ?? character.name;
            return Padding(
              padding: EdgeInsets.only(bottom: index == participants.length - 1 ? 0 : 8),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    '邀请顺序',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.38),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildImmersionSection(ColorScheme colorScheme) {
    final options = [
      (TavernImmersion.quiet, '安静', '最多 1 人回应'),
      (TavernImmersion.daily, '日常', '最多 2 人回应'),
      (TavernImmersion.lively, '热闹', '最多 3 人回应'),
      (TavernImmersion.carnival, '狂欢', '4~5 条回应'),
    ];
    return _buildChoiceSection<TavernImmersion>(
      colorScheme,
      title: '沉浸度',
      subtitle: '决定每轮对话有多丰富',
      selected: _immersion,
      options: options,
      onSelected: (value) => setState(() => _immersion = value),
    );
  }

  Widget _buildInteractionSection(ColorScheme colorScheme) {
    final options = [
      (TavernInteractionFrequency.gentle, '轻轻接话', '偶尔互相接一句'),
      (TavernInteractionFrequency.natural, '自然互动', '有真实群聊感'),
      (TavernInteractionFrequency.vivid, '热烈聊天', '像热闹小世界'),
    ];
    return _buildChoiceSection<TavernInteractionFrequency>(
      colorScheme,
      title: '角色互动',
      subtitle: '控制角色之间互相接话的频率',
      selected: _interactionFrequency,
      options: options,
      onSelected: (value) => setState(() => _interactionFrequency = value),
    );
  }

  Widget _buildChoiceSection<T>(
    ColorScheme colorScheme, {
    required String title,
    required String subtitle,
    required T selected,
    required List<(T, String, String)> options,
    required ValueChanged<T> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final value = option.$1;
            final isSelected = selected == value;
            return GestureDetector(
              onTap: () => onSelected(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: options.length == 4 ? 76 : 104,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer.withOpacity(0.6)
                      : colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outline.withOpacity(0.12),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      option.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.$3,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildReplyModeSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成方式',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildReplyModeCard(
                colorScheme,
                icon: Icons.bolt,
                title: '群聊快闪',
                subtitle: '多角色同时回复，氛围感拉满',
                isRecommended: false,
                isSelected: _replyMode == ReplyMode.flash,
                onTap: () => setState(() => _replyMode = ReplyMode.flash),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildReplyModeCard(
                colorScheme,
                icon: Icons.format_list_numbered,
                title: '逐个回复',
                subtitle: '角色依次发言，更有秩序',
                isRecommended: true,
                isSelected: _replyMode == ReplyMode.sequential,
                onTap: () => setState(() => _replyMode = ReplyMode.sequential),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReplyModeCard(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isRecommended,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withOpacity(0.5)
              : colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.5),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '推荐',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton(ColorScheme colorScheme) {
    return BlocBuilder<GroupChatBloc, GroupChatState>(
      builder: (context, state) {
        final isLoading = state is GroupChatLoading;
        final name = _nameController.text.trim();
        final buttonText = name.isEmpty
            ? '先填写酒馆名称'
            : _selectedCharacterIds.length < 2
                ? '至少选择 2 位角色'
                : '开张营业！';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: (_canCreate && !isLoading) ? _onCreate : null,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        buttonText,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '酒馆只带入角色核心设定和关系定义，不会公开单聊里的私密记忆。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.45),
              ),
            ),
          ],
        );
      },
    );
  }
}
