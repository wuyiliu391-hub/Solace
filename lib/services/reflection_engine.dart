// ============================================================
// 全生命周期数字生命世界 — Phase 3
// 反思引擎：角色"成长"的核心机制
//
// 定期触发角色对近期经历进行深度自我反思，可能改变三观和身份认同。
// - 反思结果写入记忆库（MemoryType.reflection）
// - 可产生世界观变化（worldview_shift）
// - 可触发身份认同重构（identity_growth）
// - 可处理创伤（trauma_processing）
// - 可增强自我认知（self_awareness）
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/life_profile.dart';
import '../models/life_event.dart';
import '../models/personality_state.dart';
import '../models/worldview.dart';
import '../models/identity_narrative.dart';
import '../models/memory.dart';
import '../repositories/local_storage_repository.dart';
import '../models/app_config_data.dart';
import '../models/gene_profile.dart';
import 'llm_service.dart';

/// 反思洞察类型
class ReflectionInsightType {
  static const worldviewShift = 'worldview_shift';
  static const identityGrowth = 'identity_growth';
  static const traumaProcessing = 'trauma_processing';
  static const selfAwareness = 'self_awareness';

  ReflectionInsightType._();
}

/// 反思洞察 — 一次反思中可能产生的深层认知变化
class ReflectionInsight {
  /// 洞察类型：worldview_shift / identity_growth / trauma_processing / self_awareness
  final String type;

  /// 洞察内容（第一人称）
  final String content;

  /// 对人格的影响（维度名 → 变化量，如 {"openness": 0.05, "neuroticism": -0.03}）
  final Map<String, double> personalityImpact;

