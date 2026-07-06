import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_character.dart';
import '../models/memory.dart';
import '../repositories/local_storage_repository.dart';
import '../utils/response_decoder.dart';
import '../config/constants.dart';
import 'core_hub.dart';
import 'memory_engine.dart';

/// 人设进化服务
///
/// 改造要点：
/// 1. 移除心跳服务依赖，改为前台主动触发
/// 2. 无论进化结果如何，都记录成长事件
/// 3. 新增重大事件识别逻辑
/// 4. 新增剩余消息数查询接口
/// 5. 人格成长与记忆库双向打通
/// 6. 首次运行时批量补算历史进化事件
class PersonaEvolutionService {
  final LocalStorageRepository _storage;
  final MemoryEngine _memoryEngine;

  PersonaEvolutionService(this._storage, this._memoryEngine);

  String _key(String characterId, String suffix) =>
      'persona_evo_${characterId}_$suffix';

  CoreAnchor? getCoreAnchor(String characterId) {
    final json = _storage.getString(_key(characterId, 'anchor'));
    if (json == null) return null;
    try {
      return CoreAnchor.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCoreAnchor(String characterId, CoreAnchor anchor) async {
    await _storage.setString(
      _key(characterId, 'anchor'),
      jsonEncode(anchor.toJson()),
    );
  }

  String? getEvolvedStyle(String characterId) {
    return _storage.getString(_key(characterId, 'style'));
  }

  int getEvolutionCount(String characterId) {
    return _storage.getInt(_key(characterId, 'count')) ?? 0;
  }

  double getDriftSignal(String characterId, String dimension) {
    return _storage.getDouble(_key(characterId, 'signal_$dimension')) ?? 0.0;
  }

  Future<void> _setDriftSignal(
    String characterId,
    String dimension,
    double value,
  ) async {
    await _storage.setDouble(
      _key(characterId, 'signal_$dimension'),
      value.clamp(0.0, 1.0),
    );
  }

  List<EvolutionLog> getChangelog(String characterId) {
    final json = _storage.getString(_key(characterId, 'changelog'));
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => EvolutionLog.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveChangelog(
    String characterId,
    List<EvolutionLog> logs,
  ) async {
    final trimmed = logs.length > 20 ? logs.sublist(logs.length - 20) : logs;
    await _storage.setString(
      _key(characterId, 'changelog'),
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> initializeAnchor(AICharacter character) async {
    final storage = await SharedPreferences.getInstance();
    final anchorKey = 'persona_evo_${character.id}_anchor';
    if (storage.getString(anchorKey) != null) return;

    final anchor = CoreAnchor(
      personality: character.personality,
      coreDesire: character.coreDesire,
      moralBoundary: character.moralBoundary,
      extractedAt: DateTime.now(),
    );

    await storage.setString(anchorKey, jsonEncode(anchor.toJson()));
    debugPrint('PersonaEvolution: anchor initialized for ${character.name}');
  }

  static String buildImmutableAnchorJson(AICharacter character) {
    return jsonEncode({
      'personality': character.personality,
      'coreDesire': character.coreDesire,
      'moralBoundary': character.moralBoundary,
      'backgroundStory': character.backgroundStory,
      'worldSetting': character.worldSetting,
      'createdAt': character.createdAt.toIso8601String(),
    });
  }

  static String buildTraitSummaryFromAnchor(String? currentAnchorJson) {
    if (currentAnchorJson == null || currentAnchorJson.isEmpty) {
      return '当前人格状态稳定，整体表达自然亲切。';
    }
    try {
      final map = jsonDecode(currentAnchorJson) as Map<String, dynamic>;
      double read(String key) => (map[key] as num?)?.toDouble() ?? 0.5;
      final aggressiveness = read('aggressiveness');
      final warmth = read('warmth');
      final restraint = read('restraint');
      final trust = read('trust');
      String level(double v, {String low = '较低', String mid = '中等', String high = '较高'}) {
        if (v <= 0.33) return low;
        if (v >= 0.67) return high;
        return mid;
      }
      return '当前人格状态：攻击性${level(aggressiveness, low: '较低', mid: '中等', high: '较高')}，亲近感${level(warmth, low: '偏弱', mid: '中等', high: '较强')}，克制度${level(restraint, low: '偏低', mid: '中等', high: '较高')}，信任感${level(trust, low: '偏低', mid: '中等', high: '较高')}。';
    } catch (_) {
      return '当前人格状态稳定，整体表达自然亲切。';
    }
  }

  static String formatDeltaSummary(Map<String, double> deltas) {
    if (deltas.isEmpty) return '本次没有记录到明确的人格维度变化';
    final labels = {
      'aggressiveness': '攻击性',
      'warmth': '亲近感',
      'restraint': '克制度',
      'trust': '信任感',
    };
    final parts = <String>[];
    for (final entry in deltas.entries) {
      final label = labels[entry.key] ?? entry.key;
      final arrow = entry.value >= 0 ? '↑' : '↓';
      parts.add('$label$arrow');
    }
    return parts.join('、');
  }

  /// 判断是否应该触发日常进化
  bool shouldEvolve(String characterId, int totalMessages) {
    final count = getEvolutionCount(characterId);
    const interval = 200;
    return totalMessages > 0 && totalMessages ~/ interval > count;
  }

  /// 获取距离下次日常进化还需要的消息数
  int getMessagesUntilNextEvolution(String characterId, int totalMessages) {
    final count = getEvolutionCount(characterId);
    const interval = 200;
    final nextThreshold = (count + 1) * interval;
    final remaining = nextThreshold - totalMessages;
    return remaining > 0 ? remaining : 0;
  }

  Future<bool> ensurePersonaFoundation(AICharacter character) async {
    var changed = false;
    if (getCoreAnchor(character.id) == null) {
      await initializeAnchor(character);
      changed = true;
    }

    if ((character.immutableAnchor?.isEmpty ?? true) ||
        (character.currentAnchor?.isEmpty ?? true)) {
      final updated = character.copyWith(
        immutableAnchor: buildImmutableAnchorJson(character),
        currentAnchor: jsonEncode({
          'aggressiveness': 0.5,
          'warmth': 0.5,
          'restraint': 0.5,
          'trust': 0.5,
        }),
      );
      await _storage.saveAICharacter(updated);
      await _saveInitialSnapshot(updated);
      changed = true;
    }
    return changed;
  }

  /// 核心进化方法（改造：无论结果如何都记录成长事件，记忆库双向打通）
  Future<bool> evolve({
    required AICharacter character,
    required String userId,
    bool allowQualitative = false,
    String? majorEventDescription,
  }) async {
    final anchor = getCoreAnchor(character.id);
    if (anchor == null) {
      await initializeAnchor(character);
      return false;
    }

    await ensurePersonaFoundation(character);

    try {
      // ── 读取逻辑：从记忆库加载历史人格状态 ──
      final personaMemory = await _loadPersonaFromMemory(character.id, userId);
      if (personaMemory != null) {
        debugPrint('PersonaEvolution: 从记忆库加载历史人格状态 ${character.name}');
        // 数据对齐：如果记忆库有更完整的人格数据，以记忆库为准
        await _alignDataWithMemory(character, personaMemory, userId);
      }

      final memories = await _memoryEngine.buildConsolidatedMemoryPrompt(
        character: character,
        userId: userId,
        currentMessage: '',
      );

      final currentStyle =
          getEvolvedStyle(character.id) ?? character.languageStyle ?? '自然亲切';
      final evolutionCount = getEvolutionCount(character.id);
      final mode = allowQualitative && character.qualitativeEvolutionEnabled
          ? EvolutionMode.qualitative
          : EvolutionMode.micro;

      final prompt = _buildEvolutionPrompt(
        character: character,
        anchor: anchor,
        currentStyle: currentStyle,
        memories: memories,
        evolutionCount: evolutionCount,
        mode: mode,
        majorEventDescription: majorEventDescription,
      );

      final config = await _storage.getActiveAIConfig();
      if (config == null) {
        // 无可用配置，记录失败事件
        await _recordGrowthEvent(
          characterId: character.id,
          userId: userId,
          triggerType: allowQualitative ? 'major_event' : 'micro',
          mode: mode,
          deltas: {},
          impactScore: 0.0,
          reason: '无可用AI配置，进化跳过',
          triggerData: {'majorEventDescription': majorEventDescription},
        );
        return false;
      }

      final response = await _callLLM(config, prompt);
      if (response.isEmpty) {
        await _recordGrowthEvent(
          characterId: character.id,
          userId: userId,
          triggerType: allowQualitative ? 'major_event' : 'micro',
          mode: mode,
          deltas: {},
          impactScore: 0.0,
          reason: 'LLM返回为空，进化跳过',
          triggerData: {'majorEventDescription': majorEventDescription},
        );
        return false;
      }

      final result = _parseEvolutionResult(response);
      if (result == null) {
        await _recordGrowthEvent(
          characterId: character.id,
          userId: userId,
          triggerType: allowQualitative ? 'major_event' : 'micro',
          mode: mode,
          deltas: {},
          impactScore: 0.0,
          reason: '解析进化结果失败',
          triggerData: {'majorEventDescription': majorEventDescription},
        );
        return false;
      }

      // 锚点被推翻，记录并衰减
      if (!result.anchorPreserved) {
        await _decaySignals(character.id);
        await _recordGrowthEvent(
          characterId: character.id,
          userId: userId,
          triggerType: allowQualitative ? 'major_event' : 'micro',
          mode: mode,
          deltas: {},
          impactScore: 0.0,
          reason: '人格锚点被推翻，进化被拒绝',
          triggerData: {'majorEventDescription': majorEventDescription},
        );
        return false;
      }

      // 无需改变 —— 仍然记录成长事件
      if (result.style == currentStyle && result.changes == '无需改变') {
        await _decaySignals(character.id);
        await _recordGrowthEvent(
          characterId: character.id,
          userId: userId,
          triggerType: allowQualitative ? 'major_event' : 'micro',
          mode: mode,
          deltas: {},
          impactScore: 0.0,
          reason: allowQualitative
              ? '重大事件质变：当前人格状态稳定，暂未调整'
              : '日常进化：当前人格状态稳定，暂未调整',
          triggerData: {'majorEventDescription': majorEventDescription},
        );
        // 仍然递增进化计数，避免重复触发
        await _storage.setInt(_key(character.id, 'count'), evolutionCount + 1);
        return false;
      }

      // 进化成功
      await _storage.setString(_key(character.id, 'style'), result.style);
      await _storage.setInt(_key(character.id, 'count'), evolutionCount + 1);
      await _boostSignals(character.id, result.deltas.keys.toList());

      final changelog = getChangelog(character.id);
      changelog.add(EvolutionLog(
        version: evolutionCount + 1,
        styleBefore: currentStyle,
        styleAfter: result.style,
        changes: result.changes,
        timestamp: DateTime.now(),
        mode: result.mode.name,
      ));
      await _saveChangelog(character.id, changelog);

      // 记录成长事件
      await _recordGrowthEvent(
        characterId: character.id,
        userId: userId,
        triggerType: allowQualitative ? 'major_event' : 'micro',
        mode: result.mode,
        deltas: result.deltas,
        impactScore: result.impactScore,
        reason: allowQualitative
            ? '重大事件质变：${result.changes}'
            : '日常进化：${result.changes}',
        triggerData: {'majorEventDescription': majorEventDescription},
      );

      if (result.mode == EvolutionMode.qualitative) {
        final updatedAnchorCharacter = character.copyWith(
          currentAnchor: jsonEncode(result.deltas),
        );
        await _storage.saveAICharacter(updatedAnchorCharacter);
      }

      // Sync evolved traits to Core Hub rule registry
      try {
        final evolvedAnchorJson = result.mode == EvolutionMode.qualitative
            ? jsonEncode(result.deltas)
            : character.currentAnchor;
        final characterData = {
          'id': character.id,
          'personality': character.personality,
          'currentAnchor': evolvedAnchorJson,
        };
        CoreHub.instance.updateCharacterRule(character.id, characterData);
      } catch (e) {
        debugPrint('PersonaEvolution: failed to sync rule to CoreHub — $e');
      }

      // ── 写入同步：将最新人格信息同步保存到记忆库 ──
      await _savePersonaToMemory(
        characterId: character.id,
        userId: userId,
        evolvedStyle: result.style,
        changes: result.changes,
        deltas: result.deltas,
        mode: mode,
        evolutionCount: evolutionCount + 1,
      );

      debugPrint(
        'PersonaEvolution: ${character.name} evolved #${evolutionCount + 1}: ${result.changes}',
      );
      return true;
    } catch (e) {
      debugPrint('PersonaEvolution failed: $e');
      await _recordGrowthEvent(
        characterId: character.id,
        userId: userId,
        triggerType: allowQualitative ? 'major_event' : 'micro',
        mode: allowQualitative ? EvolutionMode.qualitative : EvolutionMode.micro,
        deltas: {},
        impactScore: 0.0,
        reason: '进化异常：$e',
        triggerData: {'majorEventDescription': majorEventDescription},
      );
      return false;
    }
  }

  // ═══════════════════════════════════════════
  // 记忆库双向打通
  // ═══════════════════════════════════════════

  /// 从记忆库加载历史人格状态
  Future<Memory?> _loadPersonaFromMemory(String characterId, String userId) async {
    try {
      final memories = await _storage.getMemories(
        characterId: characterId,
        userId: userId,
        type: MemoryType.state,
        limit: 10,
      );
      // 找到最新的 persona_evolution 类型记忆
      for (final m in memories) {
        if (m.keywords.contains('persona_evolution')) {
          return m;
        }
      }
      return null;
    } catch (e) {
      debugPrint('PersonaEvolution: 从记忆库加载人格状态失败: $e');
      return null;
    }
  }

  /// 将最新人格信息同步保存到记忆库
  Future<void> _savePersonaToMemory({
    required String characterId,
    required String userId,
    required String evolvedStyle,
    required String changes,
    required Map<String, double> deltas,
    required EvolutionMode mode,
    required int evolutionCount,
  }) async {
    try {
      await _storage.saveMemory(Memory(
        id: 'persona_evo_${characterId}_$evolutionCount',
        characterId: characterId,
        userId: userId,
        type: MemoryType.state,
        content: '人格进化记录：$changes',
        importance: MemoryImportance.important,
        keywords: ['persona_evolution', mode.name, 'evolution_$evolutionCount'],
        createdAt: DateTime.now(),
        weight: 1.5,
        pinned: true,
      ));

      debugPrint('PersonaEvolution: 人格信息已同步到记忆库 $characterId #$evolutionCount');
    } catch (e) {
      debugPrint('PersonaEvolution: 同步人格信息到记忆库失败: $e');
    }
  }

  /// 数据对齐：如果记忆库有更完整的人格数据，以记忆库为准进行校正
  Future<void> _alignDataWithMemory(
    AICharacter character,
    Memory personaMemory,
    String userId,
  ) async {
    try {
      // 从记忆内容中解析人格数据
      final memoryData = jsonDecode(personaMemory.content) as Map<String, dynamic>?;
      if (memoryData == null) return;

      final memoryEvolutionCount = memoryData['evolutionCount'] as int? ?? 0;
      final currentEvolutionCount = getEvolutionCount(character.id);

      // 如果记忆库的进化次数更多，说明成长记录可能不完整，以记忆库为准
      if (memoryEvolutionCount > currentEvolutionCount) {
        debugPrint('PersonaEvolution: 数据对齐 - 记忆库进化次数 $memoryEvolutionCount > 当前 $currentEvolutionCount');
        await _storage.setInt(_key(character.id, 'count'), memoryEvolutionCount);

        // 如果记忆库有更完整的进化风格，也同步过来
        final memoryStyle = memoryData['evolvedStyle'] as String?;
        if (memoryStyle != null && memoryStyle.isNotEmpty) {
          await _storage.setString(_key(character.id, 'style'), memoryStyle);
        }
      }
    } catch (e) {
      debugPrint('PersonaEvolution: 数据对齐失败: $e');
    }
  }

  // ═══════════════════════════════════════════
  // 历史补全：首次运行时批量补算旧版本遗漏的进化事件
  // ═══════════════════════════════════════════

  /// 补算历史进化事件（首次运行时调用）
  Future<void> backfillEvolutionHistory({
    required AICharacter character,
    required String userId,
    required int totalMessages,
  }) async {
    // 检查是否已经补算过
    final backfillKey = _key(character.id, 'backfilled');
    final alreadyBackfilled = _storage.getString(backfillKey) == 'true';
    if (alreadyBackfilled) return;

    debugPrint('PersonaEvolution: 开始补算历史进化事件 ${character.name} (消息数: $totalMessages)');

    try {
      final currentEvolutionCount = getEvolutionCount(character.id);
      final expectedEvolutionCount = totalMessages ~/ 200;

      // 如果已有进化记录，说明不是首次运行，跳过补算
      if (currentEvolutionCount > 0) {
        await _storage.setString(backfillKey, 'true');
        return;
      }

      // 补算逻辑：按每200条消息触发一次，批量记录成长事件
      final eventsToCreate = expectedEvolutionCount - currentEvolutionCount;
      if (eventsToCreate <= 0) {
        await _storage.setString(backfillKey, 'true');
        return;
      }

      debugPrint('PersonaEvolution: 需要补算 $eventsToCreate 个历史进化事件');

      // 批量创建成长事件（不调用LLM，只记录历史）
      for (int i = 0; i < eventsToCreate; i++) {
        final messageThreshold = (currentEvolutionCount + i + 1) * 200;
        await _recordGrowthEvent(
          characterId: character.id,
          userId: userId,
          triggerType: 'micro',
          mode: EvolutionMode.micro,
          deltas: {},
          impactScore: 0.0,
          reason: '历史补全：消息数达到 $messageThreshold 条时的日常进化',
          triggerData: {'backfill': true, 'messageThreshold': messageThreshold},
        );

        // 同步到记忆库
        await _savePersonaToMemory(
          characterId: character.id,
          userId: userId,
          evolvedStyle: character.languageStyle ?? '自然亲切',
          changes: '历史补全：第 ${i + 1} 次日常进化',
          deltas: {},
          mode: EvolutionMode.micro,
          evolutionCount: currentEvolutionCount + i + 1,
        );
      }

      // 更新进化计数
      await _storage.setInt(_key(character.id, 'count'), expectedEvolutionCount);
      await _storage.setString(backfillKey, 'true');

      debugPrint('PersonaEvolution: 历史补全完成 ${character.name}，共补算 $eventsToCreate 个事件');
    } catch (e) {
      debugPrint('PersonaEvolution: 历史补全失败: $e');
    }
  }

  /// 前台主动触发：检查并执行日常进化（供聊天模块调用）
  Future<void> checkAndEvolve({
    required AICharacter character,
    required String userId,
    required int totalMessages,
  }) async {
    // 检查开关
    if (!character.evolutionEnabled) return;

    // 首次运行时补算历史进化事件
    await backfillEvolutionHistory(
      character: character,
      userId: userId,
      totalMessages: totalMessages,
    );

    // 检查是否达到进化阈值
    if (!shouldEvolve(character.id, totalMessages)) return;

    debugPrint('PersonaEvolution: 触发日常进化 ${character.name} (消息数: $totalMessages)');

    // 异步执行，不阻塞聊天
    await evolve(
      character: character,
      userId: userId,
      allowQualitative: false,
    );
  }

  /// 重大事件识别与触发（供聊天模块调用）
  Future<void> checkMajorEvent({
    required AICharacter character,
    required String userId,
    required String userMessage,
    required int totalMessages,
    required int sessionMessageCount,
    required Duration sessionDuration,
  }) async {
    // 检查开关
    if (!character.qualitativeEvolutionEnabled) return;

    // 识别重大事件
    final eventDescription = detectMajorEvent(
      userMessage: userMessage,
      sessionMessageCount: sessionMessageCount,
      sessionDuration: sessionDuration,
    );

    if (eventDescription == null) return;

    debugPrint('PersonaEvolution: 检测到重大事件 ${character.name}: $eventDescription');

    // 异步执行质变
    await evolve(
      character: character,
      userId: userId,
      allowQualitative: true,
      majorEventDescription: eventDescription,
    );
  }

  /// 本地重大事件识别规则
  String? detectMajorEvent({
    required String userMessage,
    required int sessionMessageCount,
    required Duration sessionDuration,
  }) {
    // 规则1：关键词识别
    final majorKeywords = [
      '难过', '委屈', '崩溃', '迷茫', '离别', '告白', '决心',
      '分手', '去世', '死亡', '绝望', '害怕', '恐惧', '孤独',
      '思念', '想念', '喜欢你', '爱你', '恨你', '讨厌',
      '毕业', '离开', '告别', '对不起', '谢谢',
      '第一次', '最后一次', '永远', '一辈子',
    ];

    final lowerMessage = userMessage.toLowerCase();
    for (final keyword in majorKeywords) {
      if (lowerMessage.contains(keyword)) {
        return '用户表达了强烈情感：包含关键词「$keyword」';
      }
    }

    // 规则2：单次连续对话时长超过60分钟
    if (sessionDuration.inMinutes >= 60) {
      return '持续深度对话超过${sessionDuration.inMinutes}分钟';
    }

    // 规则3：单次对话消息量突破阈值（50条以上）
    if (sessionMessageCount >= 50) {
      return '单次对话消息量达到${sessionMessageCount}条，为深度互动';
    }

    return null;
  }

  Future<bool> rollback(String characterId, int version) async {
    final changelog = getChangelog(characterId);
    EvolutionLog? target;
    for (final log in changelog) {
      if (log.version == version) {
        target = log;
        break;
      }
    }
    if (target == null) return false;

    await _storage.setString(_key(characterId, 'style'), target.styleBefore);
    await _storage.setInt(_key(characterId, 'count'), version - 1);

    final filtered = changelog.where((l) => l.version < version).toList();
    await _saveChangelog(characterId, filtered);

    // After rollback, sync updated rule to Core Hub
    try {
      final character = await _storage.getAICharacter(characterId);
      if (character != null) {
        final characterData = {
          'id': character.id,
          'personality': character.personality,
          'currentAnchor': character.currentAnchor ?? '',
        };
        CoreHub.instance.updateCharacterRule(characterId, characterData);
      }
    } catch (_) {}

    return true;
  }

  Future<AICharacter?> restoreInitialSnapshot(AICharacter character) async {
    final raw = _storage.getString(_key(character.id, 'snapshot_initial'));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final surfaceData = (map['surfaceData'] as Map<String, dynamic>?) ?? {};
      final restored = character.copyWith(
        languageStyle: surfaceData['languageStyle'] as String?,
        catchphrases: surfaceData['catchphrases'] as String?,
        openingLine: surfaceData['openingLine'] as String?,
        currentAnchor: map['traitsData'] as String?,
        evolutionEnabled: true,
        qualitativeEvolutionEnabled: false,
      );
      await _storage.saveAICharacter(restored);
      await _storage.setString(_key(character.id, 'style'), restored.languageStyle ?? '自然亲切');
      await _storage.setInt(_key(character.id, 'count'), 0);
      for (final dimension in const ['aggressiveness', 'warmth', 'restraint', 'trust']) {
        await _setDriftSignal(character.id, dimension, 0.0);
      }
      await _storage.setString(_key(character.id, 'growth_events'), '[]');
      await _storage.setString(_key(character.id, 'changelog'), '[]');

      // After restore, sync updated rule to Core Hub
      try {
        final characterData = {
          'id': restored.id,
          'personality': restored.personality,
          'currentAnchor': restored.currentAnchor ?? '',
        };
        CoreHub.instance.updateCharacterRule(restored.id, characterData);
      } catch (_) {}

      return restored;
    } catch (e) {
      debugPrint('PersonaEvolution restoreInitialSnapshot failed: $e');
      return null;
    }
  }

  Map<String, dynamic> getStatus(String characterId) {
    final anchor = getCoreAnchor(characterId);
    final style = getEvolvedStyle(characterId);
    final count = getEvolutionCount(characterId);
    final changelog = getChangelog(characterId);

    return {
      'anchor': anchor != null
          ? {
              'personality': anchor.personality,
              'coreDesire': anchor.coreDesire,
              'moralBoundary': anchor.moralBoundary,
            }
          : null,
      'evolvedStyle': style,
      'evolutionCount': count,
      'changelogLength': changelog.length,
      'driftSignals': {
        'aggressiveness': getDriftSignal(characterId, 'aggressiveness'),
        'warmth': getDriftSignal(characterId, 'warmth'),
        'restraint': getDriftSignal(characterId, 'restraint'),
        'trust': getDriftSignal(characterId, 'trust'),
      }
    };
  }

  String _buildEvolutionPrompt({
    required AICharacter character,
    required CoreAnchor anchor,
    required String currentStyle,
    required String memories,
    required int evolutionCount,
    required EvolutionMode mode,
    String? majorEventDescription,
  }) {
    final qualitative = mode == EvolutionMode.qualitative;
    return '''你是角色人格进化评估系统，需要判断角色是否应该发生表达方式演化。

【角色核心锚点 - 不可直接推翻】
性格：${anchor.personality}
核心欲望：${anchor.coreDesire}
道德底线：${anchor.moralBoundary}

【当前表达风格】
$currentStyle

【互动记忆】
${memories.isEmpty ? '（暂无记忆）' : memories}

【当前模式】${qualitative ? '重大事件质变' : '日常微进化'}
${majorEventDescription != null ? '【重大事件】\n$majorEventDescription\n' : ''}
【进化次数】第 ${evolutionCount + 1} 次

任务：
1. 判断是否需要进化
2. 只允许调整表达方式、亲密度、语言克制程度，不允许直接推翻核心身份
3. ${qualitative ? '如果是重大事件质变，可以允许变化更明显，但仍必须保持还是同一个人' : '如果是日常微进化，变化必须很小'}

输出 JSON：
{"style":"新的语言风格（50字内）","changes":"变化摘要（30字内）","anchor_preserved":true,"mode":"${qualitative ? 'qualitative' : 'micro'}","impact_score":${qualitative ? '0.0~1.0' : '0.0'},"deltas":{"aggressiveness":-0.05,"warmth":0.03,"restraint":0.04,"trust":0.02}}

如果不需要改变，输出：
{"style":"$currentStyle","changes":"无需改变","anchor_preserved":true,"mode":"${qualitative ? 'qualitative' : 'micro'}","impact_score":0.0,"deltas":{}}''';
  }

  _EvolutionResult? _parseEvolutionResult(String response) {
    try {
      String jsonStr = response.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch == null) return null;
      jsonStr = jsonMatch.group(0)!;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final rawMode = (map['mode'] as String? ?? 'micro').trim();
      final deltasRaw = map['deltas'];
      final deltas = <String, double>{};
      if (deltasRaw is Map<String, dynamic>) {
        for (final entry in deltasRaw.entries) {
          final value = entry.value;
          if (value is num) {
            deltas[entry.key] = value.toDouble();
          }
        }
      }
      return _EvolutionResult(
        style: (map['style'] as String?) ?? '',
        changes: (map['changes'] as String?) ?? '',
        anchorPreserved: (map['anchor_preserved'] as bool?) ?? false,
        mode: rawMode == 'qualitative'
            ? EvolutionMode.qualitative
            : EvolutionMode.micro,
        impactScore: (map['impact_score'] as num?)?.toDouble() ?? 0.0,
        deltas: deltas,
      );
    } catch (e) {
      debugPrint('PersonaEvolution parse failed: $e');
      return null;
    }
  }

  Future<void> _saveInitialSnapshot(AICharacter character) async {
    await _storage.setString(
      _key(character.id, 'snapshot_initial'),
      jsonEncode({
        'traitsData': character.currentAnchor ??
            jsonEncode({
              'aggressiveness': 0.5,
              'warmth': 0.5,
              'restraint': 0.5,
              'trust': 0.5,
            }),
        'surfaceData': {
          'languageStyle': character.languageStyle,
          'catchphrases': character.catchphrases,
          'openingLine': character.openingLine,
        },
        'createdAt': DateTime.now().toIso8601String(),
        'label': '创建时',
      }),
    );
  }

  Future<void> _recordGrowthEvent({
    required String characterId,
    required String userId,
    required String triggerType,
    required EvolutionMode mode,
    required Map<String, double> deltas,
    required double impactScore,
    required String reason,
    required Map<String, dynamic> triggerData,
  }) async {
    final logs = getStoredGrowthEvents(characterId);
    logs.add(GrowthEvent(
      id: '${DateTime.now().millisecondsSinceEpoch}_$characterId',
      characterId: characterId,
      userId: userId,
      triggerType: triggerType,
      evolutionMode: mode.name,
      triggerData: triggerData,
      deltas: deltas,
      impactScore: impactScore,
      reason: reason,
      createdAt: DateTime.now(),
    ));
    final trimmed = logs.length > 50 ? logs.sublist(logs.length - 50) : logs;
    await _storage.setString(
      _key(characterId, 'growth_events'),
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  List<GrowthEvent> getStoredGrowthEvents(String characterId) {
    final json = _storage.getString(_key(characterId, 'growth_events'));
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => GrowthEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _decaySignals(String characterId) async {
    for (final dimension in const ['aggressiveness', 'warmth', 'restraint', 'trust']) {
      final current = getDriftSignal(characterId, dimension);
      await _setDriftSignal(characterId, dimension, current * 0.2);
    }
  }

  Future<void> _boostSignals(String characterId, List<String> dimensions) async {
    for (final dimension in dimensions) {
      final current = getDriftSignal(characterId, dimension);
      await _setDriftSignal(characterId, dimension, current + 0.1);
    }
  }

  Future<String> _callLLM(dynamic config, String prompt) async {
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey}',
      },
      body: jsonEncode({
        'model': config.modelName,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        if (BuiltInAIProviders.isGlmZ19B(config.id, config.modelName)) ...{
          'temperature': GlmModeParams.personaTemperature,
          'top_p': GlmModeParams.topP,
          'top_k': GlmModeParams.personaTopK,
          'frequency_penalty': GlmModeParams.personaFrequencyPenalty,
          'thinking_budget': GlmModeParams.personaThinkingBudget,
          'max_tokens': GlmModeParams.personaMaxTokens,
        } else ...{
          'temperature': 0.5,
        },
        'max_tokens': 260,
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return ResponseDecoder.extractContent(data);
    }
    return '';
  }
}

class CoreAnchor {
  final String personality;
  final String coreDesire;
  final String moralBoundary;
  final DateTime extractedAt;

  const CoreAnchor({
    required this.personality,
    required this.coreDesire,
    required this.moralBoundary,
    required this.extractedAt,
  });

  Map<String, dynamic> toJson() => {
        'personality': personality,
        'coreDesire': coreDesire,
        'moralBoundary': moralBoundary,
        'extractedAt': extractedAt.millisecondsSinceEpoch,
      };

  factory CoreAnchor.fromJson(Map<String, dynamic> json) => CoreAnchor(
        personality: json['personality'] as String? ?? '',
        coreDesire: json['coreDesire'] as String? ?? '',
        moralBoundary: json['moralBoundary'] as String? ?? '',
        extractedAt: DateTime.fromMillisecondsSinceEpoch(
          json['extractedAt'] as int? ?? 0,
        ),
      );
}

class EvolutionLog {
  final int version;
  final String styleBefore;
  final String styleAfter;
  final String changes;
  final DateTime timestamp;
  final String mode;

  const EvolutionLog({
    required this.version,
    required this.styleBefore,
    required this.styleAfter,
    required this.changes,
    required this.timestamp,
    this.mode = 'micro',
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'styleBefore': styleBefore,
        'styleAfter': styleAfter,
        'changes': changes,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'mode': mode,
      };

  factory EvolutionLog.fromJson(Map<String, dynamic> json) => EvolutionLog(
        version: json['version'] as int? ?? 0,
        styleBefore: json['styleBefore'] as String? ?? '',
        styleAfter: json['styleAfter'] as String? ?? '',
        changes: json['changes'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['timestamp'] as int? ?? 0,
        ),
        mode: json['mode'] as String? ?? 'micro',
      );
}

enum EvolutionMode { micro, qualitative }

class GrowthEvent {
  final String id;
  final String characterId;
  final String userId;
  final String triggerType;
  final String evolutionMode;
  final Map<String, dynamic> triggerData;
  final Map<String, double> deltas;
  final double impactScore;
  final String reason;
  final DateTime createdAt;

  const GrowthEvent({
    required this.id,
    required this.characterId,
    required this.userId,
    required this.triggerType,
    required this.evolutionMode,
    required this.triggerData,
    required this.deltas,
    required this.impactScore,
    required this.reason,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'userId': userId,
        'triggerType': triggerType,
        'evolutionMode': evolutionMode,
        'triggerData': triggerData,
        'deltas': deltas,
        'impactScore': impactScore,
        'reason': reason,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GrowthEvent.fromJson(Map<String, dynamic> json) {
    final deltasRaw = json['deltas'];
    final deltas = <String, double>{};
    if (deltasRaw is Map<String, dynamic>) {
      for (final entry in deltasRaw.entries) {
        final value = entry.value;
        if (value is num) {
          deltas[entry.key] = value.toDouble();
        }
      }
    }
    return GrowthEvent(
      id: json['id'] as String? ?? '',
      characterId: json['characterId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      triggerType: json['triggerType'] as String? ?? 'micro',
      evolutionMode: json['evolutionMode'] as String? ?? 'micro',
      triggerData: (json['triggerData'] as Map<String, dynamic>?) ?? {},
      deltas: deltas,
      impactScore: (json['impactScore'] as num?)?.toDouble() ?? 0.0,
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class _EvolutionResult {
  final String style;
  final String changes;
  final bool anchorPreserved;
  final EvolutionMode mode;
  final double impactScore;
  final Map<String, double> deltas;

  const _EvolutionResult({
    required this.style,
    required this.changes,
    required this.anchorPreserved,
    required this.mode,
    required this.impactScore,
    required this.deltas,
  });
}
