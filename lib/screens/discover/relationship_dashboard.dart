import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../models/ai_character.dart';
import '../../models/character_emotion.dart';
import '../../models/intimacy_event.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/emotion_engine.dart';
import '../../services/growth_data_service.dart';
import '../../utils/avatar_resolver.dart';

/// 关系温度仪表盘
class RelationshipDashboard extends StatefulWidget {
  const RelationshipDashboard({super.key});

  @override
  State<RelationshipDashboard> createState() => _RelationshipDashboardState();
}

class _RelationshipDashboardState extends State<RelationshipDashboard> {
  AICharacter? _character;
  List<AICharacter> _characters = [];
  String? _selectedCharacterId;
  CharacterEmotion? _emotion;
  int _intimacyLevel = 0;
  int _todayDelta = 0;
  List<IntimacyEvent> _recentEvents = [];
  List<_DailyIntimacy> _weekData = [];
  int _daysSinceFirstChat = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final storage = context.read<LocalStorageRepository>();
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    final characters = await storage.getAllAICharacters();
    if (characters.isEmpty) {
      if (mounted) {
        setState(() {
          _characters = [];
          _character = null;
          _loading = false;
        });
      }
      return;
    }

    final selectedCharacter = characters.firstWhere(
      (c) => c.id == _selectedCharacterId,
      orElse: () => characters.first,
    );
    final selectedCharacterId = selectedCharacter.id;

    final engine = EmotionEngine(storage);
    final emotion = await engine.getCurrentEmotion(
      character: selectedCharacter,
      userId: userId,
    );

    final sessions = await storage.getChatSessions(userId);
    final characterSessions =
        sessions.where((s) => s.aiCharacterId == selectedCharacter.id).toList();

    int maxIntimacy = 0;
    DateTime? earliestDate;
    final events = <IntimacyEvent>[];

    for (final session in characterSessions) {
      if (session.intimacyLevel > maxIntimacy) {
        maxIntimacy = session.intimacyLevel;
      }
      if (earliestDate == null || session.createdAt.isBefore(earliestDate)) {
        earliestDate = session.createdAt;
      }
      final sessionEvents = await storage.getIntimacyEvents(
        session.id,
        limit: 100,
      );
      events.addAll(
        sessionEvents
            .where((event) => event.characterId == selectedCharacter.id),
      );
    }

    events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final todayDelta = _todayDeltaFromEvents(events);
    final weekData = _buildWeekData(events);
    final daysSince = earliestDate != null
        ? DateTime.now().difference(earliestDate).inDays
        : 0;

