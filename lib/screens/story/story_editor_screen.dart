import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../models/ai_character.dart';
import '../../models/story_book.dart';
import '../../repositories/local_storage_repository.dart';
import '../../widgets/cover_picker.dart';

/// 故事书 创建 / 编辑
class StoryEditorScreen extends StatefulWidget {
  final String userId;
  final StoryBook? book;

  const StoryEditorScreen({super.key, required this.userId, this.book});

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _synopsisCtrl;
  late final TextEditingController _worldCtrl;
  String? _coverUrl;
  StoryGenre _genre = StoryGenre.free;
  NarratorRole _narrator = NarratorRole.protagonist;
  final Set<String> _selectedCharacterIds = {};
  List<AICharacter> _allCharacters = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _titleCtrl = TextEditingController(text: b?.title ?? '');
    _synopsisCtrl = TextEditingController(text: b?.synopsis ?? '');
    _worldCtrl = TextEditingController(text: b?.worldSetting ?? '');
    _coverUrl = b?.coverUrl;
    _genre = b?.genre ?? StoryGenre.free;
    _narrator = b?.narratorRole ?? NarratorRole.protagonist;
    if (b != null) _selectedCharacterIds.addAll(b.participantCharacterIds);
    _loadCharacters();
  }

  Future<void> _loadCharacters() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final chars = await storage.getAllAICharacters();
    if (mounted) setState(() => _allCharacters = chars.where((c) => !c.isHidden).toList());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _synopsisCtrl.dispose();
    _worldCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写故事标题')),
      );
      return;
    }
    setState(() => _saving = true);
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final now = DateTime.now();
    final existing = widget.book;
    final book = StoryBook(
      id: existing?.id ?? const Uuid().v4(),
      userId: widget.userId,
      title: _titleCtrl.text.trim(),
      coverUrl: _coverUrl,
      synopsis: _synopsisCtrl.text.trim(),
      worldSetting: _worldCtrl.text.trim(),
      genre: _genre,
      narratorRole: _narrator,
      participantCharacterIds: _selectedCharacterIds.toList(),
      currentSaveId: existing?.currentSaveId,
      isArchived: existing?.isArchived ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastSegmentPreview: existing?.lastSegmentPreview,
    );
    await storage.saveStoryBook(book);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book == null ? '新建故事' : '编辑故事'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CoverPicker(
            coverUrl: _coverUrl,
            onSelected: (v) => setState(() => _coverUrl = v),
          ),
          const SizedBox(height: 20),
          _label('标题'),
          TextField(
            controller: _titleCtrl,
            decoration: _inputDeco('给故事起个名字'),
          ),
          const SizedBox(height: 16),
          _label('简介'),
          TextField(
            controller: _synopsisCtrl,
            maxLines: 2,
            decoration: _inputDeco('一句话概括故事'),
          ),
          const SizedBox(height: 16),
          _label('世界观设定'),
          TextField(
            controller: _worldCtrl,
            maxLines: 5,
            decoration: _inputDeco('时代背景、地点、规则、氛围……AI 会据此展开剧情'),
          ),
          const SizedBox(height: 20),
          _label('创作风格'),
          Wrap(
            spacing: 8,
            children: StoryGenre.values.map((g) {
              return ChoiceChip(
                label: Text(g.label),
                selected: _genre == g,
                onSelected: (_) => setState(() => _genre = g),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _label('初始叙事视角'),
          Wrap(
            spacing: 8,
            children: NarratorRole.values.map((r) {
              return ChoiceChip(
                label: Text('${r.label}视角'),
                selected: _narrator == r,
                onSelected: (_) => setState(() => _narrator = r),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _label('登场人物（从通讯录导入）'),
          const SizedBox(height: 8),
          _buildCharacterPicker(cs),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCharacterPicker(ColorScheme cs) {
    if (_allCharacters.isEmpty) {
      return Text('暂无可导入的角色',
          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.4)));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allCharacters.map((c) {
        final selected = _selectedCharacterIds.contains(c.id);
        return FilterChip(
          avatar: CircleAvatar(
            backgroundColor: cs.primaryContainer,
            child: Text(c.name.isNotEmpty ? c.name.characters.first : '?',
                style: const TextStyle(fontSize: 12)),
          ),
          label: Text(c.name),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) {
              _selectedCharacterIds.add(c.id);
            } else {
              _selectedCharacterIds.remove(c.id);
            }
          }),
        );
      }).toList(),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}
