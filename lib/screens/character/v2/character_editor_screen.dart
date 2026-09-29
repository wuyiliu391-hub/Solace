// 【对标来源：SillyTavern-1.18.0 — index.html:6039 #form_create 角色编辑表单】
// 1:1 转译自 SillyTavern 角色创建/编辑表单为 Flutter 页面

import "package:flutter/material.dart";
import "../../../models/character_card_v2.dart";

/// 角色编辑页面 V2（对标 SillyTavern #form_create）
class CharacterEditorScreen extends StatefulWidget {
  final String? characterId;
  final CharacterCardV2? initialCard;

  const CharacterEditorScreen({
    super.key,
    this.characterId,
    this.initialCard,
  });

  @override
  State<CharacterEditorScreen> createState() => _CharacterEditorScreenState();
}

class _CharacterEditorScreenState extends State<CharacterEditorScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _personalityController;
  late TextEditingController _scenarioController;
  late TextEditingController _firstMesController;
  late TextEditingController _mesExampleController;
  late TextEditingController _creatorNotesController;
  late TextEditingController _systemPromptController;
  late TextEditingController _postHistoryInstructionsController;
  late TextEditingController _creatorController;
  late TextEditingController _tagsController;
  late TextEditingController _characterVersionController;

  double _talkativeness = 0.5;
  bool _fav = false;
  String? _worldName;
  List<String> _alternateGreetings = [];
  bool _showAdvanced = false;
  bool _showDescription = true;

  @override
  void initState() {
    super.initState();
    final card = widget.initialCard;
    _nameController = TextEditingController(text: card?.name ?? '');
    _descriptionController = TextEditingController(text: card?.description ?? '');
    _personalityController = TextEditingController(text: card?.personality ?? '');
    _scenarioController = TextEditingController(text: card?.scenario ?? '');
    _firstMesController = TextEditingController(text: card?.firstMes ?? '');
    _mesExampleController = TextEditingController(text: card?.mesExample ?? '');
    _creatorNotesController = TextEditingController(text: card?.creatorNotes ?? '');
    _systemPromptController = TextEditingController(text: card?.systemPrompt ?? '');
    _postHistoryInstructionsController = TextEditingController(text: card?.postHistoryInstructions ?? '');
    _creatorController = TextEditingController(text: card?.creator ?? '');
    _tagsController = TextEditingController(text: card?.tags.join(', ') ?? '');
    _characterVersionController = TextEditingController(text: card?.characterVersion ?? '');
    if (card != null) {
      _talkativeness = card.extensions.talkativeness;
      _fav = card.extensions.fav;
      _worldName = card.extensions.world;
      _alternateGreetings = List.from(card.alternateGreetings);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _firstMesController.dispose();
    _mesExampleController.dispose();
    _creatorNotesController.dispose();
    _systemPromptController.dispose();
    _postHistoryInstructionsController.dispose();
    _creatorController.dispose();
    _tagsController.dispose();
    _characterVersionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.characterId != null ? '编辑角色' : '创建角色'),
        actions: [
          IconButton(
            icon: Icon(_fav ? Icons.star : Icons.star_border, color: _fav ? Colors.amber : null),
            onPressed: () => setState(() => _fav = !_fav),
          ),
          IconButton(icon: const Icon(Icons.check), onPressed: _saveCharacter),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatarSection(cs),
            const SizedBox(height: 16),
            _buildTextField(cs: cs, controller: _nameController, label: '角色名称', hint: '为此角色命名', required: true),
            const SizedBox(height: 12),
            _buildTextField(cs: cs, controller: _tagsController, label: '标签', hint: '用逗号分隔标签'),
            const SizedBox(height: 12),
            _buildTextField(cs: cs, controller: _characterVersionController, label: '版本'),
            const SizedBox(height: 16),
            _buildSectionHeader('创建者备注', Icons.note, cs: cs),
            _buildTextField(cs: cs, controller: _creatorNotesController, hint: '创建者备注', maxLines: 3),
            const SizedBox(height: 16),
            _buildSectionHeader('角色描述', Icons.description, cs: cs,
              onToggle: () => setState(() => _showDescription = !_showDescription), isExpanded: _showDescription),
            if (_showDescription)
              _buildTextField(cs: cs, controller: _descriptionController, hint: '身体/心理特征、背景故事...', maxLines: 8),
            const SizedBox(height: 16),
            _buildSectionHeader('人格', Icons.psychology, cs: cs),
            _buildTextField(cs: cs, controller: _personalityController, hint: '人格简述...', maxLines: 3),
            const SizedBox(height: 16),
            _buildSectionHeader('场景', Icons.theater_comedy, cs: cs),
            _buildTextField(cs: cs, controller: _scenarioController, hint: '交互背景/场景设定...', maxLines: 3),
            const SizedBox(height: 16),
            _buildSectionHeader('开场白', Icons.chat_bubble_outline, cs: cs),
            _buildTextField(cs: cs, controller: _firstMesController, hint: '角色的第一条消息...', maxLines: 5),
            const SizedBox(height: 16),
            _buildAlternateGreetingsSection(cs),
            const SizedBox(height: 16),
            _buildSectionHeader('对话示例', Icons.forum, cs: cs),
            _buildTextField(cs: cs, controller: _mesExampleController, hint: '用 <START> 分隔多段示例对话...', maxLines: 8),
            const SizedBox(height: 16),
            _buildAdvancedSection(cs),
            const SizedBox(height: 24),
            _buildTextField(cs: cs, controller: _creatorController, label: '创建者', hint: '创建者名称/联系方式'),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection(ColorScheme cs) {
    return Center(
      child: GestureDetector(
        onTap: () {},
        child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: cs.outlineVariant,
            border: Border.all(color: cs.onSurfaceVariant, width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo, size: 32, color: cs.onSurfaceVariant),
              const SizedBox(height: 4),
              Text('点击选择头像', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required ColorScheme cs, required TextEditingController controller, String? label, String? hint, int maxLines = 1, bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              if (required) const Text(' *', style: TextStyle(color: Colors.red)),
            ]),
          ),
        TextField(
          controller: controller, maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint, hintStyle: TextStyle(color: cs.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {required ColorScheme cs, VoidCallback? onToggle, bool isExpanded = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface)),
        if (onToggle != null) ...[
          const Spacer(),
          GestureDetector(
            onTap: onToggle,
            child: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: cs.onSurfaceVariant),
          ),
        ],
      ]),
    );
  }

  Widget _buildAlternateGreetingsSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.waving_hand, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('备用问候', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => setState(() => _alternateGreetings.add(''))),
        ]),
        ...List.generate(_alternateGreetings.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: _alternateGreetings[index]),
                  onChanged: (value) => _alternateGreetings[index] = value,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: '备用问候 ${index + 1}', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                ),
              ),
              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _alternateGreetings.removeAt(index))),
            ]),
          );
        }),
      ],
    );
  }

  Widget _buildAdvancedSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Row(children: [
            Icon(Icons.tune, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('高级定义', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const Spacer(),
            Icon(_showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: cs.onSurfaceVariant),
          ]),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 12),
          _buildTextField(cs: cs, controller: _systemPromptController, label: '系统提示词', hint: '系统级提示词...', maxLines: 5),
          const SizedBox(height: 12),
          _buildTextField(cs: cs, controller: _postHistoryInstructionsController, label: '历史后指令', hint: '在历史记录后注入的指令...', maxLines: 5),
          const SizedBox(height: 12),
          Row(children: [
            Text('健谈度: ${(_talkativeness * 100).toInt()}%', style: const TextStyle(fontSize: 13)),
            Expanded(child: Slider(value: _talkativeness, min: 0, max: 1, divisions: 20, onChanged: (v) => setState(() => _talkativeness = v))),
          ]),
        ],
      ],
    );
  }

  void _saveCharacter() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入角色名称')));
      return;
    }
    final card = CharacterCardV2(
      name: _nameController.text.trim(),
      description: _descriptionController.text,
      characterVersion: _characterVersionController.text,
      personality: _personalityController.text,
      scenario: _scenarioController.text,
      firstMes: _firstMesController.text,
      mesExample: _mesExampleController.text,
      creatorNotes: _creatorNotesController.text,
      tags: _tagsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      systemPrompt: _systemPromptController.text,
      postHistoryInstructions: _postHistoryInstructionsController.text,
      creator: _creatorController.text,
      alternateGreetings: _alternateGreetings.where((e) => e.isNotEmpty).toList(),
      extensions: CharacterExtensions(talkativeness: _talkativeness, fav: _fav, world: _worldName),
    );
    Navigator.pop(context, card);
  }
}
