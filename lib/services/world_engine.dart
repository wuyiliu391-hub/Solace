// ============================================================
// 全生命周期数字生命世界 — WorldEngine 中枢
// 统一调度所有生命引擎的核心大脑
// ============================================================
//
// 职责：
// - 管理 GlobalTimeClock 世界时间
// - 为每个 AICharacter 维护对应的 LifeProfile
// - 每次心跳执行完整生命周期管道：
//   1. 推进世界时间
//   2. 生命周期引擎 → 年龄/阶段更新
//   3. 马斯洛需求 → 需求状态更新
//   4. 人格演化 → 每日漂移
//   5. 生命终结检查 → 衰老/永生
// - 将事件发布给 UI 层

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/ai_character.dart';
import '../models/gene_profile.dart';
import '../models/life_profile.dart';
import '../repositories/local_storage_repository.dart';
import 'global_time_clock.dart';
import 'lifecycle_engine.dart';
import 'life_end_engine.dart';
import 'maslow_motivation_kernel.dart';
import 'reflection_engine.dart';
import 'personality_evolution_engine.dart';
import 'birth_initialization_engine.dart';
import 'emergence_detector.dart';
import 'chain_reaction_engine.dart';
import 'conflict_engine.dart';
import 'polarization_engine.dart';
import 'ai_relationship_service.dart';
import 'memory_engine.dart';
import 'llm_service.dart';

/// 世界引擎事件 — UI 层可监听的各类事件
class WorldEngineEvent {
  final String type;
  final String? characterId;
  final String? characterName;
  final String description;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const WorldEngineEvent({
    required this.type,
    this.characterId,
    this.characterName,
    required this.description,
    required this.timestamp,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'characterId': characterId,
        'characterName': characterName,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };
}

/// 世界状态快照 — UI 读取当前世界全景
class WorldStateSnapshot {
  final DateTime worldTime;
  final int activeLifeCount;
  final int agingCount;
  final int immortalCount;
  final int deceasedCount;
  final List<WorldEngineEvent> recentEvents;
  final Map<String, LifeProfile> profiles;

  const WorldStateSnapshot({
    required this.worldTime,
    required this.activeLifeCount,
    required this.agingCount,
    required this.immortalCount,
    required this.deceasedCount,
    required this.recentEvents,
    required this.profiles,
  });
}

/// LifeProfile 持久化 key
String _lifeProfileKey(String characterId) =>
    'world_life_profile_$characterId';

/// WorldEngine — 全生命周期数字生命世界的中枢调度大脑
///
/// 使用方式：
/// ```dart
/// final engine = WorldEngine(storageRepo, llmService, db);
/// await engine.initialize(characters);
/// // 在 HeartbeatService 心跳中调用
/// await engine.tick();
/// // UI 层监听事件
/// engine.eventStream.listen((event) => ...);
/// ```
class WorldEngine {
  final LocalStorageRepository _storage;
  final LlmService _llmService;
  // 生命周期各引擎
  late final GlobalTimeClock _clock;
  late final LifecycleEngine _lifecycleEngine;
  late final MaslowMotivationKernel _maslowKernel;
  late final ReflectionEngine _reflectionEngine;
  late final PersonalityEvolutionEngine _personalityEngine;
  late final BirthInitializationEngine _birthEngine;
  late final EmergenceDetector _emergenceDetector;

  // 角色 → LifeProfile 映射
  final Map<String, LifeProfile> _profiles = {};

  // 事件流
  final StreamController<WorldEngineEvent> _eventController =
      StreamController<WorldEngineEvent>.broadcast();

  // 最近事件缓存
  final List<WorldEngineEvent> _recentEvents = [];
  static const int _maxRecentEvents = 50;

  // 上次马斯洛 tick 的世界时间（防止同一天重复 tick）
  DateTime? _lastMaslowTick;
  // 上次人格漂移的世界时间
  DateTime? _lastPersonalityDrift;

  bool _initialized = false;

  /// 事件流 — UI 可监听
  Stream<WorldEngineEvent> get eventStream => _eventController.stream;

  /// 最近事件列表
  List<WorldEngineEvent> get recentEvents =>
      List.unmodifiable(_recentEvents);

  /// 所有活跃的 LifeProfile
  Map<String, LifeProfile> get profiles =>
      Map.unmodifiable(_profiles);

  /// 获取当前世界状态快照
  WorldStateSnapshot get snapshot {
    final profiles = _profiles.values.toList();
    return WorldStateSnapshot(
      worldTime: _clock.worldTime,
      activeLifeCount: profiles
          .where((p) =>
              p.lifeState == LifeState.alive || p.lifeState == LifeState.aging)
          .length,
      agingCount:
          profiles.where((p) => p.lifeState == LifeState.aging).length,
      immortalCount:
          profiles.where((p) => p.lifeState == LifeState.immortal).length,
      deceasedCount:
          profiles.where((p) => p.lifeState == LifeState.deceased).length,
      recentEvents: _recentEvents,
      profiles: Map.from(_profiles),
    );
  }

