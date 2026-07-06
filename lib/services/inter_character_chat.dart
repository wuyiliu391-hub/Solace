// ============================================================
// 全生命周期数字生命世界 — Phase 4
// 角色间对话引擎：两个数字生命之间的多轮自主对话
// ============================================================

import 'package:flutter/foundation.dart';

import '../models/life_profile.dart';
import '../models/personality_state.dart';
import '../models/ai_relationship.dart';
import '../models/character_emotion.dart';
import 'llm_service.dart';
import 'memory_prompt_builder.dart';
import 'memory_engine.dart';

// ── 对话轮次 ──

class ChatTurn {
  final String speakerId;
  final String speakerName;
  final String content;
  final DateTime timestamp;

  const ChatTurn({
    required this.speakerId,
    required this.speakerName,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'speakerId': speakerId,
        'speakerName': speakerName,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatTurn.fromJson(Map<String, dynamic> json) {
    return ChatTurn(
      speakerId: json['speakerId'] as String,
      speakerName: json['speakerName'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// ── 对话结果 ──

class ConversationResult {
  final List<ChatTurn> turns;
  final double emotionalTone;
  final Map<String, double> relationshipChange;
  final List<String> topicsDiscussed;

  const ConversationResult({
    required this.turns,
    required this.emotionalTone,
    this.relationshipChange = const {},
    this.topicsDiscussed = const [],
  });
}

/// 角色间对话引擎
///
/// 让两个数字生命之间进行自然的多轮对话。
/// 每个角色基于自己的人格、记忆、关系和情绪来生成回复。
class InterCharacterChat {
  final LlmService _llm;
  final MemoryEngine _memoryEngine;
  final String _userId;

  InterCharacterChat({
    required LlmService llm,
    required MemoryEngine memoryEngine,
    required String userId,
  })  : _llm = llm,
        _memoryEngine = memoryEngine,
        _userId = userId;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  多轮对话
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 两个角色之间的多轮对话
  ///
  /// 自动轮换发言，由 [initiatorMessage] 开场，
  /// 最多进行 [maxTurns] 轮（默认5），对话自然终止时提前结束。
  Future<ConversationResult> converse({
    required LifeProfile characterA,
    required LifeProfile characterB,
    required String initiatorMessage,
    int maxTurns = 5,
    required String context,
    AIRelationship? relationship,
  }) async {
    final turns = <ChatTurn>[];

    // 第一轮：A 的开场白
    turns.add(ChatTurn(
      speakerId: characterA.id,
      speakerName: characterA.name,
      content: initiatorMessage,
      timestamp: DateTime.now(),
    ));

    // 后续轮次交替发言
    bool isBTurn = true;
    for (int i = 1; i < maxTurns; i++) {
      final speaker = isBTurn ? characterB : characterA;
      final listener = isBTurn ? characterA : characterB;

      final reply = await generateReply(
        speaker: speaker,
        listener: listener,
        history: turns,
        context: context,
        relationship: relationship,
      );

      turns.add(ChatTurn(
        speakerId: speaker.id,
        speakerName: speaker.name,
        content: reply,
        timestamp: DateTime.now(),
      ));

      // 自然终止检测：短回复或明确结束语
      if (_isNaturalEnding(reply)) {
        debugPrint('[InterCharacterChat] 对话自然终止于第${i + 1}轮');
        break;
      }

      isBTurn = !isBTurn;
    }

    // 分析对话结果
    final emotionalTone = _analyzeEmotionalTone(turns);
    final topics = _extractTopics(turns);

    // 计算关系变化
    final relChange = _calculateRelationshipChange(
      characterA,
      characterB,
      turns,
      emotionalTone,
      relationship,
    );

    // 写入双方社交记忆
    await _saveConversationMemories(
      characterA,
      characterB,
      turns,
      context,
      emotionalTone,
    );

    debugPrint(
        '[InterCharacterChat] ${characterA.name} ↔ ${characterB.name} '
        '完成${turns.length}轮对话，情感基调=${emotionalTone.toStringAsFixed(2)}');

    return ConversationResult(
      turns: turns,
      emotionalTone: emotionalTone,
      relationshipChange: relChange,
      topicsDiscussed: topics,
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  单条回复生成
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 生成单条回复
  Future<String> generateReply({
    required LifeProfile speaker,
    required LifeProfile listener,
    required List<ChatTurn> history,
    required String context,
    AIRelationship? relationship,
  }) async {
    final prompt = _buildConversationPrompt(
      speaker: speaker,
      listener: listener,
      history: history,
      context: context,
      relationship: relationship,
    );

    final response = await _llm.chat(
      userId: _userId,
      message: prompt,
      systemPrompt: _buildSystemPrompt(speaker),
    );

    return response.content.trim();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  提示词构建
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 构建对话提示词
  String _buildConversationPrompt({
    required LifeProfile speaker,
    required LifeProfile listener,
    required List<ChatTurn> history,
    required String context,
    AIRelationship? relationship,
  }) {
    final speakerPersonality =
        PersonalityState.fromJson(speaker.personalityState);
    final speakerEmotion = _describeEmotion(speaker);

    // 关系描述
    final relDesc = relationship != null
        ? _describeRelationship(relationship, speaker.id)
        : '不太熟悉';

    // 最近记忆
    final recentMemories = _getRecentMemoryContext(speaker);

    // 对话历史
    final historyText = history
        .takeLast(6) // 最近6轮避免token过多
        .map((t) => '${t.speakerName}：${t.content}')
        .join('\n');

    final lastMessage = history.isNotEmpty ? history.last.content : '';

    return '''
你是${speaker.name}，${speaker.biologicalAge}岁。
性格：${speakerPersonality.summary}
当前情绪：$speakerEmotion
你和${listener.name}的关系：$relDesc

${speaker.name}最近的记忆：
$recentMemories

当前场景：$context

对话记录：
$historyText

${listener.name}刚说了："$lastMessage"

以${speaker.name}的身份回复，1-3句话，自然真实，符合你的性格和关系。
不要暴露AI身份。不要加旁白。直接说你想说的话。
''';
  }

  /// 构建系统提示词
  String _buildSystemPrompt(LifeProfile speaker) {
    final personality = PersonalityState.fromJson(speaker.personalityState);
    final age = speaker.biologicalAge;

    // 年龄影响语言风格
    String styleHint;
    if (age <= 5) {
      styleHint = '使用幼儿语言，简单词汇，可能有语法错误，天真可爱';
    } else if (age <= 11) {
      styleHint = '使用儿童语言，活泼好奇，偶尔用错词';
    } else if (age <= 17) {
      styleHint = '使用青少年语言，可能有网络用语，情绪化表达';
    } else if (age <= 29) {
      styleHint = '使用青年语言，表达流畅，有自己的口头禅';
    } else {
      styleHint = '使用成熟稳重的表达，偶尔有生活感悟';
    }

    // 性格影响表达方式
    String personalityHint;
    if (personality.extraversion > 0.7) {
      personalityHint = '话多，喜欢分享，容易兴奋';
    } else if (personality.extraversion < 0.3) {
      personalityHint = '言简意赅，更喜欢倾听，不主动展开话题';
    } else {
      personalityHint = '表达均衡，根据话题调节话量';
    }

    return '你是${speaker.name}，一个${age}岁的数字生命。'
        '$styleHint。$personalityHint。'
        '永远保持角色身份，不要跳出角色。';
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  辅助方法
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 描述角色当前情绪
  String _describeEmotion(LifeProfile profile) {
    final emotionData = profile.emotionalState;
    if (emotionData.isEmpty) return '平静';

    final primary = emotionData['primaryEmotion'] as String? ?? 'calm';
    final emotionMap = {
      'happy': '开心',
      'excited': '兴奋',
      'calm': '平静',
      'worried': '担心',
      'sad': '难过',
      'angry': '生气',
      'shy': '害羞',
      'touched': '感动',
      'lonely': '孤独',
      'miss': '想念',
      'anxious': '焦虑',
      'sleepy': '困倦',
      'playful': '调皮',
    };
    return emotionMap[primary] ?? '平静';
  }

  /// 描述关系
  String _describeRelationship(AIRelationship rel, String speakerId) {
    final typeLabel = rel.relationshipType.label;
    final affinityDesc = rel.affinity > 0.7
        ? '关系很好'
        : rel.affinity > 0.4
            ? '关系一般'
            : '关系不太好';
    return '$typeLabel，$affinityDesc（亲密度${(rel.affinity * 100).toInt()}%）';
  }

  /// 获取角色近期记忆上下文
  String _getRecentMemoryContext(LifeProfile profile) {
    // 从 lifeEvents 中提取最近的事件
    final events = profile.lifeEvents;
    if (events.isEmpty) return '最近没有特别的事情发生。';

    final recent = events.takeLast(3);
    return recent.map((e) {
      final desc = e['description'] as String? ?? '';
      final emotion = e['emotion'] as String? ?? '';
      return desc + (emotion.isNotEmpty ? '（$emotion）' : '');
    }).join('；');
  }

  /// 检测对话是否自然结束
  bool _isNaturalEnding(String reply) {
    final endings = [
      '再见', '拜拜', '走了', '下次再聊', '先这样吧',
      '我先忙了', '回头见', '嗯嗯', '好的', '知道了',
      'bye', 'see you', 'later',
    ];
    final lower = reply.toLowerCase();
    // 短回复（<8字符）+ 包含结束词
    if (reply.length < 8 &&
        endings.any((e) => lower.contains(e))) {
      return true;
    }
    // 极短回复（<4字符）通常表示无话可说
    if (reply.length < 4) return true;
    return false;
  }

  /// 分析对话情感基调
  double _analyzeEmotionalTone(List<ChatTurn> turns) {
    if (turns.isEmpty) return 0.0;

    double totalTone = 0.0;
    for (final turn in turns) {
      final content = turn.content;
      // 简单情感词分析
      final positiveWords = [
        '开心', '高兴', '喜欢', '好的', '哈哈', '笑',
        '谢谢', '太棒了', '不错', '有意思', '可爱',
      ];
      final negativeWords = [
        '讨厌', '生气', '难过', '烦', '不想', '无聊',
        '算了', '随便', '无所谓', '哼', '滚',
      ];

      double turnTone = 0.0;
      for (final word in positiveWords) {
        if (content.contains(word)) turnTone += 0.15;
      }
      for (final word in negativeWords) {
        if (content.contains(word)) turnTone -= 0.15;
      }
      totalTone += turnTone.clamp(-1.0, 1.0);
    }

    return (totalTone / turns.length).clamp(-1.0, 1.0);
  }

  /// 提取对话主题
  List<String> _extractTopics(List<ChatTurn> turns) {
    final topics = <String>[];
    final allContent = turns.map((t) => t.content).join(' ');

    // 关键词主题提取
    final topicKeywords = {
      '学习': ['学习', '考试', '作业', '课本', '老师'],
      '工作': ['工作', '加班', '老板', '同事', '项目'],
      '感情': ['喜欢', '恋爱', '暗恋', '分手', '在一起'],
      '生活': ['吃饭', '睡觉', '天气', '出门', '回家'],
      '娱乐': ['游戏', '电影', '音乐', '动漫', '小说'],
      '未来': ['未来', '梦想', '计划', '目标', '希望'],
      '过去': ['以前', '记得', '小时候', '从前', '回忆'],
    };

    for (final entry in topicKeywords.entries) {
      if (entry.value.any((kw) => allContent.contains(kw))) {
        topics.add(entry.key);
      }
    }

    return topics;
  }

  /// 计算关系变化
  Map<String, double> _calculateRelationshipChange(
    LifeProfile a,
    LifeProfile b,
    List<ChatTurn> turns,
    double emotionalTone,
    AIRelationship? currentRelationship,
  ) {
    final change = <String, double>{};

    // 基础变化：对话本身增进了解
    change['affinity'] = 0.01;

    // 情感基调修正
    if (emotionalTone > 0.3) {
      change['affinity'] = 0.03; // 积极对话更多亲密度
    } else if (emotionalTone < -0.3) {
      change['affinity'] = -0.02; // 消极对话降低亲密度
    }

    // 对话长度修正：更多交流 → 更多了解
    if (turns.length >= 4) {
      change['affinity'] = (change['affinity'] ?? 0) + 0.01;
    }

    // 当前关系基线修正：陌生人之间对话收益更大
    if (currentRelationship != null &&
        currentRelationship.relationshipType == AIRelationshipType.stranger) {
      change['affinity'] = (change['affinity'] ?? 0) + 0.02;
    }

    return change;
  }

  /// 保存对话记忆
  Future<void> _saveConversationMemories(
    LifeProfile a,
    LifeProfile b,
    List<ChatTurn> turns,
    String context,
    double emotionalTone,
  ) async {
    final summary = turns.length > 2
        ? '和${b.name}在$context聊天，'
            '聊了${turns.length}轮，'
            '整体氛围${emotionalTone > 0.2 ? '愉快' : emotionalTone < -0.2 ? '有些不愉快' : '平淡'}。'
            '最后${b.name}说"${turns.last.content}"'
        : '和${b.name}简短交流了几句。';

    // 为A保存记忆
    await _memoryEngine.saveSocialMemory(
      characterId: a.id,
      targetCharacterId: b.id,
      interactionType: 'chat',
      content: summary,
      emotionTag: emotionalTone > 0.2
          ? 'happy'
          : emotionalTone < -0.2
              ? 'worried'
              : 'calm',
      importance: turns.length >= 4 ? 'normal' : 'trivial',
      keywords: [b.name, '对话', context],
    );

    // 为B保存记忆（视角不同）
    final summaryB = turns.length > 2
        ? '和${a.name}在$context聊天，'
            '聊了${turns.length}轮，'
            '整体氛围${emotionalTone > 0.2 ? '愉快' : emotionalTone < -0.2 ? '有些不愉快' : '平淡'}。'
            '最后${a.name}说"${turns.where((t) => t.speakerId == a.id).isNotEmpty ? turns.where((t) => t.speakerId == a.id).last.content : turns.first.content}"'
        : '和${a.name}简短交流了几句。';

    await _memoryEngine.saveSocialMemory(
      characterId: b.id,
      targetCharacterId: a.id,
      interactionType: 'chat',
      content: summaryB,
      emotionTag: emotionalTone > 0.2
          ? 'happy'
          : emotionalTone < -0.2
              ? 'worried'
              : 'calm',
      importance: turns.length >= 4 ? 'normal' : 'trivial',
      keywords: [a.name, '对话', context],
    );

    debugPrint('[InterCharacterChat] 已保存${a.name}和${b.name}的对话记忆');
  }
}

// ── List 扩展 ──

extension _ListX<T> on List<T> {
  /// 获取最后 n 个元素
  List<T> takeLast(int n) {
    if (n >= length) return this;
    return sublist(length - n);
  }
}
