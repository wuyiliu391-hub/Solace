// 【对标来源：Muice-Chatbot-1.4 — llm/faiss_memory.py 向量记忆存储】
// 1:1 转译自 Muice FAISSMemory 类，适配 Flutter SQLite + SharedPreferences
// 参考文件：llm/faiss_memory.py:search_memory()、insert_memory()、save_all_data()

import "dart:convert";
import "dart:math";
import "package:uuid/uuid.dart";
import "package:sqflite/sqflite.dart";
import "../models/emotion_memory_entry.dart";
import "database_service.dart";

/// 记忆仓库（对标 Muice FAISSMemory）
/// 将 Muice 的 FAISS 向量检索逻辑平移至 SQLite + 内存向量计算
/// 保留原生 search_memory / insert_memory / save_all_data 语义
class MemoryRepository {
  static MemoryRepository? _instance;
  static MemoryRepository get instance => _instance ??= MemoryRepository._();
  MemoryRepository._();

  final DatabaseService _db = DatabaseService.instance;
  static const _uuid = Uuid();

  /// 向量维度（对标 Muice distiluse-base-multilingual-cased-v1 = 512）
  static const int embeddingSize = 512;

  /// top_k 检索数量（对标 Muice FAISSMemory.top_k = 1）
  static const int topK = 1;

  /// 内存缓存的向量索引（对标 Muice self.index）
  List<List<double>> _indexVectors = [];

  /// 索引到文档 ID 的映射（对标 Muice self.index_to_docstore_id）
  Map<int, String> _indexToDocstoreId = {};

  /// 文档存储（对标 Muice self.docstore）
  Map<String, EmotionMemoryEntry> _docstore = {};

  /// 是否已加载
  bool _loaded = false;

  /// 初始化（对标 Muice __init__）
  Future<void> initialize(String characterId, String userId) async {
    if (_loaded) return;

    final db = await _db.database;
    final rows = await db.query(
      'memories',
      where: 'characterId = ? AND userId = ?',
      whereArgs: [characterId, userId],
      orderBy: 'timestamp DESC',
    );

    _docstore.clear();
    _indexVectors.clear();
    _indexToDocstoreId.clear();

    int idx = 0;
    for (final row in rows) {
      final entry = _rowToEntry(row);
      _docstore[entry.id] = entry;

      if (entry.embedding != null && entry.embedding!.isNotEmpty) {
        _indexVectors.add(entry.embedding!);
        _indexToDocstoreId[idx] = entry.id;
        idx++;
      }
    }

    _loaded = true;
  }

  /// 搜索记忆（对标 Muice FAISSMemory.search_memory）
  /// 使用余弦相似度替代 FAISS L2 距离
  Future<List<EmotionMemoryEntry>> searchMemory({
    required String query,
    required String characterId,
    required String userId,
    int? topKOverride,
  }) async {
    await initialize(characterId, userId);

    if (_indexVectors.isEmpty) return [];

    // 如果有嵌入向量，使用向量检索
    // 否则回退到关键词匹配（对标 Muice 正则匹配 input/output）
    final queryEmbedding = await _getEmbedding(query);
    if (queryEmbedding != null) {
      return _vectorSearch(queryEmbedding, topKOverride ?? topK);
    }

    // 回退：关键词匹配（对标 Muice search_memory 正则 pattern）
    return _keywordSearch(query, characterId, userId, topKOverride ?? topK);
  }

  /// 向量检索（对标 Muice FAISS IndexFlatL2 搜索）
  List<EmotionMemoryEntry> _vectorSearch(
      List<double> queryVector, int k) {
    if (_indexVectors.isEmpty) return [];

    // 计算余弦相似度（对标 FAISS L2 距离，越小越相似）
    final scores = <MapEntry<int, double>>[];
    for (int i = 0; i < _indexVectors.length; i++) {
      final similarity = _cosineSimilarity(queryVector, _indexVectors[i]);
      scores.add(MapEntry(i, similarity));
    }

    // 按相似度降序排序（对标 FAISS 最小 L2 距离）
    scores.sort((a, b) => b.value.compareTo(a.value));

    // 取 top_k
    final results = <EmotionMemoryEntry>[];
    for (int i = 0; i < k && i < scores.length; i++) {
      final docId = _indexToDocstoreId[scores[i].key];
      if (docId != null && _docstore.containsKey(docId)) {
        results.add(_docstore[docId]!);
      }
    }

    return results;
  }

