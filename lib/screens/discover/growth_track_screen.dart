import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../config/growth_copy.dart';
import '../../models/ai_character.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/growth_data_service.dart';

class GrowthTrackScreen extends StatefulWidget {
  const GrowthTrackScreen({super.key});

  @override
  State<GrowthTrackScreen> createState() => _GrowthTrackScreenState();
}

class _GrowthTrackScreenState extends State<GrowthTrackScreen> {
  GrowthData? _data;
  List<AICharacter> _characters = [];
  String? _selectedCharacterId;
  bool _loading = true;
  String _timelineFilter = '全部';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final auth = context.read<AuthBloc>().state;
      if (auth is! AuthAuthenticated) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final service = GrowthDataService(storage, auth.user.id);
      final characters = await storage.getAllAICharacters();
      final data = await service.load(characterId: _selectedCharacterId);
      if (mounted) {
        setState(() {
          _characters = characters;
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToFirstNode() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : _data == null
              ? _buildEmptyState(cs)
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      _buildHeader(cs),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildCharacterSelector(cs),
                            const SizedBox(height: 16),
                            _buildRelationThermometer(cs),
                            const SizedBox(height: 16),
                            _buildStageSection(cs),
                            const SizedBox(height: 16),
                            _buildTimelineSection(cs),
                            const SizedBox(height: 16),
                            _buildHighlightsSection(cs),
                            const SizedBox(height: 16),
                            _buildAchievementsSection(cs),
                            const SizedBox(height: 16),
                            _buildNextStepSection(cs),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ═══════════════════════════════════════════
  // 角色切换
  // ═══════════════════════════════════════════

  Widget _buildCharacterSelector(ColorScheme cs) {
    if (_characters.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
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
              _loadData();
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ① 顶部主视觉 · 我们的起点
  // ═══════════════════════════════════════════

  Widget _buildHeader(ColorScheme cs) {
    final d = _data!;
    final days = d.daysSince;
    final firstDate = d.earliestDate;

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primary.withOpacity(0.7)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  // 角色头像
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.onPrimary.withOpacity(0.15),
                      border: Border.all(
                          color: cs.onPrimary.withOpacity(0.3), width: 2),
                    ),
                    child: d.primaryCharacter?.avatarUrl != null
                        ? ClipOval(
                            child: Image.network(
                              d.primaryCharacter!.avatarUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(Icons.person,
                                  color: cs.onPrimary, size: 28),
                            ),
                          )
                        : Icon(Icons.person, color: cs.onPrimary, size: 28),
                  ),
                  const SizedBox(height: 10),
                  // 陪伴天数
                  Text(
                    days > 0
                        ? '从 ${firstDate!.month}月${firstDate.day}日 那天起'
                        : '今天是我们认识的第一天',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onPrimary.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    days > 0 ? '我们已经一起走过了 $days 天' : '故事才刚刚开始',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '一起说了 ${d.totalMessages} 句话',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onPrimary.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ② 关系温度计 · 此刻的我们
  // ═══════════════════════════════════════════

  Widget _buildRelationThermometer(ColorScheme cs) {
    final d = _data!;
    final charName = d.primaryCharacter?.name ?? '他';

    final items = [
      _MetricItem(Icons.favorite, '心动对象', d.sessionCount > 0 ? charName : '—',
          '你的心里住了 ${d.sessionCount} 个人'),
      _MetricItem(Icons.chat_bubble_outline, '说过的话', '${d.totalMessages}',
          '你们一起说了 ${d.totalMessages} 句话'),
      _MetricItem(
          Icons.thermostat, '心灵契合度', '${d.avgIntimacy}%', '$charName懂你的程度'),
      _MetricItem(Icons.bedtime, '深夜陪伴', '${d.nightChatCount}',
          '有 ${d.nightChatCount} 个夜晚陪你'),
    ];

    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('此刻的我们',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 14),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 22, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(item.value,
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurface)),
                          ],
                        ),
                      ),
                      Text(item.detail,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                )),
          ],
        ));
  }

  // ═══════════════════════════════════════════
  // ③ 关系阶段 · 我们走到哪了
  // ═══════════════════════════════════════════

  Widget _buildStageSection(ColorScheme cs) {
    final d = _data!;
    final stage = relationshipStage(d.maxIntimacy);
    final persona = d.primaryCharacter != null
        ? GrowthCopy.matchPersona(d.primaryCharacter!.personality)
        : PersonaType.generic;

    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('我们走到哪了',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const Spacer(),
                Text(GrowthCopy.stageTitle(stage),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
              ],
            ),
            const SizedBox(height: 16),
            // 阶段进度条
            Row(
              children: List.generate(5, (i) {
                final isActive = i <= stage;
                final isCurrent = i == stage;
                return Expanded(
                  child: Container(
                    height: isCurrent ? 8 : 5,
                    margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: isActive ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                  color: cs.primary.withOpacity(0.4),
                                  blurRadius: 6)
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            // 阶段名称
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final isActive = i <= stage;
                return Text(
                  GrowthCopy.stageTitle(i),
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            // 当前阶段描述
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                GrowthCopy.stageSubtitle(stage, persona),
                style:
                    TextStyle(fontSize: 14, color: cs.onSurface, height: 1.5),
              ),
            ),
          ],
        ));
  }

  // ═══════════════════════════════════════════
  // ④ 时间线 · 我们的足迹（核心模块）
  // ═══════════════════════════════════════════

  Widget _buildTimelineSection(ColorScheme cs) {
    final d = _data!;
    final nodes = _filteredNodes;

    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题 + 回到起点按钮
            Row(
              children: [
                Text('我们的足迹',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const Spacer(),
                if (d.timelineNodes.length > 5)
                  GestureDetector(
                    onTap: _scrollToFirstNode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_rounded, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Text('回到起点',
                              style:
                                  TextStyle(fontSize: 12, color: cs.primary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 筛选器
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['全部', '里程碑', '纪念日', '高光', '日常', '进化'].map((f) {
                  final isActive = _timelineFilter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _timelineFilter = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? cs.primary : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(f,
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  isActive ? cs.onPrimary : cs.onSurfaceVariant,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            )),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            // 节点列表
            if (nodes.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        GrowthCopy.emptyTimeline(),
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      if (d.messagesUntilNextEvolution > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '距离下次日常进化还需 ${d.messagesUntilNextEvolution} 条消息',
                          style: TextStyle(fontSize: 12, color: cs.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              ...nodes.asMap().entries.map((entry) {
                final i = entry.key;
                final node = entry.value;
                final isLast = i == nodes.length - 1;
                return _buildTimelineNode(cs, node, isLast, i);
              }),
          ],
        ));
  }

  List<TimelineNode> get _filteredNodes {
    final d = _data!;
    if (_timelineFilter == '全部') return d.timelineNodes.reversed.toList();
    final typeMap = {
      '里程碑': TimelineNodeType.milestone,
      '纪念日': TimelineNodeType.anniversary,
      '高光': [
        TimelineNodeType.highlight,
        TimelineNodeType.night,
        TimelineNodeType.special
      ],
      '日常': TimelineNodeType.daily,
      '进化': [TimelineNodeType.evolution, TimelineNodeType.qualitative],
    };
    final filter = typeMap[_timelineFilter];
    if (filter is List) {
      return d.timelineNodes
          .where((n) => filter.contains(n.type))
          .toList()
          .reversed
          .toList();
    }
    return d.timelineNodes
        .where((n) => n.type == filter)
        .toList()
        .reversed
        .toList();
  }

  Widget _buildTimelineNode(
      ColorScheme cs, TimelineNode node, bool isLast, int index) {
    final icon = _nodeIcon(node.type);
    final color = _nodeColor(node.type, cs);
    final isAnniversary = node.type == TimelineNodeType.anniversary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧时间线
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: isAnniversary ? 28 : 22,
                  height: isAnniversary ? 28 : 22,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: isAnniversary
                        ? Border.all(color: color, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Icon(icon,
                        size: isAnniversary ? 14 : 11, color: Colors.white),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: cs.outlineVariant.withOpacity(0.4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 右侧内容
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isAnniversary
                      ? color.withOpacity(0.08)
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: isAnniversary
                      ? Border.all(color: color.withOpacity(0.3))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            node.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          _formatNodeDate(node.date),
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      node.subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                          height: 1.4),
                    ),
                    if (node.characterName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        node.characterName!,
                        style: TextStyle(fontSize: 11, color: cs.primary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _nodeIcon(TimelineNodeType type) {
    switch (type) {
      case TimelineNodeType.milestone:
        return Icons.star;
      case TimelineNodeType.anniversary:
        return Icons.cake;
      case TimelineNodeType.highlight:
        return Icons.chat_bubble;
      case TimelineNodeType.special:
        return Icons.celebration;
      case TimelineNodeType.daily:
        return Icons.calendar_today;
      case TimelineNodeType.night:
        return Icons.bedtime;
      case TimelineNodeType.evolution:
        return Icons.spa;
      case TimelineNodeType.qualitative:
        return Icons.bolt;
    }
  }

  Color _nodeColor(TimelineNodeType type, ColorScheme cs) {
    switch (type) {
      case TimelineNodeType.milestone:
        return const Color(0xFFF59E0B);
      case TimelineNodeType.anniversary:
        return const Color(0xFFEC4899);
      case TimelineNodeType.highlight:
        return const Color(0xFF3B82F6);
      case TimelineNodeType.special:
        return const Color(0xFF8B5CF6);
      case TimelineNodeType.daily:
        return const Color(0xFF06B6D4);
      case TimelineNodeType.night:
        return const Color(0xFF6366F1);
      case TimelineNodeType.evolution:
        return const Color(0xFF10B981);
      case TimelineNodeType.qualitative:
        return const Color(0xFFF97316);
    }
  }

  String _formatNodeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  // ═══════════════════════════════════════════
  // ⑤ 专属回忆录 · 那些心动瞬间
  // ═══════════════════════════════════════════

  Widget _buildHighlightsSection(ColorScheme cs) {
    final d = _data!;
    if (d.highlights.isEmpty) return const SizedBox.shrink();

    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('那些心动瞬间',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 14),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.highlights.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final h = d.highlights[i];
                  return Container(
                    width: 160,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.primary.withOpacity(0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(h.title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface)),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(h.subtitle,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                  height: 1.3)),
                        ),
                        Text(
                          '${h.date.month}/${h.date.day}',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ));
  }

  // ═══════════════════════════════════════════
  // ⑥ 成就纪念册
  // ═══════════════════════════════════════════

  Widget _buildAchievementsSection(ColorScheme cs) {
    final d = _data!;
    final unlocked = d.achievements.where((a) => a.unlocked).toList();
    final locked = d.achievements.where((a) => !a.unlocked).toList();

    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('专属纪念册',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const Spacer(),
                Text('${unlocked.length}/${d.achievements.length}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 14),
            // 已解锁
            ...unlocked.map((a) => _buildAchievementCard(cs, a, true)),
            // 未解锁（最多显示3个）
            if (locked.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('继续互动解锁',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              ...locked.take(3).map((a) => _buildAchievementCard(cs, a, false)),
            ],
          ],
        ));
  }

  Widget _buildAchievementCard(
      ColorScheme cs, AchievementData a, bool unlocked) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked ? cs.primary.withOpacity(0.05) : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked ? cs.primary.withOpacity(0.15) : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(a.icon,
              size: 28, color: unlocked ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: unlocked ? cs.onSurface : cs.onSurfaceVariant,
                    )),
                const SizedBox(height: 2),
                Text(
                  unlocked ? a.subtitle : a.unlockHint,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(
            unlocked ? Icons.check_circle : Icons.lock_outline,
            color: unlocked ? const Color(0xFF10B981) : cs.outline,
            size: 20,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ⑦ 未来期许 · 接下来的故事
  // ═══════════════════════════════════════════

  Widget _buildNextStepSection(ColorScheme cs) {
    final d = _data!;
    final persona = d.primaryCharacter != null
        ? GrowthCopy.matchPersona(d.primaryCharacter!.personality)
        : PersonaType.generic;
    final nextText = GrowthCopy.nextStepText(d.avgIntimacy, persona);

    return _card(cs,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('接下来的故事',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.06),
                    cs.primary.withOpacity(0.02)
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                nextText,
                style:
                    TextStyle(fontSize: 15, color: cs.onSurface, height: 1.5),
              ),
            ),
          ],
        ));
  }

  // ═══════════════════════════════════════════
  // 通用组件
  // ═══════════════════════════════════════════

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_stories,
                size: 64, color: cs.primary.withOpacity(0.3)),
            const SizedBox(height: 20),
            Text('故事才刚刚开始',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('去和他聊聊天吧\n每一个瞬间都会被珍藏',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: cs.onSurfaceVariant, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _card(ColorScheme cs, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MetricItem {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  _MetricItem(this.icon, this.label, this.value, this.detail);
}
