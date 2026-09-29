// ============================================================
// 全生命周期数字生命世界 — Phase 3
// 记忆注入提示词构建器：将角色记忆注入 LLM 系统提示词
// 按遗忘曲线过滤，按年龄能力限制过滤
// ============================================================

import '../models/memory.dart';

/// 关系快照 — 用于记忆注入的关系摘要
class RelationshipSnapshot {
  final String personId;
  final String personName;
  final String relationType; // "朋友", "恋人", "对手" 等
  final double intimacy; // 0.0~1.0
  final double trust; // 0.0~1.0
  final List<String> tags;
  final String summary; // 一句话概括关系

  const RelationshipSnapshot({
    required this.personId,
    required this.personName,
    required this.relationType,
    this.intimacy = 0.0,
    this.trust = 0.0,
    this.tags = const [],
    required this.summary,
  });

  /// 综合重要性评分（亲密度 + 信任度加权）
  double get importance => intimacy * 0.6 + trust * 0.4;
}

/// 记忆注入提示词构建器
///
/// 将角色的多维记忆结构化注入 LLM 系统提示词，
/// 包含遗忘曲线过滤（基于 Memory.weight）和年龄能力限制。
///
/// 纯静态工具类，不需要实例化。
class MemoryPromptBuilder {
  MemoryPromptBuilder._();

  // ── 遗忘曲线阈值 ──
  static const double _forgettingThreshold = 0.3;

  // ── 关系记忆上限 ──
  static const int _maxRelationshipMemories = 5;

  // ── 近期事件上限 ──
  static const int _maxRecentMemories = 10;

  // ── 反思记忆上限 ──
  static const int _maxReflectionMemories = 5;

  // ── 创伤关键词（用于识别创伤记忆） ──
  static const List<String> _traumaKeywords = [
    '创伤', '背叛', '失去', '死亡', '抛弃', '伤害', '恐惧',
    '绝望', '崩溃', '痛苦', '灾难', '事故', '虐待', '遗弃',
  ];

  /// 构建完整的记忆上下文（注入到 LLM 系统提示词）
  ///
  /// 包含：关系记忆 + 近期事件 + 创伤记忆 + 反思记忆
  /// 如提供 [targetPersonId]，还会注入与该交互对象的专属记忆。
  static String buildMemoryContext({
    required List<Memory> memories,
    required List<RelationshipSnapshot> relationships,
    required int age,
    String? targetPersonId,
  }) {
    final filtered = filterByCapability(memories, age);

    final buffer = StringBuffer();

    // 1. 关系记忆
    buffer.write(_buildRelationshipMemories(relationships));

    // 2. 近期事件记忆（遗忘曲线过滤）
    buffer.write(_buildRecentMemories(filtered, age));

    // 3. 创伤记忆（永不遗忘）
    buffer.write(_buildTraumaMemories(filtered));

    // 4. 反思记忆
    buffer.write(_buildReflectionMemories(filtered));

    // 5. 针对特定交互对象的记忆
    if (targetPersonId != null && targetPersonId.isNotEmpty) {
      final targetName = _resolveTargetName(relationships, targetPersonId);
      buffer.write(
        _buildTargetedMemories(filtered, targetPersonId, targetName),
      );
    }

    return buffer.toString();
  }

  /// 从关系列表中查找目标人物名称
  static String _resolveTargetName(
    List<RelationshipSnapshot> relationships,
    String targetPersonId,
  ) {
    for (final r in relationships) {
      if (r.personId == targetPersonId) return r.personName;
    }
    return '对方';
  }

  /// 构建关系记忆（按重要性排序，取前5）
  static String _buildRelationshipMemories(
    List<RelationshipSnapshot> relationships,
  ) {
    if (relationships.isEmpty) return '';

    // 按重要性降序排列
    final sorted = List<RelationshipSnapshot>.from(relationships)
      ..sort((a, b) => b.importance.compareTo(a.importance));

    final topN = sorted.take(_maxRelationshipMemories).toList();

    final buffer = StringBuffer();
    buffer.writeln('【重要的人】');

    for (final r in topN) {
      final line = StringBuffer('- ${r.personName}');
      line.write('（${r.relationType}）');
      if (r.summary.isNotEmpty) {
        line.write('：${r.summary}');
      }
      buffer.writeln(line.toString());
    }

    buffer.writeln();
    return buffer.toString();
  }