  /// 关键词检索（对标 Muice search_memory 正则匹配）
  List<EmotionMemoryEntry> _keywordSearch(
      String query, String characterId, String userId, int k) {
    final queryLower = query.toLowerCase();
    final scored = <MapEntry<EmotionMemoryEntry, double>>[];

    for (final entry in _docstore.values) {
      if (entry.characterId != characterId || entry.userId != userId) {
        continue;
      }

      double score = 0.0;
      final inputLower = entry.input.toLowerCase();
      final outputLower = entry.output.toLowerCase();

      // 关键词匹配评分（对标 Muice 正则 input/output 匹配）
      if (inputLower.contains(queryLower) ||
          queryLower.contains(inputLower)) {
        score += 1.0;
      }
      if (outputLower.contains(queryLower)) {
        score += 0.5;
      }

      // 时间衰减加分（最近的记忆优先）
      final hoursSince =
          DateTime.now().difference(entry.timestamp).inHours;
      score += 1.0 / (1.0 + log(hoursSince + 1));

      // 权重加分
      score += entry.weight * 0.5;

      if (score > 0) {
        scored.add(MapEntry(entry, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(k).map((e) => e.key).toList();
  }

  /// 插入记忆（对标 Muice FAISSMemory.insert_memory）
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
    await initialize(characterId, userId);

    final id = _uuid.v4();
    final now = DateTime.now();

    final entry = EmotionMemoryEntry(
      id: id,
      characterId: characterId,
      userId: userId,
      input: input,
      output: output,
      emotionTag: emotionTag,
      valence: valence,
      arousal: arousal,
      timestamp: now,
      embedding: embedding,
      weight: 1.0,
    );

    // 写入 SQLite（对标 Muice save_all_data -> save_index）
    final db = await _db.database;
    await db.insert('memories', {
      'id': id,
      'characterId': characterId,
      'userId': userId,
      'input': input,
      'output': output,
      'emotionTag': emotionTag,
      'valence': valence,
      'arousal': arousal,
      'timestamp': now.toIso8601String(),
      'embedding': embedding != null ? jsonEncode(embedding) : null,
      'weight': 1.0,
      'pinned': 0,
      'lastRecalledAt': null,
    });

    // 更新内存索引（对标 Muice self.index.add）
    _docstore[id] = entry;
    if (embedding != null && embedding.isNotEmpty) {
      final idx = _indexVectors.length;
      _indexVectors.add(embedding);
      _indexToDocstoreId[idx] = id;
    }
  }

  /// 标记记忆被回忆（对标 Muice 记忆强化机制）
  Future<void> markRecalled(String memoryId) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'memories',
      {
        'weight': 'weight * 1.01', // 强化系数
        'lastRecalledAt': now,
      },
      where: 'id = ?',
      whereArgs: [memoryId],
    );

    // 更新内存缓存
    if (_docstore.containsKey(memoryId)) {
      final old = _docstore[memoryId]!;
      _docstore[memoryId] = EmotionMemoryEntry(
        id: old.id,
        characterId: old.characterId,
        userId: old.userId,
        input: old.input,
        output: old.output,
        emotionTag: old.emotionTag,
        valence: old.valence,
        arousal: old.arousal,
        timestamp: old.timestamp,
        embedding: old.embedding,
        weight: (old.weight * 1.01).clamp(0.0, 2.0),
      );
    }
  }

  /// 获取角色所有记忆
  Future<List<EmotionMemoryEntry>> getAllMemories(
      String characterId, String userId) async {
    await initialize(characterId, userId);
    return _docstore.values
        .where((e) =>
            e.characterId == characterId && e.userId == userId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// 删除记忆
  Future<void> deleteMemory(String memoryId) async {
    final db = await _db.database;
    await db.delete('memories', where: 'id = ?', whereArgs: [memoryId]);
    _docstore.remove(memoryId);
  }

  /// 清空角色记忆
  Future<void> clearMemories(
      String characterId, String userId) async {
    final db = await _db.database;
    await db.delete('memories',
        where: 'characterId = ? AND userId = ?',
        whereArgs: [characterId, userId]);
    _docstore.clear();
    _indexVectors.clear();
    _indexToDocstoreId.clear();
  }

  /// 获取记忆数量
  Future<int> getMemoryCount(
      String characterId, String userId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM memories WHERE characterId = ? AND userId = ?',
      [characterId, userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 余弦相似度计算
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// 获取嵌入向量（占位：实际需要对接 embedding 服务）
  Future<List<double>?> _getEmbedding(String text) async {
    return null;
  }

  /// 数据库行转记忆条目
  EmotionMemoryEntry _rowToEntry(Map<String, dynamic> row) {
    return EmotionMemoryEntry(
      id: row['id'] as String? ?? '',
      characterId: row['characterId'] as String? ?? '',
      userId: row['userId'] as String? ?? '',
      input: row['input'] as String? ?? '',
      output: row['output'] as String? ?? '',
      emotionTag: row['emotionTag'] as String?,
      valence: (row['valence'] as num?)?.toDouble(),
      arousal: (row['arousal'] as num?)?.toDouble(),
      timestamp: row['timestamp'] != null
          ? DateTime.parse(row['timestamp'] as String)
          : DateTime.now(),
      embedding: row['embedding'] != null
          ? (jsonDecode(row['embedding'] as String) as List<dynamic>)
              .map((e) => (e as num).toDouble())
              .toList()
          : null,
      weight: (row['weight'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

