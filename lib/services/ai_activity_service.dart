import 'package:flutter/foundation.dart';
import '../models/ai_activity_event.dart';
import '../repositories/local_storage_repository.dart';
import 'emotion_engine.dart';
import 'inner_thought_service.dart';
import 'memory_engine.dart';
import 'persona_evolution_service.dart';
import 'weather_service.dart';

/// AI 活动服务 — 聚合各子系统的事件，生成统一的活动动态流
class AIActivityService {
  final LocalStorageRepository _storage;
  late final EmotionEngine _emotionEngine;
  late final InnerThoughtService _thoughtService;
  late final PersonaEvolutionService _evolutionService;

  AIActivityService(this._storage) {
    _emotionEngine = EmotionEngine(_storage);
    _thoughtService = InnerThoughtService(_storage, _emotionEngine);
    _evolutionService =
        PersonaEvolutionService(_storage, MemoryEngine(_storage));
  }

  /// 获取今日活动事件列表（按时间倒序）
  Future<List<AIActivityEvent>> getTodayActivities({
    required String userId,
    String? characterId,
    int limit = 30,
  }) async {
    final events = <AIActivityEvent>[];
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    try {
      final allCharacters = await _storage.getAllAICharacters();
      final characters = characterId == null
          ? allCharacters
          : allCharacters.where((c) => c.id == characterId).toList();
      if (characters.isEmpty) return events;

      for (final character in characters) {
        // 1. 内心独白
        final thoughts = await _thoughtService.getThoughts(
          characterId: character.id,
          userId: userId,
          limit: 10,
        );
        for (final thought in thoughts) {
          if (thought.createdAt.isAfter(startOfDay) &&
              thought.type.toString().contains('ai')) {
            events.add(AIActivityEvent(
              id: 'thought_${thought.id}',
              characterId: character.id,
              characterName: character.name,
              characterAvatar: character.avatarUrl,
              type: AIActivityType.innerThought,
              title: '$thought',
              subtitle: _truncate(thought.content, 50),
              detail: thought.content,
              createdAt: thought.createdAt,
            ));
          }
        }

        // 2. 情绪变化（从 memories 中读取情绪记忆）
        final emotionMemories = await _storage.getMemories(
          characterId: character.id,
          userId: userId,
          limit: 50,
        );
        for (final memory in emotionMemories) {
          if (memory.createdAt.isAfter(startOfDay) &&
              memory.type.toString().contains('emotion')) {
            events.add(AIActivityEvent(
              id: 'emotion_${memory.id}',
              characterId: character.id,
              characterName: character.name,
              characterAvatar: character.avatarUrl,
              type: AIActivityType.emotionChange,
              title: '情绪变化',
              subtitle: memory.content,
              detail: memory.content,
              createdAt: memory.createdAt,
            ));
          }
        }

        // 3. 人格进化
        final growthEvents =
            _evolutionService.getStoredGrowthEvents(character.id);
        for (final ge in growthEvents) {
          if (ge.createdAt.isAfter(startOfDay)) {
            events.add(AIActivityEvent(
              id: 'evolution_${ge.id}',
              characterId: character.id,
              characterName: character.name,
              characterAvatar: character.avatarUrl,
              type: AIActivityType.evolution,
              title: '人格成长',
              subtitle: ge.reason,
              detail: ge.reason,
              createdAt: ge.createdAt,
            ));
          }
        }

        // 4. 天气影响心情
        try {
          final weatherService = WeatherService(_storage, _emotionEngine);
          final weather = await weatherService.getCurrentWeather();
          if (weather.type != WeatherType.unknown &&
              weather.type != WeatherType.sunny) {
            events.add(AIActivityEvent(
              id: 'weather_${now.millisecondsSinceEpoch}',
              characterId: character.id,
              characterName: character.name,
              characterAvatar: character.avatarUrl,
              type: AIActivityType.weatherMood,
              title: '天气影响',
              subtitle: '今天${weather.label}，${character.name}的心情受到影响',
              createdAt: now,
            ));
          }
        } catch (_) {}

        // 5. 今日亲密度变化
        final todayDelta = await _storage.getTodayIntimacyDelta();
        if (todayDelta > 0) {
          events.add(AIActivityEvent(
            id: 'intimacy_${now.millisecondsSinceEpoch}',
            characterId: character.id,
            characterName: character.name,
            characterAvatar: character.avatarUrl,
            type: AIActivityType.milestone,
            title: '关系升温',
            subtitle: '今天亲密度 +$todayDelta',
            createdAt: now,
          ));
        }
      }

      // 按时间倒序排列
      events.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('AIActivityService: $e');
    }

    return events.take(limit).toList();
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }
}