  /// 构建近期事件记忆（按遗忘曲线过滤，保留率 > 0.3）
  static String _buildRecentMemories(List<Memory> memories, int age) {
    // 过滤：非创伤、非反思，且权重高于遗忘阈值
    final recent = memories.where((m) {
      if (m.weight < _forgettingThreshold) return false;
      if (_isTrauma(m)) return false; // 创伤单独处理
      if (m.type == MemoryType.reflection) return false; // 反思单独处理
      return true;
    }).toList();

    if (recent.isEmpty) return '';

    // 按创建时间降序，取最近的
    recent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final topN = recent.take(_maxRecentMemories).toList();

    final buffer = StringBuffer();
    buffer.writeln('【最近发生的事】');

    for (final m in topN) {
      final content = _truncateForAge(m.content, age);
      buffer.writeln('- $content');
    }

    buffer.writeln();
    return buffer.toString();
  }

  /// 构建创伤记忆（总是包含，只要有）
  static String _buildTraumaMemories(List<Memory> memories) {
    final traumas = memories.where(_isTrauma).toList();
    if (traumas.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('【内心的伤痕】');

    for (final m in traumas) {
      buffer.writeln('- ${m.content}');
    }

    buffer.writeln();
    return buffer.toString();
  }

  /// 构建反思记忆（最新的几条）
  static String _buildReflectionMemories(List<Memory> memories) {
    final reflections =
        memories.where((m) => m.type == MemoryType.reflection).toList();
    if (reflections.isEmpty) return '';

    // 按创建时间降序
    reflections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final topN = reflections.take(_maxReflectionMemories).toList();

    final buffer = StringBuffer();
    buffer.writeln('【反思与成长】');

    for (final m in topN) {
      buffer.writeln('- ${m.content}');
    }

    buffer.writeln();
    return buffer.toString();
  }

  /// 构建针对特定交互对象的记忆
  static String _buildTargetedMemories(
    List<Memory> memories,
    String targetPersonId,
    String targetName,
  ) {
    // 筛选与目标人物相关的记忆（通过关键词匹配 userId 或内容）
    final targeted = memories.where((m) {
      // 直接关联：记忆的 userId 就是目标人物
      if (m.userId == targetPersonId) return true;
      // 内容提及：记忆关键词或内容中包含目标人物信息
      if (m.keywords.any((k) => k.contains(targetPersonId))) return true;
      return false;
    }).toList();

    if (targeted.isEmpty) return '';

    // 按创建时间降序
    targeted.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final buffer = StringBuffer();
    buffer.writeln('【与${targetName}的记忆】');

    for (final m in targeted.take(5)) {
      buffer.writeln('- ${m.content}');
    }

    buffer.writeln();
    return buffer.toString();
  }

  /// 根据年龄过滤记忆能力
  ///
  /// - 0-2岁：只保留 emotionalWeight > 0.8 的记忆（极致情感体验）
  /// - 3-5岁：保留 emotionalWeight > 0.5 的记忆，内容截断
  /// - 6-11岁：保留 emotionalWeight > 0.3 的记忆
  /// - 12岁+：完整保留
  static List<Memory> filterByCapability(List<Memory> memories, int age) {
    if (age >= 12) return memories;

    double threshold;
    if (age <= 2) {
      threshold = 0.8;
    } else if (age <= 5) {
      threshold = 0.5;
    } else {
      threshold = 0.3;
    }

    return memories.where((m) => m.weight >= threshold).toList();
  }

  // ── 内部工具方法 ──

  /// 判断是否为创伤记忆
  ///
  /// 基于记忆类型（emotion + 高权重）和关键词匹配。
  static bool _isTrauma(Memory memory) {
    // 高权重的情绪记忆可能为创伤
    if (memory.type == MemoryType.emotion && memory.weight > 0.7) {
      return true;
    }
    // 关键词匹配
    final content = memory.content.toLowerCase();
    return _traumaKeywords.any((kw) => content.contains(kw));
  }

  /// 根据年龄截断记忆内容
  ///
  /// 幼儿期（3-5岁）只保留核心片段，模拟碎片化记忆。
  static String _truncateForAge(String content, int age) {
    if (age > 5) return content;

    // 3-5岁：截断为前30字，模拟碎片化
    const maxLen = 30;
    if (content.length <= maxLen) return content;
    return '${content.substring(0, maxLen)}……';
  }
}
