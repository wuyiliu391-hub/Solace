// ============================================================
// 全生命周期数字生命世界 — Phase 6
// 关系图谱：简洁列表展示
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/relationship_graph.dart';
import '../../models/ai_character.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_relationship_service.dart' hide RelationshipType;

/// 关系类型 → 颜色映射
Color relationshipColor(RelationshipType type) {
  switch (type) {
    case RelationshipType.enemy:
      return const Color(0xFFE53935);
    case RelationshipType.rival:
      return const Color(0xFFFF7043);
    case RelationshipType.friend:
    case RelationshipType.bestFriend:
      return const Color(0xFF4CAF50);
    case RelationshipType.crush:
    case RelationshipType.lover:
      return const Color(0xFFE91E90);
    case RelationshipType.sibling:
      return const Color(0xFF29B6F6);
    case RelationshipType.mentor:
      return const Color(0xFFFFB300);
    case RelationshipType.follower:
      return const Color(0xFF7E57C2);
    case RelationshipType.stranger:
      return const Color(0xFF9E9E9E);
    default:
      return const Color(0xFF9E9E9E);
  }
}

/// 关系类型 → 标签映射
String _relTypeLabel(RelationshipType type) {
  switch (type) {
    case RelationshipType.stranger: return '陌生人';
    case RelationshipType.friend: return '朋友';
    case RelationshipType.bestFriend: return '挚友';
    case RelationshipType.crush: return '暗恋';
    case RelationshipType.lover: return '恋人';
    case RelationshipType.rival: return '对手';
    case RelationshipType.enemy: return '敌人';
    case RelationshipType.sibling: return '兄弟姐妹';
    case RelationshipType.mentor: return '师徒';
    case RelationshipType.follower: return '追随者';
    default: return '未知';
  }
}

/// 关系图谱页面 — 简洁列表版
class RelationshipGraphViewScreen extends StatefulWidget {
  const RelationshipGraphViewScreen({super.key});

  @override
  State<RelationshipGraphViewScreen> createState() => _RelationshipGraphViewScreenState();
}

class _RelationshipGraphViewScreenState extends State<RelationshipGraphViewScreen> {
  final List<AICharacter> _characters = [];
  final List<RelationshipGraph> _relationships = [];
  bool _loading = true;

  // 角色 ID → 名字 映射
  final Map<String, String> _nameMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final userId = authState.user.id;

      // 加载所有角色
      final sessions = await storage.getChatSessions(userId);
      for (final session in sessions) {
        final char = await storage.getAICharacter(session.aiCharacterId);
        if (char != null) {
          _characters.add(char);
          _nameMap[char.id] = char.name;
        }
      }

      // 使用 AIRelationshipService 加载关系数据
      final relService = AIRelationshipService(storage);
      final loadedRelIds = <String>{};

      for (final char in _characters) {
        final relationships = await relService.getRelationships(char.id);
        for (final rel in relationships) {
          // 避免重复添加（关系是双向的）
          if (!loadedRelIds.contains(rel.id)) {
            loadedRelIds.add(rel.id);
            // 将 AIRelationship 转换为 RelationshipGraph
            final graph = RelationshipGraph(
              id: rel.id,
              personIdA: rel.characterIdA,
              personIdB: rel.characterIdB,
              familiarity: rel.affinity,
              intimacy: rel.affinity * 0.8, // 基于亲密度估算
              trust: rel.affinity * 0.7, // 基于亲密度估算
              respect: rel.affinity * 0.6,
              createdAt: rel.createdAt,
              updatedAt: rel.updatedAt ?? rel.createdAt,
            );
            _relationships.add(graph);
          }
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('RelationshipGraphViewScreen: 加载失败 $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        title: Text('关系图谱', style: TextStyle(color: cs.onSurface)),
        iconTheme: IconThemeData(color: cs.onSurface),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _relationships.isEmpty
              ? _buildEmptyState(context)
              : _buildList(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub, size: 64, color: cs.onSurfaceVariant.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('暂无关系数据', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
          const SizedBox(height: 8),
          Text('角色之间建立关系后将在此展示', style: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.6), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _relationships.length,
      itemBuilder: (context, index) {
        final rel = _relationships[index];
        final relType = rel.inferredType;
        final color = relationshipColor(relType);
        final nameA = _nameMap[rel.personIdA] ?? rel.personIdA;
        final nameB = _nameMap[rel.personIdB] ?? rel.personIdB;
        final familiarity = rel.familiarity.clamp(0.0, 1.0);
        final intimacy = ((rel.intimacy + 1) / 2).clamp(0.0, 1.0); // 归一化到 0-1
        final trust = ((rel.trust + 1) / 2).clamp(0.0, 1.0);

        return Card(
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像A ↔ 头像B + 关系类型
                Row(
                  children: [
                    // 角色A头像
                    _buildAvatar(context, nameA, cs),
                    const SizedBox(width: 8),
                    // 关系类型标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_relTypeLabel(relType), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.swap_horiz, size: 18, color: color),
                    const SizedBox(width: 8),
                    // 角色B头像
                    _buildAvatar(context, nameB, cs),
                    const SizedBox(width: 12),
                    // 名字
                    Expanded(
                      child: Text(
                        '$nameA ↔ $nameB',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 维度进度条
                Row(
                  children: [
                    Expanded(child: _buildDimensionBar(context, '亲密度', intimacy, Colors.pink)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDimensionBar(context, '信任度', trust, Colors.blue)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDimensionBar(context, '熟悉度', familiarity, Colors.teal)),
                  ],
                ),
                // 标签
                if (rel.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: rel.tags.map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(t, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatar(BuildContext context, String name, ColorScheme cs) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name.characters.first : '?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onPrimaryContainer),
        ),
      ),
    );
  }

  Widget _buildDimensionBar(BuildContext context, String label, double value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            Text('${(value * 100).toInt()}%', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
