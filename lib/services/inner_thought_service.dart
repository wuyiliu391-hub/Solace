import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import 'emotion_engine.dart';

/// 内心活动服务 — 管理用户和 AI 的内心独白
///
/// 功能：
/// 1. 用户内心独白：从文本输入面板保存
/// 2. AI 内心独白：从 ReflectionEngine 的持久化状态自动生成
/// 3. 阅读交互：用户读 AI 想法时调整情绪，AI 在心跳时"读"用户想法
enum InnerThoughtType {
  user, // 用户的内心独白
  ai, // AI 自动生成的内心独白
}

class InnerThought {
  final String id;
  final String characterId;
  final String userId;
  final String content;
  final InnerThoughtType type;
  final double emotionValence;
  final double emotionArousal;
  final bool isRead;
  final DateTime createdAt;

  const InnerThought({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.content,
    required this.type,
    this.emotionValence = 0.0,
    this.emotionArousal = 0.0,
    this.isRead = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'characterId': characterId,
        'userId': userId,
        'content': content,
        'type': type.index,
        'emotionValence': emotionValence,
        'emotionArousal': emotionArousal,
        'isRead': isRead ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
      };

  factory InnerThought.fromMap(Map<String, dynamic> map) => InnerThought(
        id: map['id'] as String,
        characterId: map['characterId'] as String,
        userId: map['userId'] as String,
        content: map['content'] as String,
        type: InnerThoughtType.values[map['type'] as int],
        emotionValence: (map['emotionValence'] as num?)?.toDouble() ?? 0.0,
        emotionArousal: (map['emotionArousal'] as num?)?.toDouble() ?? 0.0,
        isRead: (map['isRead'] as int) == 1,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

/// 内心活动服务
class InnerThoughtService {
  final LocalStorageRepository _storage;
  final EmotionEngine _emotionEngine;
  final _uuid = const Uuid();

  InnerThoughtService(this._storage, this._emotionEngine);

  // ===================== 用户内心独白 =====================

  /// 保存用户内心独白
  Future<InnerThought> saveUserThought({
    required String characterId,
    required String userId,
    required String content,
    double emotionValence = 0.0,
    double emotionArousal = 0.0,
  }) async {
    final thought = InnerThought(
      id: _uuid.v4(),
      characterId: characterId,
      userId: userId,
      content: content,
      type: InnerThoughtType.user,
      emotionValence: emotionValence,
      emotionArousal: emotionArousal,
      createdAt: DateTime.now(),
    );

    await _storage.setString('thought_${thought.id}', jsonEncode(thought.toMap()));
    // 更新索引
    final indexKey = 'thought_index_${characterId}_$userId';
    final ids = _storage.getString(indexKey);
    final idList = ids != null ? List<String>.from(jsonDecode(ids)) : [];
    idList.add(thought.id);
    await _storage.setString(indexKey, jsonEncode(idList));

    debugPrint('InnerThoughtService: 保存用户内心独白 ${thought.id}');
    return thought;
  }

  // ===================== AI 内心独白 =====================

  /// 从 ReflectionEngine 的持久化状态自动生成 AI 内心独白
  ///
  /// 读取 SharedPreferences 中的 reflection_{charId}_{userId}_state
  /// 将其中的 thought 字段提取为一条内心独白
  Future<InnerThought?> generateAIFromReflection({
    required String characterId,
    required String userId,
  }) async {
    final stateKey = 'reflection_${characterId}_${userId}_state';
    final stateJson = _storage.getString(stateKey);
    if (stateJson == null) {
      debugPrint('InnerThoughtService: 未找到反思状态 $stateKey');
      return null;
    }

    try {
      final stateMap = jsonDecode(stateJson) as Map<String, dynamic>;
      final thought = stateMap['thought'] as String?;
      if (thought == null || thought.isEmpty) return null;

      // 从反思状态中提取情绪信息
      final urgency = (stateMap['urgency'] as num?)?.toDouble() ?? 0.0;

      // 根据 urgency 估算情绪维度
      double valence = 0.0;
      double arousal = 0.3;
      if (urgency > 0.5) {
        valence = -(urgency - 0.5) * 0.1; // 高紧迫度偏消极
        arousal = 0.3 + urgency * 0.4; // 紧迫度高→活跃
      }

      final aiThought = InnerThought(
        id: _uuid.v4(),
        characterId: characterId,
        userId: userId,
        content: thought,
        type: InnerThoughtType.ai,
        emotionValence: valence,
        emotionArousal: arousal,
        createdAt: DateTime.now(),
      );

      await _storage.setString('thought_${aiThought.id}', jsonEncode(aiThought.toMap()));
      final indexKey = 'thought_index_${characterId}_$userId';
      final ids = _storage.getString(indexKey);
      final idList = ids != null ? List<String>.from(jsonDecode(ids)) : [];
      idList.add(aiThought.id);
      await _storage.setString(indexKey, jsonEncode(idList));

      debugPrint('InnerThoughtService: 从反思状态生成 AI 内心独白 ${aiThought.id}');
      return aiThought;
    } catch (e) {
      debugPrint('InnerThoughtService: 解析反思状态失败 $e');
      return null;
    }
  }

  // ===================== 阅读交互 =====================

  /// 用户阅读 AI 内心独白时调用
  ///
  /// 效果：调整情绪 valence ±0.02（根据内容情感倾向），亲密 +1
  Future<void> onUserReadAIThought({
    required String characterId,
    required String userId,
    required InnerThought thought,
  }) async {
    if (thought.type != InnerThoughtType.ai) return;

    // 标记已读
    final updatedThought = _markAsRead(thought);
    await _storage.setString('thought_${thought.id}', jsonEncode(updatedThought.toMap()));

    // 根据内容情感倾向调整 valence
    // 正面关键词 → +0.02，负面关键词 → -0.02
    final delta = _analyzeSentimentDelta(thought.content);
    await _emotionEngine.adjustValence(
      characterId: characterId,
      userId: userId,
      delta: delta,
    );

    debugPrint('InnerThoughtService: 用户阅读 AI 独白，valence 调整 ${delta > 0 ? "+" : ""}$delta');
  }

  /// AI 在心跳时"阅读"用户内心独白
  ///
  /// 效果：根据独白内容的情感分析调整 AI 情绪
  Future<void> onAIReadUserThought({
    required String characterId,
    required String userId,
    required InnerThought thought,
  }) async {
    if (thought.type != InnerThoughtType.user) return;

    // 标记已读
    final updatedThought = _markAsRead(thought);
    await _storage.setString('thought_${thought.id}', jsonEncode(updatedThought.toMap()));

    // 根据用户独白的情感调整 AI 情绪
    final delta = _analyzeSentimentDelta(thought.content);
    await _emotionEngine.adjustValence(
      characterId: characterId,
      userId: userId,
      delta: delta,
    );

    debugPrint('InnerThoughtService: AI 阅读用户独白，valence 调整 ${delta > 0 ? "+" : ""}$delta');
  }

  // ===================== 查询 =====================

  /// 获取角色与用户之间的所有内心独白
  Future<List<InnerThought>> getThoughts({
    required String characterId,
    required String userId,
    int limit = 50,
  }) async {
    final indexKey = 'thought_index_${characterId}_$userId';
    final idsJson = _storage.getString(indexKey);
    if (idsJson == null) return [];

    final ids = List<String>.from(jsonDecode(idsJson));
    final thoughts = <InnerThought>[];

    for (final id in ids.reversed) {
      final data = _storage.getString('thought_$id');
      if (data != null) {
        try {
          thoughts.add(InnerThought.fromMap(jsonDecode(data)));
        } catch (_) {}
      }
      if (thoughts.length >= limit) break;
    }

    return thoughts;
  }

  /// 获取未读的 AI 内心独白
  Future<List<InnerThought>> getUnreadAIThoughts({
    required String characterId,
    required String userId,
  }) async {
    final all = await getThoughts(characterId: characterId, userId: userId);
    return all
        .where((t) => t.type == InnerThoughtType.ai && !t.isRead)
        .toList();
  }

  /// 获取未读的用户内心独白（AI 待读）
  Future<List<InnerThought>> getUnreadUserThoughts({
    required String characterId,
    required String userId,
  }) async {
    final all = await getThoughts(characterId: characterId, userId: userId);
    return all
        .where((t) => t.type == InnerThoughtType.user && !t.isRead)
        .toList();
  }

  /// 删除内心独白
  Future<void> deleteThought(String thoughtId) async {
    await _storage.remove('thought_$thoughtId');
    debugPrint('InnerThoughtService: 删除内心独白 $thoughtId');
  }

  // ===================== 内部工具 =====================

  InnerThought _markAsRead(InnerThought thought) {
    return InnerThought(
      id: thought.id,
      characterId: thought.characterId,
      userId: thought.userId,
      content: thought.content,
      type: thought.type,
      emotionValence: thought.emotionValence,
      emotionArousal: thought.emotionArousal,
      isRead: true,
      createdAt: thought.createdAt,
    );
  }

  /// 简单情感分析：返回 valence 调整量（+0.02 或 -0.02）
  double _analyzeSentimentDelta(String content) {
    // 正面关键词
    const positiveWords = [
      '开心', '快乐', '幸福', '喜欢', '爱', '美好', '温暖', '感谢',
      '期待', '希望', '棒', '好', '甜', '幸福', '感动', '惊喜',
    ];
    // 负面关键词
    const negativeWords = [
      '难过', '伤心', '生气', '烦', '累', '焦虑', '担心', '害怕',
      '孤独', '无聊', '失望', '讨厌', '恨', '痛', '苦', '哭',
    ];

    int positiveCount = 0;
    int negativeCount = 0;
    for (final word in positiveWords) {
      if (content.contains(word)) positiveCount++;
    }
    for (final word in negativeWords) {
      if (content.contains(word)) negativeCount++;
    }

    if (positiveCount > negativeCount) return 0.02;
    if (negativeCount > positiveCount) return -0.02;
    return 0.0; // 中性内容不调整
  }
}
