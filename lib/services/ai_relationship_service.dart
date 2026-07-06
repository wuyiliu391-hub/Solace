import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/ai_character.dart';
import '../models/ai_config.dart';
import '../repositories/local_storage_repository.dart';
import '../config/constants.dart';
import '../utils/response_decoder.dart';

/// AI-to-AI 关系类型
enum RelationshipType {
  friend, // 朋友
  bestFriend, // 好友
  crush, // 暗恋
  lover, // 恋人
  rival, // 对手
  enemy, // 敌人
  sibling, // 兄弟姐妹
  mentor, // 导师
  stranger, // 陌生人
}

/// AI-to-AI 关系
class AIRelationship {
  final String id;
  final String characterIdA;
  final String characterIdB;
  final RelationshipType relationshipType;
  final double affinity; // 0.0~1.0，亲密度
  final String? description;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AIRelationship({
    required this.id,
    required this.characterIdA,
    required this.characterIdB,
    required this.relationshipType,
    this.affinity = 0.5,
    this.description,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'characterIdA': characterIdA,
        'characterIdB': characterIdB,
        'relationshipType': relationshipType.index,
        'affinity': affinity,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory AIRelationship.fromMap(Map<String, dynamic> map) => AIRelationship(
        id: map['id'] as String,
        characterIdA: map['characterIdA'] as String,
        characterIdB: map['characterIdB'] as String,
        relationshipType:
            RelationshipType.values[map['relationshipType'] as int],
        affinity: (map['affinity'] as num?)?.toDouble() ?? 0.5,
        description: map['description'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: map['updatedAt'] != null
            ? DateTime.parse(map['updatedAt'] as String)
            : null,
      );

  AIRelationship copyWith({
    RelationshipType? relationshipType,
    double? affinity,
    String? description,
    DateTime? updatedAt,
  }) {
    return AIRelationship(
      id: id,
      characterIdA: characterIdA,
      characterIdB: characterIdB,
      relationshipType: relationshipType ?? this.relationshipType,
      affinity: affinity ?? this.affinity,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// AI 关系网络服务
///
/// 功能：
/// 1. 管理 AI-to-AI 关系的 CRUD
/// 2. 用户与一个 AI 互动时，调整相关 AI 的亲密度
/// 3. 首次创建关系时通过 LLM 生成关系描述
/// 4. 为聊天 prompt 提供关系上下文
class AIRelationshipService {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();

  AIRelationshipService(this._storage);

  // ===================== CRUD =====================

  /// 创建 AI 关系
  Future<AIRelationship> createRelationship({
    required String characterIdA,
    required String characterIdB,
    required RelationshipType type,
    double affinity = 0.5,
    String? description,
  }) async {
    // 检查是否已存在（双向）
    final existing = await getRelationship(characterIdA, characterIdB);
    if (existing != null) {
      debugPrint('AIRelationshipService: 关系已存在 ${existing.id}');
      return existing;
    }

    final relationship = AIRelationship(
      id: _uuid.v4(),
      characterIdA: characterIdA,
      characterIdB: characterIdB,
      relationshipType: type,
      affinity: affinity,
      description: description,
      createdAt: DateTime.now(),
    );

    await _storage.setString(
        'ai_rel_${relationship.id}', jsonEncode(relationship.toMap()));
    // 更新索引
    _updateIndex(characterIdA, relationship.id);
    _updateIndex(characterIdB, relationship.id);

    debugPrint(
        'AIRelationshipService: 创建关系 ${characterIdA} ↔ $characterIdB ($type)');
    return relationship;
  }

  /// 获取两个角色之间的关系
  Future<AIRelationship?> getRelationship(
      String characterIdA, String characterIdB) async {
    // 查找 A→B 或 B→A
    final relA = await _findByPair(characterIdA, characterIdB);
    if (relA != null) return relA;
    return _findByPair(characterIdB, characterIdA);
  }

  /// 获取某个角色的所有关系
  Future<List<AIRelationship>> getRelationships(String characterId) async {
    final indexKey = 'ai_rel_index_$characterId';
    final idsJson = _storage.getString(indexKey);
    if (idsJson == null) return [];

    final ids = List<String>.from(jsonDecode(idsJson));
    final relationships = <AIRelationship>[];

    for (final id in ids) {
      final data = _storage.getString('ai_rel_$id');
      if (data != null) {
        try {
          relationships.add(AIRelationship.fromMap(jsonDecode(data)));
        } catch (_) {}
      }
    }

    return relationships;
  }

  /// 更新关系
  Future<void> updateRelationship(AIRelationship relationship) async {
    final updated = relationship.copyWith(updatedAt: DateTime.now());
    await _storage.setString(
        'ai_rel_${updated.id}', jsonEncode(updated.toMap()));
    debugPrint('AIRelationshipService: 更新关系 ${updated.id}');
  }

  /// 删除关系
  Future<void> deleteRelationship(String relationshipId) async {
    await _storage.remove('ai_rel_$relationshipId');
    debugPrint('AIRelationshipService: 删除关系 $relationshipId');
  }

  // ===================== 互动影响 =====================

  /// 用户与一个 AI 互动时，调整相关 AI 的亲密度
  ///
  /// 朋友关系：亲密度 +0.05
  /// 对手关系：亲密度 -0.03
  /// 其他关系不自动调整
  Future<void> onUserInteractWithAI({
    required String interactedCharacterId,
  }) async {
    final relationships = await getRelationships(interactedCharacterId);

    for (final rel in relationships) {
      double delta = 0.0;

      switch (rel.relationshipType) {
        case RelationshipType.friend:
        case RelationshipType.bestFriend:
        case RelationshipType.sibling:
          delta = 0.05; // 朋友 gain
          break;
        case RelationshipType.rival:
        case RelationshipType.enemy:
          delta = -0.03; // 对手 lose
          break;
        default:
          continue; // 其他关系不调整
      }

      final newAffinity = (rel.affinity + delta).clamp(0.0, 1.0);
      final updated = rel.copyWith(affinity: newAffinity);
      await updateRelationship(updated);

      debugPrint(
          'AIRelationshipService: ${rel.characterIdA} ↔ ${rel.characterIdB} '
          '亲密度 ${delta > 0 ? "+" : ""}${delta.toStringAsFixed(2)} → ${newAffinity.toStringAsFixed(2)}');
    }
  }

  // ===================== 关系描述生成 =====================

  /// 首次创建关系时通过 LLM 生成关系描述
  Future<String> generateRelationshipDescription({
    required AICharacter characterA,
    required AICharacter characterB,
    required RelationshipType type,
  }) async {
    final config = await _storage.getActiveAIConfig();
    if (config == null) return _getDefaultDescription(type);

    try {
      final prompt = '''为以下两个 AI 角色生成一段简短的关系描述（30-50字）。

【角色A】${characterA.name}
性格：${characterA.personality}

【角色B】${characterB.name}
性格：${characterB.personality}

【关系类型】${_relationshipLabel(type)}

请描述他们的关系，语气自然，像朋友间的介绍。直接返回描述文字，不要 JSON。''';

      final response = await _callAI(config, prompt);
      if (response != null && response.isNotEmpty) {
        return response.trim();
      }
    } catch (e) {
      debugPrint('AIRelationshipService: 生成关系描述失败 $e');
    }

    return _getDefaultDescription(type);
  }

  // ===================== 聊天 Prompt 上下文 =====================

  /// 为聊天 prompt 提供关系上下文
  ///
  /// 返回格式如："Character A 是你的好朋友，你们关系很亲密。"
  Future<String> getRelationshipContext({
    required String characterId,
    required List<String> otherCharacterIds,
  }) async {
    final buffer = StringBuffer();
    final relationships = await getRelationships(characterId);

    for (final rel in relationships) {
      // 找到与目标角色的关系
      final otherId =
          rel.characterIdA == characterId ? rel.characterIdB : rel.characterIdA;

      if (!otherCharacterIds.contains(otherId)) continue;

      final otherChar = await _storage.getAICharacter(otherId);
      if (otherChar == null) continue;

      final label = _relationshipLabel(rel.relationshipType);
      final affinityDesc = rel.affinity >= 0.7
          ? '关系很亲密'
          : rel.affinity >= 0.4
              ? '关系一般'
              : '关系不太好';

      buffer.writeln('${otherChar.name}是你的$label，$affinityDesc。'
          '${rel.description != null ? " ${rel.description}" : ""}');
    }

    return buffer.toString();
  }

  // ===================== 内部工具 =====================

  Future<AIRelationship?> _findByPair(String fromId, String toId) async {
    final relationships = await getRelationships(fromId);
    for (final rel in relationships) {
      if (rel.characterIdA == fromId && rel.characterIdB == toId) {
        return rel;
      }
    }
    return null;
  }

  Future<void> _updateIndex(String characterId, String relationshipId) async {
    final indexKey = 'ai_rel_index_$characterId';
    final idsJson = _storage.getString(indexKey);
    final idList =
        idsJson != null ? List<String>.from(jsonDecode(idsJson)) : [];
    if (!idList.contains(relationshipId)) {
      idList.add(relationshipId);
      await _storage.setString(indexKey, jsonEncode(idList));
    }
  }

  String _relationshipLabel(RelationshipType type) {
    switch (type) {
      case RelationshipType.friend:
        return '朋友';
      case RelationshipType.bestFriend:
        return '好友';
      case RelationshipType.crush:
        return '暗恋对象';
      case RelationshipType.lover:
        return '恋人';
      case RelationshipType.rival:
        return '对手';
      case RelationshipType.enemy:
        return '敌人';
      case RelationshipType.sibling:
        return '兄弟姐妹';
      case RelationshipType.mentor:
        return '导师';
      case RelationshipType.stranger:
        return '陌生人';
    }
  }

  String _getDefaultDescription(RelationshipType type) {
    switch (type) {
      case RelationshipType.friend:
        return '普通朋友，偶尔会聊天。';
      case RelationshipType.bestFriend:
        return '关系很好的朋友，经常互相帮助。';
      case RelationshipType.crush:
        return '暗恋对方，见面会有点紧张。';
      case RelationshipType.lover:
        return '恋人关系，彼此很亲密。';
      case RelationshipType.rival:
        return '竞争对手，互相较劲。';
      case RelationshipType.enemy:
        return '不太对付，尽量避免接触。';
      case RelationshipType.sibling:
        return '像兄弟姐妹一样，从小一起长大。';
      case RelationshipType.mentor:
        return '导师关系，经常请教问题。';
      case RelationshipType.stranger:
        return '不太认识，只是知道对方。';
    }
  }

  Future<String?> _callAI(AIConfig config, String prompt) async {
    String baseUrl = config.baseUrl.trim();
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = Uri.parse('$baseUrl/chat/completions');

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };

    final body = jsonEncode({
      'model': config.modelName,
      'messages': [
        {
          'role': 'system',
          'content': _storage.buildGlobalModePrompt(scope: 'AI关系描述'),
        },
        {'role': 'user', 'content': prompt},
      ],
      if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
        'temperature': GlmModeParams.relationshipTemperature,
        'top_p': GlmModeParams.topP,
        'top_k': GlmModeParams.relationshipTopK,
        'frequency_penalty': GlmModeParams.relationshipFrequencyPenalty,
        'thinking_budget': GlmModeParams.relationshipThinkingBudget,
        'max_tokens': GlmModeParams.relationshipMaxTokens,
      } else ...{
        'temperature': 0.8,
      },
      'max_tokens':
          _storage.isChatStyleNovelModeEnabled() ? config.maxTokens : 100,
    });

    try {
      final response = await http
          .post(url, headers: headers, body: body)
          .timeout(AppDurations.aiRequest);

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(
          response.headers['content-type'],
          response.bodyBytes,
        );
        final data = jsonDecode(decoded);
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          return choices[0]['message']?['content'] as String?;
        }
      }
    } catch (e) {
      debugPrint('AIRelationshipService: LLM 调用失败 $e');
    }

    return null;
  }
}