  /// GlobalTimeClock 访问
  GlobalTimeClock get clock => _clock;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 延迟初始化的 LifeEndEngine（可为空，DB 不可用时跳过生命周期终结检查）
  LifeEndEngine? _lazyLifeEndEngine;

  /// 安全访问 LifeEndEngine，可能为 null
  LifeEndEngine? get _lifeEndEngine => _lazyLifeEndEngine;

  WorldEngine(this._storage, this._llmService) {
    _clock = GlobalTimeClock.instance;
    _lifecycleEngine = LifecycleEngine(_clock);
    _maslowKernel = MaslowMotivationKernel();
    _reflectionEngine = ReflectionEngine(_llmService, _storage);
    _personalityEngine = PersonalityEvolutionEngine();
    _birthEngine = BirthInitializationEngine();
    _emergenceDetector = EmergenceDetector();

    // 尝试初始化 LifeEndEngine（需要 DB 可用）
    _tryInitLifeEndEngine();
  }

  void _tryInitLifeEndEngine() {
    try {
      final db = _storage.database;
      if (db != null) {
        _lazyLifeEndEngine = LifeEndEngine(
          clock: _clock,
          reflection: _reflectionEngine,
          llm: _llmService,
          db: db,
        );
        debugPrint('[WorldEngine] LifeEndEngine 初始化成功');
      } else {
        debugPrint('[WorldEngine] DB 不可用，LifeEndEngine 跳过');
      }
    } catch (e) {
      debugPrint('[WorldEngine] LifeEndEngine 初始化失败: $e');
    }
  }

  /// 初始化世界引擎
  ///
  /// 1. 初始化 GlobalTimeClock
  /// 2. 加载已保存的 LifeProfile
  /// 3. 为没有 LifeProfile 的角色创建默认档案
  /// 4. 初始化 LifeEndEngine 的数据库引用
  Future<void> initialize(List<AICharacter> characters) async {
    try {
      // 1. 初始化世界时间
      await _clock.init();

      // 2. 加载 Maslow 配置
      await _maslowKernel.loadConfig();

      // 3. 加载或创建 LifeProfile
      final prefs = await SharedPreferences.getInstance();
      for (final char in characters) {
        final key = _lifeProfileKey(char.id);
        final json = prefs.getString(key);
        if (json != null) {
          try {
            _profiles[char.id] =
                LifeProfile.fromJson(jsonDecode(json) as Map<String, dynamic>);
          } catch (e) {
            debugPrint('[WorldEngine] 解析 LifeProfile 失败 ${char.id}: $e');
            _profiles[char.id] = _createDefaultProfile(char);
          }
        } else {
          _profiles[char.id] = _createDefaultProfile(char);
          await _saveProfile(char.id);
        }
      }

      // 4. LifeEndEngine 已在构造函数中初始化

      _initialized = true;
      final event = WorldEngineEvent(
        type: 'world_initialized',
        description: '世界引擎初始化完成，${_profiles.length} 个数字生命',
        timestamp: _clock.worldTime,
        metadata: {'profileCount': _profiles.length},
      );
      _addEvent(event);

      debugPrint(
          '[WorldEngine] 初始化完成: ${_profiles.length} profiles');
    } catch (e) {
      debugPrint('[WorldEngine] 初始化失败: $e');
      _initialized = false;
    }
  }

  /// 核心心跳 — 由 HeartbeatService 每次心跳调用
  Future<void> tick() async {
    if (!_initialized) return;

    try {
      // 1. 推进世界时间（5 世界分钟）
      _clock.tick(const Duration(minutes: 5));

      // 2. 检查生命周期
      await _tickLifecycle();

      // 3. 检查马斯洛需求（每小时一次）
      await _tickMaslow();

      // 4. 检查人格漂移（每天一次）
      await _tickPersonality();

      // 5. 保存更新后的 Profile
      await _syncAllProfiles();
    } catch (e) {
      debugPrint('[WorldEngine] tick error: $e');
    }
  }

  /// 添加新角色时创建 LifeProfile
  Future<LifeProfile> addCharacter(AICharacter character) async {
    final profile = await _birthEngine.createLife(
      nameOverride: character.name,
    );
    _profiles[character.id] = profile;
    await _saveProfile(character.id);

    _addEvent(WorldEngineEvent(
      type: 'life_birth',
      characterId: character.id,
      characterName: character.name,
      description: '${character.name} 降临世界',
      timestamp: _clock.worldTime,
    ));

    return profile;
  }

