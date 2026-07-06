import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_activity_event.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_activity_service.dart';

/// AI 活动动态流页面
class AIActivityFeedScreen extends StatefulWidget {
  const AIActivityFeedScreen({super.key});

  @override
  State<AIActivityFeedScreen> createState() => _AIActivityFeedScreenState();
}

class _AIActivityFeedScreenState extends State<AIActivityFeedScreen> {
  List<AIActivityEvent> _events = [];
  List<AICharacter> _characters = [];
  String? _selectedCharacterId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    final service = AIActivityService(storage);
    final characters = await storage.getAllAICharacters();
    final events = await service.getTodayActivities(
      userId: userId,
      characterId: _selectedCharacterId,
    );

    if (!mounted) return;
    setState(() {
      _characters = characters;
      _events = events;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('AI 动态'),
        centerTitle: true,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCharacterSelector(cs),
                Expanded(
                  child:
                      _events.isEmpty ? _buildEmptyState(cs) : _buildFeed(cs),
                ),
              ],
            ),
    );
  }

  Widget _buildCharacterSelector(ColorScheme cs) {
    if (_characters.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _characters.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final character = isAll ? null : _characters[index - 1];
          final selected = isAll
              ? _selectedCharacterId == null
              : _selectedCharacterId == character!.id;
          return ChoiceChip(
            selected: selected,
            label: Text(isAll ? '全部角色' : character!.name),
            avatar: isAll
                ? const Icon(Icons.groups_rounded, size: 16)
                : CircleAvatar(
                    radius: 10,
                    backgroundImage: character!.avatarUrl != null
                        ? NetworkImage(character.avatarUrl!)
                        : null,
                    child: character.avatarUrl == null
                        ? const Icon(Icons.person, size: 12)
                        : null,
                  ),
            onSelected: (_) {
              setState(() {
                _selectedCharacterId = isAll ? null : character!.id;
                _loading = true;
              });
              _loadActivities();
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 64, color: cs.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('今天还没有动态',
              style: TextStyle(
                  fontSize: 16, color: cs.onSurface.withOpacity(0.5))),
          const SizedBox(height: 8),
          Text('和 AI 聊天后，这里会显示TA的动态',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildFeed(ColorScheme cs) {
    return RefreshIndicator(
      onRefresh: _loadActivities,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _events.length,
        itemBuilder: (context, index) {
          final event = _events[index];
          final isFirst = index == 0;
          final isLast = index == _events.length - 1;
          return _buildEventCard(cs, event, isFirst, isLast);
        },
      ),
    );
  }

  Widget _buildEventCard(
      ColorScheme cs, AIActivityEvent event, bool isFirst, bool isLast) {
    final color = event.color;
    final timeStr = DateFormat('HH:mm').format(event.createdAt);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间线
          SizedBox(
            width: 48,
            child: Column(
              children: [
                // 时间
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                // 圆点
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                // 连接线
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: cs.outlineVariant.withOpacity(0.3),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧卡片
          Expanded(
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(0.2),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      Icon(event.icon, size: 18, color: event.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(event.title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface)),
                      ),
                      // 角色头像
                      if (event.characterAvatar != null &&
                          event.characterAvatar!.isNotEmpty)
                        ClipOval(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: Image.network(
                              event.characterAvatar!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _miniAvatar(cs),
                            ),
                          ),
                        )
                      else
                        _miniAvatar(cs),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 副标题
                  Text(event.subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          height: 1.4)),
                  // 详情（可展开）
                  if (event.detail != null && event.detail!.length > 50) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _showDetail(event),
                      child: Text(
                        '查看详情',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAvatar(ColorScheme cs) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, size: 12, color: cs.primary),
    );
  }

  Color _getTypeColor(AIActivityType type, ColorScheme cs) {
    switch (type) {
      case AIActivityType.emotionChange:
        return const Color(0xFF9C27B0); // purple
      case AIActivityType.innerThought:
        return const Color(0xFF2196F3); // blue
      case AIActivityType.momentPost:
        return const Color(0xFF4CAF50); // green
      case AIActivityType.memoryFormed:
        return const Color(0xFFFF9800); // orange
      case AIActivityType.evolution:
        return const Color(0xFF009688); // teal
      case AIActivityType.letterSent:
        return const Color(0xFFE91E63); // pink
      case AIActivityType.milestone:
        return const Color(0xFFF44336); // red
      case AIActivityType.weatherMood:
        return const Color(0xFF00BCD4); // cyan
    }
  }

  void _showDetail(AIActivityEvent event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(event.icon, size: 22, color: event.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(event.title,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(event.detail!,
                  style: TextStyle(
                      fontSize: 15, color: cs.onSurfaceVariant, height: 1.6)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
