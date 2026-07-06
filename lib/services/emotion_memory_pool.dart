// 【对标来源：Muice-Chatbot-1.4 — llm/faiss_memory.py 情绪记忆池】
// 1:1 转译自 Muice FAISSMemory 的情绪感知记忆检索
// 参考文件：llm/faiss_memory.py:search_memory()、insert_memory()

import "dart:math";
import "../models/emotion_memory_entry.dart";
import "../repositories/memory_repository.dart";

/// 情绪记忆池（对标 Muice FAISSMemory + 情绪扩展）
/// 基于 Muice 向量检索逻辑，增加情绪标签过滤与权重计算
class EmotionMemoryPool {
  final MemoryRepository _memoryRepo = MemoryRepository.instance;

  /// 检索相关记忆（对标 Muice search_memory）
  /// 同时考虑文本相似度和情绪匹配度
  Future<List<EmotionMemoryEntry>> searchMemory({
    required String query,
    required String characterId,
    required String userId,
    String? currentEmotionTag,
    double? currentValence,
    double? currentArousal,
    int topK = 3,
  }) async {
    // 基础检索（对标 Muice FAISS L2 检索）
    final candidates = await _memoryRepo.searchMemory(
      query: query,
      characterId: characterId,
      userId: userId,
      topKOverride: topK * 2, // 多检索一些候选
    );

    if (candidates.isEmpty) return [];

    // 情绪加权重排序
    final scored = <MapEntry<EmotionMemoryEntry, double>>[];
    for (final entry in candidates) {
      double score = 1.0;

      // 情绪标签匹配加分
      if (currentEmotionTag != null &&
          entry.emotionTag == currentEmotionTag) {
        score += 0.3;
      }

      // 情绪效价相近加分（对标 Muice 情绪记忆池筛选）
      if (currentValence != null && entry.valence != null) {
        final valenceDiff = (currentValence - entry.valence!).abs();
        score += (1.0 - valenceDiff) * 0.2;
      }

      // 唤醒度相近加分
      if (currentArousal != null && entry.arousal != null) {
        final arousalDiff = (currentArousal - entry.arousal!).abs();
        score += (1.0 - arousalDiff) * 0.1;
      }

      // 时间衰减加分（最近的记忆优先）
      final hoursSince =
          DateTime.now().difference(entry.timestamp).inHours;
      score += 1.0 / (1.0 + log(hoursSince + 1)) * 0.2;

      // 权重加分
      score += entry.weight * 0.2;

      scored.add(MapEntry(entry, score));
    }

    // 按综合评分排序
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(topK).map((e) => e.key).toList();
  }

  /// 插入情绪记忆（对标 Muice insert_memory）
  Future<void> insertMemory({
    required String input,
    required String output,
    required String characterId,
    required String userId,
    String? emotionTag,
    double? valence,
    double? arousal,
    List<double>? embedding,
  }) async {
    await _memoryRepo.insertMemory(
      input: input,
      output: output,
      characterId: characterId,
      userId: userId,
      emotionTag: emotionTag,
      valence: valence,
      arousal: arousal,
      embedding: embedding,
    );
  }

  /// 标记记忆被回忆（强化记忆权重）
  Future<void> markRecalled(String memoryId) async {
    await _memoryRepo.markRecalled(memoryId);
  }

  /// 获取所有情绪记忆
  Future<List<EmotionMemoryEntry>> getAllMemories(
      String characterId, String userId) async {
    return await _memoryRepo.getAllMemories(characterId, userId);
  }

  /// 获取情绪统计
  Future<Map<String, int>> getEmotionStats(
      String characterId, String userId) async {
    final memories =
        await _memoryRepo.getAllMemories(characterId, userId);
    final stats = <String, int>{};

    for (final entry in memories) {
      final tag = entry.emotionTag ?? 'unknown';
      stats[tag] = (stats[tag] ?? 0) + 1;
    }

    return stats;
  }
}