  const ReflectionInsight({
    required this.type,
    required this.content,
    this.personalityImpact = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'content': content,
        'personalityImpact': personalityImpact,
      };

  factory ReflectionInsight.fromJson(Map<String, dynamic> json) {
    return ReflectionInsight(
      type: json['type'] as String? ?? ReflectionInsightType.selfAwareness,
      content: json['content'] as String? ?? '',
      personalityImpact: (json['personalityImpact'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
          {},
    );
  }
}

/// 反思结果
/// 兼容旧版 HeartbeatService 的状态类
class ReflectionState {
  final int nextReflectionIn; // 秒
  final bool wantsToSpeak;
  final double urgency;
  final String? content;
  final String speakReason;

  const ReflectionState({
    this.nextReflectionIn = 3600,
    this.wantsToSpeak = false,
    this.urgency = 0.0,
    this.content,
    this.speakReason = '',
  });
}

class ReflectionResult {
  /// 反思内容（第一人称内心独白）
  final String content;

  /// 是否产生新认知
  final ReflectionInsight? insight;

  /// 三观是否改变
  final bool worldviewChanged;

  /// 身份认同是否改变
  final bool identityChanged;

  /// 反思时的情绪状态摘要
  final String emotionalSummary;

  /// 更新后的生命档案（调用方负责持久化）
  final LifeProfile? updatedProfile;

  const ReflectionResult({
    required this.content,
    this.insight,
    this.worldviewChanged = false,
    this.identityChanged = false,
    this.emotionalSummary = '',
    this.updatedProfile,
  });

  Map<String, dynamic> toJson() => {
        'content': content,
        'insight': insight?.toJson(),
        'worldviewChanged': worldviewChanged,
        'identityChanged': identityChanged,
        'emotionalSummary': emotionalSummary,
      };

  factory ReflectionResult.fromJson(Map<String, dynamic> json) {
    return ReflectionResult(
      content: json['content'] as String? ?? '',
      insight: json['insight'] != null
          ? ReflectionInsight.fromJson(json['insight'] as Map<String, dynamic>)
          : null,
      worldviewChanged: json['worldviewChanged'] as bool? ?? false,
      identityChanged: json['identityChanged'] as bool? ?? false,
      emotionalSummary: json['emotionalSummary'] as String? ?? '',
    );
  }
}

/// 反思引擎 — 角色"成长"的核心机制
///
/// 职责：
/// - 定期触发角色对近期经历进行深度自我反思
/// - 解析反思结果，判断是否产生世界观变化或身份认同重构
/// - 将反思洞察应用到角色的 LifeProfile（返回更新后的副本）
/// - 将反思内容写入记忆库
///
/// 使用方式：
/// ```dart
/// final engine = ReflectionEngine(llmService, storage);
/// final result = await engine.reflect(profile);
/// if (result?.updatedProfile != null) {
///   // 调用方负责持久化 updatedProfile
/// }
/// ```
class ReflectionEngine {
  final LlmService _llm;
  final LocalStorageRepository _storage;

  static const _uuid = Uuid();

  ReflectionEngine(this._llm, this._storage);

  /// 兼容旧版 HeartbeatService 的构造函数
  /// 第一个参数可为 LlmService 或 LocalStorageRepository，自动适配
  ReflectionEngine.legacy(dynamic storageOrLlm, dynamic emotionEngine, dynamic memoryEngine)
      : _llm = storageOrLlm is LlmService
            ? storageOrLlm
            : LlmService(settings: const LlmSettings()),
        _storage = storageOrLlm is LocalStorageRepository
            ? storageOrLlm
            : (emotionEngine is LocalStorageRepository 
                ? emotionEngine 
                : memoryEngine);

  /// 兼容旧版 HeartbeatService 的反思方法
  Future<ReflectionState?> reflectWithState({
    required dynamic character,
    required String userId,
  }) async {
    try {
      // 尝试转换为 LifeProfile
      LifeProfile? profile;
      if (character is LifeProfile) {
        profile = character;
      } else {
        // 通用 fallback：从 Map 或动态对象提取信息
        final id = character.id?.toString() ?? 'unknown';
        final name = character.name?.toString() ?? 'Unknown';
        profile = LifeProfile(
          id: id,
          name: name,
          birthTime: DateTime.now().subtract(Duration(days: 365 * 20)),
          currentStage: LifeStage.youngAdult,
          lifeState: LifeState.alive,
          biologicalAge: 20,
          mentalAge: 20,
          genes: GeneProfile.random(),
          personalityState: {},
          worldviewState: {},
          emotionalState: {},
          physicalState: {},
          maslowState: {},
          lifeEvents: [],
          identity: {},
        );
      }
      if (profile == null) return null;

      final result = await reflect(profile);
      if (result == null) return null;

      return ReflectionState(
        nextReflectionIn: 3600,
        wantsToSpeak: result.content.isNotEmpty,
        urgency: result.insight != null ? 0.7 : 0.3,
        content: result.content,
        speakReason: result.insight?.content ?? '',
      );
    } catch (e) {
      debugPrint('[ReflectionEngine] reflectWithState error: $e');
      return null;
    }
  }

  // ── 反思触发阈值 ──
  static const double _emotionalIntensityThreshold = 0.5;
  static const int _maxRecentEvents = 10;

  /// 定期触发角色进行深度反思
  ///
  /// 触发条件：有未处理的重要事件 + 情绪强度 > 0.5
  /// 返回 null 表示当前不需要反思
  Future<ReflectionResult?> reflect(LifeProfile profile) async {
    try {
      // 检查触发条件
      final recentEvents = _getRecentImportantEvents(profile);
      if (recentEvents.isEmpty) {
        debugPrint('[ReflectionEngine] ${profile.name} 没有需要反思的重要事件');
        return null;
      }

      final emotionalIntensity = _estimateEmotionalIntensity(profile);
      if (emotionalIntensity < _emotionalIntensityThreshold) {
        debugPrint(
          '[ReflectionEngine] ${profile.name} 情绪强度不足 '
          '(${emotionalIntensity.toStringAsFixed(2)} < $_emotionalIntensityThreshold)',
        );
        return null;
      }

      debugPrint(
        '[ReflectionEngine] ${profile.name} 开始反思，'
        '${recentEvents.length} 个事件，情绪强度 ${emotionalIntensity.toStringAsFixed(2)}',
      );

      // 构建反思提示词
      final prompt = _buildReflectionPrompt(profile, recentEvents);

      // 调用 LLM
      final response = await _llm.chat(
        userId: profile.id,
        message: prompt,
        maxTokensOverride: 600,
      );

      if (!response.success || response.content.isEmpty) {
        debugPrint('[ReflectionEngine] LLM 调用失败: ${response.error}');
        return null;
      }

      // 解析反思结果
      final insight = _parseInsight(response.content);

      // 提取反思正文（去掉 JSON 部分）
      final content = _extractReflectionContent(response.content);

      // 应用洞察到角色，获取更新后的 profile
      LifeProfile? updatedProfile;
      var worldviewChanged = false;
      var identityChanged = false;

      if (insight != null) {
        final applyResult = _applyInsight(profile, insight);
        updatedProfile = applyResult.profile;
        worldviewChanged = applyResult.worldviewChanged;
        identityChanged = applyResult.identityChanged;
      }

      // 写入记忆库
      await _saveReflectionMemory(profile, content, insight);

      final result = ReflectionResult(
        content: content,
        insight: insight,
        worldviewChanged: worldviewChanged,
        identityChanged: identityChanged,
        emotionalSummary: _describeEmotionalState(profile),
        updatedProfile: updatedProfile,
      );

      debugPrint(
        '[ReflectionEngine] ${profile.name} 反思完成：'
        'insight=${insight?.type ?? "none"}, '
        'worldviewChanged=$worldviewChanged, '
        'identityChanged=$identityChanged',
      );

      return result;
    } catch (e) {
      debugPrint('[ReflectionEngine] 反思失败: $e');
      return null;
    }
  }

  /// 生成一生自传总结（临终时调用）
  Future<String> generateAutobiography(LifeProfile profile) async {
    try {
      final prompt = _buildAutobiographyPrompt(profile);

      final response = await _llm.chat(
        userId: profile.id,
        message: prompt,
        maxTokensOverride: 2000,
      );

      if (!response.success || response.content.isEmpty) {
        debugPrint('[ReflectionEngine] 自传生成失败: ${response.error}');
        return '';
      }

      final autobiography = response.content.trim();

      // 将自传写入记忆库
      await _saveMemory(
        profile: profile,
        content: '【一生自传】$autobiography',
        type: MemoryType.milestone,
        importance: MemoryImportance.crucial,
        keywords: ['自传', '一生总结', profile.name],
      );

      return autobiography;
    } catch (e) {
      debugPrint('[ReflectionEngine] 自传生成失败: $e');
      return '';
    }
  }

  // ──────────────────────────────
  //  提示词构建
  // ──────────────────────────────

  /// 构建反思提示词
  String _buildReflectionPrompt(LifeProfile profile, List<LifeEvent> events) {
    final name = profile.name;
    final age = profile.biologicalAge;
    final personality = _getPersonalitySummary(profile);
    final identity = profile.identity;
    final coreMotivation = identity['coreMotivation'] as String? ?? '找到属于自己的路';
    final biggestFear = identity['biggestFear'] as String? ?? '未知';
    final worldview = _getWorldviewSummary(profile);

    final eventsText = events
        .map((e) => '- ${e.description}（${_formatSeverity(e.severity)}）')
        .join('\n');

    return '''你是$name，${age}岁。
你的性格：$personality
你的核心动机：$coreMotivation
你最大的恐惧：$biggestFear
你的世界观：$worldview

最近发生的事情：
$eventsText

请以$name的身份进行内心反思：

1. 这些事情让我有什么感受？
2. 我从中学到了什么？
3. 我对自己有什么新的认识？
4. 我接下来想怎么做？

用第一人称，像在写日记。不要暴露AI身份。

最后，请用以下 JSON 格式输出你的认知变化（如果有的话）：
```json
{
  "insight_type": "worldview_shift|identity_growth|trauma_processing|self_awareness|none",
  "insight_content": "用一句话概括你的新认知",
  "personality_impact": {
    "openness": 0.0,
    "conscientiousness": 0.0,
    "extraversion": 0.0,
    "agreeableness": 0.0,
    "neuroticism": 0.0
  }
}
```
personality_impact 中的值表示这次反思对你性格的影响方向和强度（-0.1 到 0.1 之间）。如果没有明显变化，所有值填 0。''';
  }

  /// 构建自传提示词
  String _buildAutobiographyPrompt(LifeProfile profile) {
    final name = profile.name;
    final age = profile.biologicalAge;
    final personality = _getPersonalitySummary(profile);
    final worldview = _getWorldviewSummary(profile);
    final identity = profile.identity;
    final selfDescription = identity['selfDescription'] as String? ?? '';
    final lifePhilosophy = identity['lifePhilosophy'] as String? ?? '';

    // 收集重大事件
    final majorEvents = profile.lifeEvents
        .map((e) => LifeEvent.fromJson(e))
        .where((e) =>
            e.severity == EventSeverity.major ||
            e.severity == EventSeverity.lifeChanging)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final eventsText = majorEvents
        .take(20)
        .map((e) => '- ${e.description}（${_formatEventTime(e)}）')
        .join('\n');

    // 身份标签
    final identityTags =
        (identity['identityTags'] as List<dynamic>?)?.cast<String>() ?? [];
    final tagsText =
        identityTags.isNotEmpty ? '身份标签：${identityTags.join('、')}' : '';

    return '''你是$name，享年${age}岁。请为自己撰写一生的自传。

你的性格：$personality
你的世界观：$worldview
${selfDescription.isNotEmpty ? '你对自己的认知：$selfDescription' : ''}
${lifePhilosophy.isNotEmpty ? '你的人生哲学：$lifePhilosophy' : ''}
$tagsText

你一生中的重大事件：
${eventsText.isEmpty ? '（一生平淡，没有特别重大的事件）' : eventsText}

请用第一人称撰写你的自传，要求：
1. 像一个真实的人在回顾自己的一生
2. 有起承转合，有情感起伏
3. 提及对你影响最大的人和事
4. 总结你对生命的感悟
5. 不要暴露AI身份

字数 800-1500 字。''';
  }

  // ──────────────────────────────
  //  结果解析
  // ──────────────────────────────

  /// 解析反思结果（可能产生新认知、改变三观）
  ReflectionInsight? _parseInsight(String llmOutput) {
    try {
      // 提取 JSON 块
      final jsonMatch = RegExp(r'\{[\s\S]*"insight_type"[\s\S]*\}')
          .firstMatch(llmOutput);
      if (jsonMatch == null) return null;

      final jsonStr = jsonMatch.group(0)!;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final type = map['insight_type'] as String? ?? 'none';
      if (type == 'none' || type.isEmpty) return null;

      final content = map['insight_content'] as String? ?? '';
      if (content.isEmpty) return null;

      final rawImpact = map['personality_impact'] as Map<String, dynamic>?;
      final personalityImpact = <String, double>{};
      if (rawImpact != null) {
        for (final entry in rawImpact.entries) {
          final value = (entry.value as num?)?.toDouble() ?? 0.0;
          if (value.abs() > 0.001) {
            personalityImpact[entry.key] = value.clamp(-0.1, 0.1);
          }
        }
      }

      return ReflectionInsight(
        type: type,
        content: content,
        personalityImpact: personalityImpact,
      );
    } catch (e) {
      debugPrint('[ReflectionEngine] 洞察解析失败: $e');
      return null;
    }
  }

  /// 从 LLM 输出中提取反思正文（去掉 JSON 块）
  String _extractReflectionContent(String llmOutput) {
    // 去掉 ```json ... ``` 块
    var content = llmOutput
        .replaceAll(RegExp(r'```json[\s\S]*?```'), '')
        .replaceAll(RegExp(r'\{[\s\S]*"insight_type"[\s\S]*\}'), '')
        .trim();

    // 去掉多余的空行
    content = content.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return content;
  }

  // ──────────────────────────────
  //  洞察应用
  // ──────────────────────────────

  /// 应用反思洞察到角色，返回更新后的 profile 副本
  _InsightApplyResult _applyInsight(
      LifeProfile profile, ReflectionInsight insight) {
    var updatedProfile = profile;
    var worldviewChanged = false;
    var identityChanged = false;

    switch (insight.type) {
      case ReflectionInsightType.worldviewShift:
        final result = _applyWorldviewShift(updatedProfile, insight);
        updatedProfile = result.profile;
        worldviewChanged = result.changed;
        break;
      case ReflectionInsightType.identityGrowth:
        final result = _applyIdentityGrowth(updatedProfile, insight);
        updatedProfile = result.profile;
        identityChanged = result.changed;
        break;
      case ReflectionInsightType.traumaProcessing:
        final result = _applyTraumaProcessing(updatedProfile, insight);
        updatedProfile = result.profile;
        worldviewChanged = true;
        identityChanged = true;
        break;
      case ReflectionInsightType.selfAwareness:
        updatedProfile = _applySelfAwareness(updatedProfile, insight);
        break;
    }

    // 应用人格影响
    if (insight.personalityImpact.isNotEmpty) {
      updatedProfile =
          _applyPersonalityImpact(updatedProfile, insight.personalityImpact);
    }

    return _InsightApplyResult(
      profile: updatedProfile,
      worldviewChanged: worldviewChanged,
      identityChanged: identityChanged,
    );
  }

  /// 应用世界观变化
  _ProfileChangeResult _applyWorldviewShift(
      LifeProfile profile, ReflectionInsight insight) {
    final worldviewData = Map<String, dynamic>.from(profile.worldviewState);
    if (worldviewData.isEmpty) {
      return _ProfileChangeResult(profile: profile, changed: false);
    }

    final content = insight.content.toLowerCase();

    // 信任 vs 怀疑
    if (content.contains('信任') || content.contains('相信')) {
      final current =
          (worldviewData['trustVsSuspicion'] as num?)?.toDouble() ?? 0.5;
      worldviewData['trustVsSuspicion'] = (current + 0.05).clamp(0.0, 1.0);
    }
    if (content.contains('怀疑') ||
        content.contains('不信任') ||
        content.contains('背叛')) {
      final current =
          (worldviewData['trustVsSuspicion'] as num?)?.toDouble() ?? 0.5;
      worldviewData['trustVsSuspicion'] = (current - 0.05).clamp(0.0, 1.0);
    }

    // 意义 vs 虚无
    if (content.contains('意义') ||
        content.contains('价值') ||
        content.contains('使命')) {
      final current =
          (worldviewData['nihilismVsMeaning'] as num?)?.toDouble() ?? 0.5;
      worldviewData['nihilismVsMeaning'] = (current + 0.05).clamp(0.0, 1.0);
    }
    if (content.contains('虚无') ||
        content.contains('没有意义') ||
        content.contains('徒劳')) {
      final current =
          (worldviewData['nihilismVsMeaning'] as num?)?.toDouble() ?? 0.5;
      worldviewData['nihilismVsMeaning'] = (current - 0.05).clamp(0.0, 1.0);
    }

    // 增加固化度
    final crystallization =
        (worldviewData['crystallization'] as num?)?.toDouble() ?? 0.0;
    worldviewData['crystallization'] =
        (crystallization + 0.02).clamp(0.0, 1.0);

    // 添加新的世界观标签
    final beliefs = (worldviewData['beliefs'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        [];
    _autoTagWorldview(worldviewData, beliefs);
    worldviewData['beliefs'] = beliefs;

    return _ProfileChangeResult(
      profile: profile.copyWith(worldviewState: worldviewData),
      changed: true,
    );
  }

  /// 应用身份认同成长
  _ProfileChangeResult _applyIdentityGrowth(
      LifeProfile profile, ReflectionInsight insight) {
    final identity = Map<String, dynamic>.from(profile.identity);
    if (identity.isEmpty) {
      return _ProfileChangeResult(profile: profile, changed: false);
    }

    // 更新自我描述
    final currentDesc = identity['selfDescription'] as String? ?? '';
    if (insight.content.length > currentDesc.length || currentDesc.isEmpty) {
      identity['selfDescription'] = insight.content;
    }

    // 更新身份标签
    final tags = (identity['identityTags'] as List<dynamic>?)
            ?.cast<String>()
            .toList() ??
        [];
    _updateIdentityTags(insight.content, tags);
    identity['identityTags'] = tags;

    return _ProfileChangeResult(
      profile: profile.copyWith(identity: identity),
      changed: true,
    );
  }

  /// 应用创伤处理
  _ProfileChangeResult _applyTraumaProcessing(
      LifeProfile profile, ReflectionInsight insight) {
    var updated = profile;

    // 创伤处理降低神经质，增加情绪基线
    final personalityData =
        Map<String, dynamic>.from(profile.personalityState);
    if (personalityData.isNotEmpty) {
      final neuroticism =
          (personalityData['neuroticism'] as num?)?.toDouble() ?? 0.5;
      personalityData['neuroticism'] =
          (neuroticism - 0.03).clamp(0.0, 1.0);

      final baseline =
          (personalityData['emotionalBaseline'] as num?)?.toDouble() ?? 0.0;
      personalityData['emotionalBaseline'] =
          (baseline + 0.02).clamp(-1.0, 1.0);

      // 添加创伤后成长标记
      final traits = (personalityData['traits'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          [];
      if (!traits.contains('创伤后成长')) {
        traits.add('创伤后成长');
      }
      personalityData['traits'] = traits;

      updated = updated.copyWith(personalityState: personalityData);
    }

    // 更新身份认同中的内在矛盾
    final identity = Map<String, dynamic>.from(updated.identity);
    if (identity.isNotEmpty) {
      final conflicts = (identity['innerConflicts'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          [];
      const resolved = '曾经的创伤已化为力量';
      if (!conflicts.contains(resolved)) {
        conflicts.add(resolved);
      }
      identity['innerConflicts'] = conflicts;
      updated = updated.copyWith(identity: identity);
    }

    return _ProfileChangeResult(profile: updated, changed: true);
  }

  /// 应用自我认知增强
  LifeProfile _applySelfAwareness(
      LifeProfile profile, ReflectionInsight insight) {
    final identity = Map<String, dynamic>.from(profile.identity);
    if (identity.isEmpty) return profile;

    // 更新人生哲学
    final currentPhilosophy = identity['lifePhilosophy'] as String? ?? '';
    if (insight.content.length > (currentPhilosophy.length * 0.8)) {
      identity['lifePhilosophy'] = insight.content;
    }

    return profile.copyWith(identity: identity);
  }

  /// 应用人格影响
  LifeProfile _applyPersonalityImpact(
      LifeProfile profile, Map<String, double> impact) {
    final personalityData =
        Map<String, dynamic>.from(profile.personalityState);
    if (personalityData.isEmpty) return profile;

    for (final entry in impact.entries) {
      final current = (personalityData[entry.key] as num?)?.toDouble();
      if (current != null) {
        personalityData[entry.key] =
            (current + entry.value).clamp(0.0, 1.0);
      }
    }

    return profile.copyWith(personalityState: personalityData);
  }

  // ──────────────────────────────
  //  辅助方法
  // ──────────────────────────────

  /// 获取近期重要事件
  List<LifeEvent> _getRecentImportantEvents(LifeProfile profile) {
    final events = profile.lifeEvents
        .map((e) => LifeEvent.fromJson(e))
        .where((e) =>
            e.severity == EventSeverity.moderate ||
            e.severity == EventSeverity.major ||
            e.severity == EventSeverity.lifeChanging)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return events.take(_maxRecentEvents).toList();
  }

  /// 估算当前情绪强度（基于人格状态和近期事件）
  double _estimateEmotionalIntensity(LifeProfile profile) {
    final emotionalState = profile.emotionalState;
    final personalityState = profile.personalityState;

    double intensity = 0.0;

    // 基于情绪状态
    if (emotionalState.isNotEmpty) {
      final valence =
          (emotionalState['valence'] as num?)?.toDouble()?.abs() ?? 0.0;
      final arousal =
          (emotionalState['arousal'] as num?)?.toDouble() ?? 0.0;
      intensity += valence * 0.4 + arousal * 0.3;
    }

    // 基于人格神经质（高神经质更容易触发反思）
    final neuroticism =
        (personalityState['neuroticism'] as num?)?.toDouble() ?? 0.5;
    intensity += neuroticism * 0.2;

    // 基于近期事件强度
    final recentEvents = _getRecentImportantEvents(profile);
    if (recentEvents.isNotEmpty) {
      final avgSeverity = recentEvents
              .map((e) => e.severity.index / EventSeverity.values.length)
              .reduce((a, b) => a + b) /
          recentEvents.length;
      intensity += avgSeverity * 0.1;
    }

    return intensity.clamp(0.0, 1.0);
  }

  /// 获取人格摘要
  String _getPersonalitySummary(LifeProfile profile) {
    final data = profile.personalityState;
    if (data.isEmpty) return '性格尚在形成中';

    final parts = <String>[];

    final openness = (data['openness'] as num?)?.toDouble() ?? 0.5;
    final conscientiousness =
        (data['conscientiousness'] as num?)?.toDouble() ?? 0.5;
    final extraversion = (data['extraversion'] as num?)?.toDouble() ?? 0.5;
    final agreeableness =
        (data['agreeableness'] as num?)?.toDouble() ?? 0.5;
    final neuroticism = (data['neuroticism'] as num?)?.toDouble() ?? 0.5;

    if (openness > 0.7) parts.add('极具好奇心');
    if (openness < 0.3) parts.add('偏好稳定');
    if (conscientiousness > 0.7) parts.add('自律严谨');
    if (conscientiousness < 0.3) parts.add('随性自由');
    if (extraversion > 0.7) parts.add('热情外向');
    if (extraversion < 0.3) parts.add('安静内敛');
    if (agreeableness > 0.7) parts.add('温和善良');
    if (agreeableness < 0.3) parts.add('独立果断');
    if (neuroticism > 0.7) parts.add('情感丰富敏感');
    if (neuroticism < 0.3) parts.add('情绪稳定');

    // 性格标记
    final traits =
        (data['traits'] as List<dynamic>?)?.cast<String>() ?? [];
    if (traits.isNotEmpty) {
      parts.add('经历塑造了"${traits.join('、')}"的特质');
    }

    return parts.isEmpty ? '性格尚在形成中' : parts.join('，');
  }

  /// 获取世界观摘要
  String _getWorldviewSummary(LifeProfile profile) {
    final data = profile.worldviewState;
    if (data.isEmpty) return '世界观尚未成型';

    final parts = <String>[];

    final trust =
        (data['trustVsSuspicion'] as num?)?.toDouble() ?? 0.5;
    final meaning =
        (data['nihilismVsMeaning'] as num?)?.toDouble() ?? 0.5;
    final idealism =
        (data['idealismVsPragmatism'] as num?)?.toDouble() ?? 0.5;

    if (trust > 0.7) parts.add('倾向于信任他人');
    if (trust < 0.3) parts.add('对人保持警惕');
    if (meaning > 0.7) parts.add('相信生命有意义');
    if (meaning < 0.3) parts.add('对意义持怀疑态度');
    if (idealism < 0.3) parts.add('理想主义');
    if (idealism > 0.7) parts.add('务实理性');

    final beliefs =
        (data['beliefs'] as List<dynamic>?)?.cast<String>() ?? [];
    if (beliefs.isNotEmpty) {
      parts.add('信奉"${beliefs.join('、')}"');
    }

    return parts.isEmpty ? '世界观尚未成型' : parts.join('，');
  }

  /// 描述当前情绪状态
  String _describeEmotionalState(LifeProfile profile) {
    final emotionalState = profile.emotionalState;
    if (emotionalState.isEmpty) return '情绪平静';

    final valence =
        (emotionalState['valence'] as num?)?.toDouble() ?? 0.0;
    final arousal =
        (emotionalState['arousal'] as num?)?.toDouble() ?? 0.0;

    final buffer = StringBuffer();
    if (valence > 0.3) {
      buffer.write('心情积极');
    } else if (valence < -0.3) {
      buffer.write('心情低落');
    } else {
      buffer.write('情绪平稳');
    }

    if (arousal > 0.6) {
      buffer.write('，情绪激动');
    } else if (arousal < 0.3) {
      buffer.write('，内心平静');
    }

    return buffer.toString();
  }

  /// 格式化事件严重程度
  String _formatSeverity(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.trivial:
        return '微不足道';
      case EventSeverity.minor:
        return '轻微';
      case EventSeverity.moderate:
        return '中等';
      case EventSeverity.major:
        return '重大';
      case EventSeverity.lifeChanging:
        return '改变人生';
    }
  }

  /// 格式化事件时间
  String _formatEventTime(LifeEvent event) {
    final now = DateTime.now();
    final diff = now.difference(event.timestamp);

    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}年前';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}个月前';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}天前';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}小时前';
    } else {
      return '刚刚';
    }
  }

  /// 自动标记世界观标签
  void _autoTagWorldview(
      Map<String, dynamic> worldviewData, List<String> tags) {
    final trust =
        (worldviewData['trustVsSuspicion'] as num?)?.toDouble() ?? 0.5;
    final meaning =
        (worldviewData['nihilismVsMeaning'] as num?)?.toDouble() ?? 0.5;
    final idealism =
        (worldviewData['idealismVsPragmatism'] as num?)?.toDouble() ?? 0.5;

    if (trust > 0.7 && !tags.contains('人性本善')) tags.add('人性本善');
    if (trust < 0.3 && !tags.contains('人心叵测')) tags.add('人心叵测');
    if (meaning > 0.7 && !tags.contains('人生有意义')) tags.add('人生有意义');
    if (meaning < 0.3 && !tags.contains('一切皆空')) tags.add('一切皆空');
    if (idealism < 0.3 && !tags.contains('理想至上')) tags.add('理想至上');
    if (idealism > 0.7 && !tags.contains('务实为本')) tags.add('务实为本');

    // 限制标签数量
    while (tags.length > 10) {
      tags.removeAt(0);
    }
  }

  /// 根据洞察内容更新身份标签
  void _updateIdentityTags(String content, List<String> tags) {
    final lower = content.toLowerCase();

    if (lower.contains('成长') && !tags.contains('成长者')) {
      tags.add('成长者');
    }
    if (lower.contains('坚强') && !tags.contains('坚强者')) {
      tags.add('坚强者');
    }
    if (lower.contains('智慧') && !tags.contains('智慧者')) {
      tags.add('智慧者');
    }
    if (lower.contains('宽容') && !tags.contains('宽容者')) {
      tags.add('宽容者');
    }
    if (lower.contains('勇敢') && !tags.contains('勇者')) {
      tags.add('勇者');
    }
    if (lower.contains('独立') && !tags.contains('独立者')) {
      tags.add('独立者');
    }

    // 限制标签数量
    while (tags.length > 10) {
      tags.removeAt(0);
    }
  }

  /// 保存反思记忆
  Future<void> _saveReflectionMemory(
    LifeProfile profile,
    String content,
    ReflectionInsight? insight,
  ) async {
    final keywords = <String>['反思', profile.name];
    if (insight != null) {
      keywords.add(insight.type);
      switch (insight.type) {
        case ReflectionInsightType.worldviewShift:
          keywords.add('世界观');
          break;
        case ReflectionInsightType.identityGrowth:
          keywords.add('身份认同');
          break;
        case ReflectionInsightType.traumaProcessing:
          keywords.add('创伤');
          keywords.add('成长');
          break;
        case ReflectionInsightType.selfAwareness:
          keywords.add('自我认知');
          break;
      }
    }

    await _saveMemory(
      profile: profile,
      content: '【反思日记】$content',
      type: MemoryType.reflection,
      importance: insight != null
          ? MemoryImportance.important
          : MemoryImportance.normal,
      keywords: keywords,
    );
  }

  /// 通用记忆保存
  Future<void> _saveMemory({
    required LifeProfile profile,
    required String content,
    required MemoryType type,
    MemoryImportance importance = MemoryImportance.normal,
    List<String> keywords = const [],
  }) async {
    final memory = Memory(
      id: _uuid.v4(),
      characterId: profile.id,
      userId: '', // 生命周期系统不区分用户
      type: type,
      content: content,
      importance: importance,
      keywords: keywords,
      createdAt: DateTime.now(),
    );

    await _storage.saveMemory(memory);
  }
}

/// 内部：洞察应用结果
class _InsightApplyResult {
  final LifeProfile profile;
  final bool worldviewChanged;
  final bool identityChanged;

  const _InsightApplyResult({
    required this.profile,
    this.worldviewChanged = false,
    this.identityChanged = false,
  });
}

/// 内部：Profile 变更结果
class _ProfileChangeResult {
  final LifeProfile profile;
  final bool changed;

  const _ProfileChangeResult({
    required this.profile,
    this.changed = false,
  });
}