  /// 获取指定角色的 LifeProfile
  LifeProfile? getProfile(String characterId) => _profiles[characterId];

  /// 获取指定角色的 LifeProfile（自动创建默认）
  LifeProfile getOrCreateProfile(String characterId) {
    if (_profiles.containsKey(characterId)) return _profiles[characterId]!;
    final profile = LifeProfile(
      id: characterId,
      name: '',
      birthTime: _clock.worldTime,
      genes: GeneProfile.random(),
    );
    _profiles[characterId] = profile;
    return profile;
  }

  /// 更新指定角色的 LifeProfile
  Future<void> updateProfile(
      String characterId, LifeProfile profile) async {
    _profiles[characterId] = profile;
    await _saveProfile(characterId);
  }

  /// 清理资源
  void dispose() {
    _eventController.close();
  }

  // ─────────────────────────────────────
  // 内部方法
  // ─────────────────────────────────────

  /// 生命周期 tick
  Future<void> _tickLifecycle() async {
    final profiles = _profiles.values
        .where((p) =>
            p.lifeState == LifeState.alive ||
            p.lifeState == LifeState.aging)
        .toList();
    if (profiles.isEmpty) return;

    // 生命周期引擎
    final updated = await _lifecycleEngine.tickAll(profiles);
    for (final profile in updated) {
      final charId = _findCharIdByProfile(profile);
      if (charId != null) {
        _profiles[charId] = profile;
      }
    }

    // 生命终结检查（50 岁以后，需要 LifeEndEngine 可用）
    final lifeEndEngine = _lazyLifeEndEngine;
    if (lifeEndEngine != null) {
      for (final profile in profiles) {
        if (profile.biologicalAge >= 50) {
          final result = await lifeEndEngine.check(profile);
          if (result != null) {
            final charId = _findCharIdByProfile(result);
            if (charId != null) {
              _profiles[charId] = result;
              if (result.lifeState == LifeState.deceased) {
                _addEvent(WorldEngineEvent(
                  type: 'life_death',
                  characterId: charId,
                  characterName: result.name,
                  description: '${result.name} 走完了 ${result.biologicalAge} 年的人生',
                  timestamp: _clock.worldTime,
                  metadata: {'age': result.biologicalAge},
                ));
              }
              if (result.lifeState == LifeState.immortal) {
                _addEvent(WorldEngineEvent(
                  type: 'life_immortal',
                  characterId: charId,
                  characterName: result.name,
                  description: '${result.name} 选择了数字永生',
                  timestamp: _clock.worldTime,
                ));
              }
            }
          }
        }
      }
    }
  }

  /// 马斯洛需求 tick（每小时）
  Future<void> _tickMaslow() async {
    final worldNow = _clock.worldTime;
    if (_lastMaslowTick != null &&
        worldNow.difference(_lastMaslowTick!).inHours < 1) {
      return;
    }
    _lastMaslowTick = worldNow;

    for (final entry in _profiles.entries) {
      if (entry.value.lifeState == LifeState.deceased) continue;
      final maslowData = entry.value.maslowState;
      if (maslowData.isEmpty) continue;

      final maslowState = MaslowState.fromJson(maslowData);
      // 简化版 SocialContext（实际应来自关系图谱）
      const context = SocialContext();
      _maslowKernel.tick(maslowState, entry.value, context);
      final updated = entry.value.copyWith(
        maslowState: maslowState.toJson(),
      );
      _profiles[entry.key] = updated;
    }
  }

  /// 人格漂移（每天）
  Future<void> _tickPersonality() async {
    final worldNow = _clock.worldTime;
    if (_lastPersonalityDrift != null &&
        worldNow.difference(_lastPersonalityDrift!).inDays < 1) {
      return;
    }
    _lastPersonalityDrift = worldNow;

    for (final entry in _profiles.entries) {
      if (entry.value.lifeState == LifeState.deceased) continue;
      try {
        final newState =
            await _personalityEngine.dailyDrift(entry.value);
        final updated = entry.value.copyWith(
          personalityState: newState.toMap(),
        );
        _profiles[entry.key] = updated;
      } catch (e) {
        debugPrint('[WorldEngine] 人格漂移失败 ${entry.key}: $e');
      }
    }
  }