    if (!mounted) return;
    setState(() {
      _characters = characters;
      _selectedCharacterId = selectedCharacterId;
      _character = selectedCharacter;
      _emotion = emotion;
      _intimacyLevel = maxIntimacy;
      _todayDelta = todayDelta;
      _recentEvents = events.take(20).toList();
      _weekData = weekData;
      _daysSinceFirstChat = daysSince;
      _loading = false;
    });
  }

  int _todayDeltaFromEvents(List<IntimacyEvent> events) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return events
        .where((event) => !event.createdAt.isBefore(startOfDay))
        .fold(0, (total, event) => total + event.delta);
  }

  List<_DailyIntimacy> _buildWeekData(List<IntimacyEvent> events) {
    final now = DateTime.now();
    final Map<String, int> dailyDeltas = {};

    // 初始化最近7天
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = DateFormat('MM/dd').format(date);
      dailyDeltas[key] = 0;
    }

    // 聚合每日变化
    for (final event in events) {
      final key = DateFormat('MM/dd').format(event.createdAt);
      if (dailyDeltas.containsKey(key)) {
        dailyDeltas[key] = (dailyDeltas[key] ?? 0) + event.delta;
      }
    }

    return dailyDeltas.entries
        .map((e) => _DailyIntimacy(date: e.key, delta: e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('关系温度'),
        centerTitle: true,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _character == null
              ? Center(
                  child: Text('暂无数据',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (_characters.length > 1) ...[
                        _buildCharacterSelector(cs),
                        const SizedBox(height: 16),
                      ],
                      _buildHeader(cs),
                      const SizedBox(height: 16),
                      _buildTemperatureCard(cs),
                      const SizedBox(height: 16),
                      _buildEmotionCard(cs),
                      const SizedBox(height: 16),
                      _buildWeekChart(cs),
                      const SizedBox(height: 16),
                      _buildRecentEvents(cs),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCharacterSelector(ColorScheme cs) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _characters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final character = _characters[index];
          final selected = character.id == _selectedCharacterId;
          return ChoiceChip(
            selected: selected,
            label: Text(character.name),
            avatar: CircleAvatar(
              radius: 10,
              backgroundImage: AvatarResolver.imageProvider(character.avatarUrl),
              child: AvatarResolver.imageProvider(character.avatarUrl) == null
                  ? const Icon(Icons.person, size: 12)
                  : null,
            ),
            onSelected: (_) {
              if (selected) return;
              setState(() {
                _selectedCharacterId = character.id;
                _loading = true;
              });
              _loadData();
            },
          );
        },
      ),
    );
  }

  // ── 头部：角色信息 + 认识天数 ──
  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withOpacity(0.1),
            cs.tertiary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: (_character!.avatarUrl ?? '').isNotEmpty
                  ? (AvatarResolver.imageWidget(_character!.avatarUrl,
                      fit: BoxFit.cover,
                      onError: () => _defaultAvatar(cs)) ??
                      _defaultAvatar(cs))
                  : _defaultAvatar(cs),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_character!.name,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                Text('已经认识 $_daysSinceFirstChat 天',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 关系温度计 ──
  Widget _buildTemperatureCard(ColorScheme cs) {
    final stage = relationshipStage(_intimacyLevel);
    final stageNames = ['初见', '熟悉', '亲近', '亲密', '灵魂伴侣'];
    final stageName = stageNames[stage];
    final nextStageThresholds = [21, 41, 61, 81, 100];
    final nextThreshold = stage < 4 ? nextStageThresholds[stage] : 100;
    final progressInStage = stage < 4
        ? (_intimacyLevel - (stage > 0 ? nextStageThresholds[stage - 1] : 0)) /
            (nextThreshold - (stage > 0 ? nextStageThresholds[stage - 1] : 0))
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: cs.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('关系温度',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(stageName,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 温度数值
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$_intimacyLevel',
                  style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                      height: 1)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text('/ 100',
                    style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
              ),
              const Spacer(),
              if (_todayDelta != 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _todayDelta > 0
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${_todayDelta > 0 ? '+' : ''}$_todayDelta 今日',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _todayDelta > 0
                              ? const Color(0xFF10B981)
                              : Colors.red)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressInStage.clamp(0.0, 1.0),
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          if (stage < 4)
            Text(
                '距离「${stageNames[stage + 1]}」还需 ${nextThreshold - _intimacyLevel} 点',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ── 当前情绪卡片 ──
  Widget _buildEmotionCard(ColorScheme cs) {
    final emotion = _emotion;
    if (emotion == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: cs.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(emotion.effectiveEmotion.icon,
              size: 36, color: emotion.effectiveEmotion.color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_character!.name} 现在${emotion.effectiveEmotion.label}',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(emotion.effectiveEmotion.description,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          // 情绪强度指示
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: emotion.currentIntensity,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  strokeWidth: 4,
                ),
                Text('${(emotion.currentIntensity * 100).toInt()}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 7天亲密度曲线 ──
  Widget _buildWeekChart(ColorScheme cs) {
    if (_weekData.isEmpty) return const SizedBox();

    final maxDelta = _weekData
        .map((d) => d.delta.abs())
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, 999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: cs.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近 7 天',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _weekData.map((d) {
                final height = maxDelta > 0
                    ? (d.delta.abs() / maxDelta * 80).clamp(4.0, 80.0)
                    : 4.0;
                final isPositive = d.delta >= 0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (d.delta != 0)
                          Text('${isPositive ? '+' : ''}${d.delta}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: isPositive
                                      ? const Color(0xFF10B981)
                                      : Colors.red)),
                        const SizedBox(height: 4),
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            color: isPositive
                                ? cs.primary.withOpacity(0.7)
                                : Colors.red.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(d.date,
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── 最近亲密度事件 ──
  Widget _buildRecentEvents(ColorScheme cs) {
    if (_recentEvents.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: cs.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('最近变化',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 12),
          ..._recentEvents.take(10).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            e.delta > 0 ? const Color(0xFF10B981) : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${e.delta > 0 ? '+' : ''}${e.delta}  ${e.source}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface)),
                          if (e.messagePreview != null &&
                              e.messagePreview!.isNotEmpty)
                            Text(e.messagePreview!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Text(DateFormat('MM/dd HH:mm').format(e.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _defaultAvatar(ColorScheme cs) {
    return Container(
      color: cs.primary.withOpacity(0.1),
      child: Icon(Icons.person, color: cs.primary, size: 28),
    );
  }
}

class _DailyIntimacy {
  final String date;
  final int delta;
  const _DailyIntimacy({required this.date, required this.delta});
}
