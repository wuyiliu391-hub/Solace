import 'package:uuid/uuid.dart';
import '../../models/memory.dart';
import 'graph_node.dart';

/// 从记忆列表构建图数据（节点 + 连线）
/// 性能优化：用倒排索引代替 O(n²) 全量比较
class MemoryGraphBuilder {
  static const _uuid = Uuid();

  /// 生成连线：基于关键词倒排索引 + 同类型 + 时间接近
  /// 复杂度从 O(n²) 降到 O(n * avg_keywords_per_node * avg_matches_per_keyword)
  static List<GraphEdge> buildEdges(List<GraphNode> nodes, List<Memory> memories, {int maxEdges = 80}) {
    final count = nodes.length < memories.length ? nodes.length : memories.length;
    if (count == 0) return [];

    // 倒排索引：keyword -> [(nodeIdx, memoryIdx)]
    final invertedIndex = <String, List<int>>{};
    for (int i = 0; i < count; i++) {
      final kws = memories[i].keywords;
      for (final kw in kws) {
        invertedIndex.putIfAbsent(kw, () => []).add(i);
      }
    }

    // 候选边集合（去重）
    final edgeScores = <String, double>{};
    final edgeLabels = <String, String?>{};

    // 遍历倒排索引，只有共享关键词的节点对才会被比较
    for (final entry in invertedIndex.entries) {
      final indices = entry.value;
      if (indices.length < 2) continue;

      for (int i = 0; i < indices.length; i++) {
        for (int j = i + 1; j < indices.length; j++) {
          final aIdx = indices[i];
          final bIdx = indices[j];
          final key = aIdx < bIdx ? '$aIdx-$bIdx' : '$bIdx-$aIdx';

          final a = memories[aIdx];
          final b = memories[bIdx];

          double score = edgeScores[key] ?? 0;

          // 关键词重叠加分
          score += 0.35;

          // 同类型加分
          if (a.type == b.type) score += 0.2;

          // 时间接近加分
          final daysDiff = a.createdAt.difference(b.createdAt).inDays.abs();
          if (daysDiff <= 7) {
            score += (1 - daysDiff / 7) * 0.15;
          }

          edgeScores[key] = score;
          edgeLabels[key] ??= entry.key;
        }
      }
    }

    // 同类型 + 时间接近但无关键词共享的节点对（抽样，不做全量）
    // 用时间排序后只比较相邻的
    if (count <= 100) {
      final timeSorted = List.generate(count, (i) => i)
        ..sort((a, b) => memories[a].createdAt.compareTo(memories[b].createdAt));

      for (int i = 0; i < timeSorted.length; i++) {
        for (int j = i + 1; j < timeSorted.length && j <= i + 10; j++) {
          final aIdx = timeSorted[i];
          final bIdx = timeSorted[j];
          final key = aIdx < bIdx ? '$aIdx-$bIdx' : '$bIdx-$aIdx';
          if (edgeScores.containsKey(key)) continue;

          final a = memories[aIdx];
          final b = memories[bIdx];

          double score = 0;
          if (a.type == b.type) score += 0.2;

          final daysDiff = a.createdAt.difference(b.createdAt).inDays.abs();
          if (daysDiff <= 7) {
            score += (1 - daysDiff / 7) * 0.15;
          }

          if (score >= 0.3) {
            edgeScores[key] = score;
            edgeLabels[key] = null;
          }
        }
      }
    }

    // 构建候选列表
    final candidates = <GraphEdge>[];
    edgeScores.forEach((key, score) {
      if (score >= 0.3) {
        final parts = key.split('-');
        final aIdx = int.parse(parts[0]);
        final bIdx = int.parse(parts[1]);
        candidates.add(GraphEdge(
          id: _uuid.v4(),
          sourceId: nodes[aIdx].id,
          targetId: nodes[bIdx].id,
          label: edgeLabels[key],
          strength: score.clamp(0.0, 1.0),
        ));
      }
    });

    candidates.sort((a, b) => b.strength.compareTo(a.strength));
    return candidates.take(maxEdges).toList();
  }

  /// 从 Memory 列表构建 GraphNode 列表
  /// 卡片只放短预览；全文在详情弹窗（Memory.content）
  static List<GraphNode> buildNodes(List<Memory> memories) {
    return memories.map((m) {
      final preview = _cardPreview(m);
      return GraphNode(
        id: m.id,
        label: preview,
        subtitle: m.keywords.isNotEmpty ? m.keywords.take(2).join(' · ') : null,
        summary: preview,
        typeIndex: m.type.index,
        importance: m.importance.index / 3.0,
        weight: m.weight,
        x: 0,
        y: 0,
      );
    }).toList();
  }

  /// 图谱卡片固定短文案，避免撑破节点
  static String _cardPreview(Memory m) {
    final raw = (m.summary != null && m.summary!.trim().isNotEmpty)
        ? m.summary!.trim()
        : m.content.trim();
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (oneLine.length <= 18) return oneLine;
    return '${oneLine.substring(0, 17)}…';
  }
}