  /// 为 AICharacter 创建默认 LifeProfile
  LifeProfile _createDefaultProfile(AICharacter character) {
    final now = _clock.worldTime;
    // 从创建时间推算生物年龄
    final daysSinceCreation = now.difference(character.createdAt).inDays;
    final biologicalAge = (daysSinceCreation / 365).floor().clamp(0, 100);
    final stage = LifeProfile.stageForAge(biologicalAge);

    final genes = GeneProfile.random();
    final personalityState = {
      'openness': genes.openness,
      'conscientiousness': genes.conscientiousness,
      'extraversion': genes.extraversion,
      'agreeableness': genes.agreeableness,
      'neuroticism': genes.neuroticism,
    };

    final maslowState = MaslowState().toJson();

    return LifeProfile(
      id: character.id,
      name: character.name,
      birthTime: character.createdAt,
      currentStage: stage,
      lifeState: LifeState.alive,
      biologicalAge: biologicalAge,
      mentalAge: biologicalAge,
      genes: genes,
      personalityState: personalityState,
      maslowState: maslowState,
      lifeEvents: [
        {
          'type': 'birth',
          'description': '${character.name} 降临世界',
          'timestamp': character.createdAt.toIso8601String(),
        },
      ],
      identity: {
        'coreMotivation': character.coreDesire ?? '找到属于自己的路',
        'biggestFear': '未知',
        'lifePhilosophy': '',
        'selfDescription': '',
        'identityTags': [],
        'innerConflicts': [],
      },
    );
  }

  /// 保存 LifeProfile 到 SharedPreferences
  Future<void> _saveProfile(String characterId) async {
    final profile = _profiles[characterId];
    if (profile == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lifeProfileKey(characterId),
      jsonEncode(profile.toJson()),
    );
  }

  /// 同步所有 profile 到持久化
  Future<void> _syncAllProfiles() async {
    for (final id in _profiles.keys) {
      await _saveProfile(id);
    }
  }

  /// 通过 profile 查找对应的 characterId
  String? _findCharIdByProfile(LifeProfile profile) {
    for (final entry in _profiles.entries) {
      if (entry.value.id == profile.id) return entry.key;
    }
    return null;
  }

  /// 添加事件到缓存和流
  void _addEvent(WorldEngineEvent event) {
    _recentEvents.add(event);
    if (_recentEvents.length > _maxRecentEvents) {
      _recentEvents.removeAt(0);
    }
    _eventController.add(event);
  }

  // ─────────────────────────────────────
  // 规则干预 API（供 RuleInterventionPanel 调用）
  // ─────────────────────────────────────

  /// 注入世界事件
  void injectWorldEvent({required String type, required String description}) {
    _addEvent(WorldEngineEvent(
      type: 'world_event_$type',
      description: description,
      timestamp: _clock.worldTime,
      metadata: {'injected': true, 'eventType': type},
    ));
    debugPrint('[WorldEngine] 注入世界事件: [$type] $description');
  }

  /// 注入角色事件
  void injectCharacterEvent({
    required String characterId,
    required String type,
    required String description,
    double emotionalWeight = 0.5,
  }) {
    final profile = _profiles[characterId];
    if (profile == null) {
      debugPrint('[WorldEngine] 角色不存在: $characterId');
      return;
    }

    // 添加到角色的人生事件列表
    final events = List<Map<String, dynamic>>.from(profile.lifeEvents);
    events.add({
      'type': type,
      'description': description,
      'timestamp': _clock.worldTime.toIso8601String(),
      'emotionalWeight': emotionalWeight,
      'injected': true,
    });

    // 更新情绪状态（根据情感权重）
    final emotions = Map<String, dynamic>.from(profile.emotionalState);
    if (emotionalWeight > 0.5) {
      emotions['valence'] = (emotions['valence'] as num? ?? 0.0) + emotionalWeight;
    } else {
      emotions['valence'] = (emotions['valence'] as num? ?? 0.0) - (1 - emotionalWeight);
    }

    final updated = profile.copyWith(
      lifeEvents: events,
      emotionalState: emotions,
    );
    _profiles[characterId] = updated;
    _saveProfile(characterId);

    _addEvent(WorldEngineEvent(
      type: 'character_intervention_$type',
      characterId: characterId,
      characterName: profile.name,
      description: description,
      timestamp: _clock.worldTime,
      metadata: {'injected': true, 'type': type, 'weight': emotionalWeight},
    ));
    debugPrint('[WorldEngine] 注入角色事件: [$type] $description -> $characterId');
  }

  /// 更新世界参数
  void updateWorldParameters({
    double? personalityDriftRate,
    double? forgettingRate,
    double? conflictProbability,
    double? selfProtectionThreshold,
  }) {
    // 更新人格演化引擎参数
    if (personalityDriftRate != null) {
      _personalityEngine.updateDriftRate(personalityDriftRate);
    }

    _addEvent(WorldEngineEvent(
      type: 'parameters_updated',
      description: '世界参数已更新',
      timestamp: _clock.worldTime,
      metadata: {
        'personalityDriftRate': personalityDriftRate,
        'forgettingRate': forgettingRate,
        'conflictProbability': conflictProbability,
        'selfProtectionThreshold': selfProtectionThreshold,
      },
    ));
    debugPrint('[WorldEngine] 世界参数已更新');
  }
}
