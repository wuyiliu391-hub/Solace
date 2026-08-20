import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../models/memory.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/emotion_engine.dart';
import '../../services/inner_thought_service.dart';
import '../../utils/avatar_resolver.dart';

/// 角色心理档案：把已经存在的情绪、欲望、记忆和内心独白集中呈现。
class CharacterPsychologyScreen extends StatefulWidget {
  const CharacterPsychologyScreen({super.key});

  @override
  State<CharacterPsychologyScreen> createState() =>
      _CharacterPsychologyScreenState();
}

class _CharacterPsychologyScreenState extends State<CharacterPsychologyScreen> {
  AICharacter? _character;
  List<AICharacter> _characters = const [];
  CharacterEmotion? _emotion;
  List<InnerThought> _thoughts = const [];
  List<Memory> _memories = const [];
  bool _loading = true;

  String get _userId {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.id : '';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? characterId]) async {
    final storage = context.read<LocalStorageRepository>();
    final characters = await storage.getAllAICharacters();
    if (characters.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final character = characters.firstWhere(
      (item) => item.id == characterId,
      orElse: () => _character == null
          ? characters.first
          : characters.firstWhere(
              (item) => item.id == _character!.id,
              orElse: () => characters.first,
            ),
    );
    final emotion = await EmotionEngine(storage).getCurrentEmotion(
      character: character,
      userId: _userId,
    );
    final thoughts = await InnerThoughtService(
      storage,
      EmotionEngine(storage),
    ).getThoughts(
      characterId: character.id,
      userId: _userId,
      limit: 30,
    );
    final memories = await storage.getMemories(
      characterId: character.id,
      userId: _userId,
      limit: 30,
    );
    if (!mounted) return;
    setState(() {
      _characters = characters;
      _character = character;
      _emotion = emotion;
      _thoughts = thoughts;
      _memories = memories;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色心理档案'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _character == null
              ? const Center(child: Text('还没有角色'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (_characters.length > 1) _characterPicker(scheme),
                      _profileHeader(scheme),
                      _emotionCard(scheme),
                      _thoughtCard(scheme),
                      _memoryCard(scheme),
                      _privacyNotice(scheme),
                    ],
                  ),
                ),
    );
  }

  Widget _characterPicker(ColorScheme scheme) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _characters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final character = _characters[index];
          return ChoiceChip(
            selected: character.id == _character!.id,
            label: Text(character.name),
            onSelected: (_) {
              setState(() => _loading = true);
              _load(character.id);
            },
          );
        },
      ),
    );
  }

  Widget _profileHeader(ColorScheme scheme) {
    final avatar = AvatarResolver.imageWidget(
      _character!.avatarUrl,
      width: 58,
      height: 58,
      fit: BoxFit.cover,
      onError: () => const Icon(Icons.person),
    );
    return Card(
      margin: const EdgeInsets.only(top: 16, bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 29,
              backgroundColor: scheme.primaryContainer,
              child: avatar ?? Icon(Icons.person, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_character!.name,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('这是基于互动事件形成的心理状态快照',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _character!.isOnline
                              ? const Color(0xFF43A047)
                              : scheme.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _character!.isOnline ? '在线' : '离线',
                        style: TextStyle(
                          fontSize: 11,
                          color: _character!.isOnline
                              ? const Color(0xFF388E3C)
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((_character!.currentStatus ?? '').isNotEmpty) ...[
                        Text(' · ', style: TextStyle(color: scheme.outline)),
                        Flexible(
                          child: Text(
                            _character!.currentStatus!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _emotionCard(ColorScheme scheme) {
    final emotion = _emotion!;
    final current = emotion.effectiveEmotion;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('TA 最近的心情', _formatSnapshotTime(emotion.updatedAt)),
            Row(
              children: [
                Icon(current.icon, color: current.color, size: 34),
                const SizedBox(width: 12),
                Text(current.label,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: current.color)),
                const Spacer(),
                Text('${(emotion.currentIntensity * 100).round()}%',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 14),
            _meter('情绪效价', (emotion.currentValence + 1) / 2, scheme.primary),
            _meter('唤醒程度', emotion.currentArousal, Colors.orange),
            _meter('孤独程度', emotion.loneliness, Colors.indigo),
            if (emotion.trigger?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('触发原因：${emotion.trigger}',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meter(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
              width: 72,
              child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                minHeight: 6,
                color: color,
                backgroundColor: color.withValues(alpha: .12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
              width: 34,
              child: Text('${(value * 100).round()}%',
                  style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _thoughtCard(ColorScheme scheme) {
    final latest =
        _thoughts.where((item) => item.type == InnerThoughtType.ai).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('TA 留下的内心独白', '${latest.length} 条记录'),
            if (latest.isEmpty)
              Text('还没有可展示的内心独白。只有角色产生并保存了反思记录，这里才会出现内容。',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6))
            else
              ...latest.take(3).map((thought) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('“${thought.content}”',
                        style: const TextStyle(height: 1.55)),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _memoryCard(ColorScheme scheme) {
    final counts = <MemoryType, int>{};
    for (final memory in _memories) {
      counts[memory.type] = (counts[memory.type] ?? 0) + 1;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('TA 记住了什么', '${_memories.length} 条近期记忆'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: counts.entries
                  .map((entry) => Chip(
                        avatar: const Icon(Icons.bookmark_outline, size: 16),
                        label:
                            Text('${_memoryLabel(entry.key)} ${entry.value}'),
                      ))
                  .toList(),
            ),
            if (_memories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_memories.first.summary ?? _memories.first.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }

  String _memoryLabel(MemoryType type) {
    switch (type) {
      case MemoryType.preference:
        return '偏好';
      case MemoryType.emotion:
        return '情绪';
      case MemoryType.milestone:
        return '节点';
      case MemoryType.state:
        return '状态';
      case MemoryType.reflection:
        return '反思';
      case MemoryType.rollingSummary:
        return '摘要';
      case MemoryType.conversation:
        return '对话';
    }
  }

  Widget _privacyNotice(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '这里展示的是事件驱动的历史快照，不代表角色正在实时思考，也不等同于顶部的在线/离线状态。数据来自本地情绪引擎、记忆和内心独白；它是理解 TA 的窗口，不是绝对真相。',
              style: TextStyle(
                  fontSize: 11, color: scheme.onSurfaceVariant, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSnapshotTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.isNegative || diff.inMinutes < 1) return '刚刚记录';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前记录';
    if (diff.inDays < 1) return '${diff.inHours}小时前记录';
    if (diff.inDays < 7) return '${diff.inDays}天前记录';
    return '${time.month}/${time.day} 记录';
  }
}
