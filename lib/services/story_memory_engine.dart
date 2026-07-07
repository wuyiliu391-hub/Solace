import 'package:flutter/foundation.dart';
import '../models/ai_character.dart';
import '../models/chat_message.dart';
import '../models/story_book.dart';
import '../repositories/local_storage_repository.dart';
import 'memory_engine.dart';

/// 故事书独立记忆引擎
///
/// 复用单聊 [MemoryEngine] 的全部算法（LLM 抽取、艾宾浩斯热度评分、
/// 每日衰减、梦境整合、滚动摘要），但以 storyId 作为记忆维度，
/// 与单聊、与其他书本天然隔离——满足"独立记忆引擎"需求。
///
/// 实现方式：把 storyId 填入 MemoryEngine 的 characterId 通道，
/// userId 固定为书本所属用户；用一个合成的 AICharacter 承载书本身份。
class StoryMemoryEngine {
  final MemoryEngine _engine;

  StoryMemoryEngine(LocalStorageRepository storage)
      : _engine = MemoryEngine(storage);

  /// 把故事书包装成 MemoryEngine 所需的 AICharacter 载体
  AICharacter _asCharacter(StoryBook book) {
    return AICharacter(
      id: book.id, // ← 关键：storyId 作为记忆维度
      name: book.title.isEmpty ? '故事' : book.title,
      personality: book.worldSetting,
      coreDesire: '',
      moralBoundary: '',
      worldSetting: book.worldSetting,
      createdAt: book.createdAt,
    );
  }

  /// 构建剧情记忆 prompt（永久档案 + 近期状态 + 相关记忆）
  Future<String> buildMemoryPrompt({
    required StoryBook book,
    required String currentText,
    String memoryMode = 'full',
  }) async {
    try {
      return await _engine.buildConsolidatedMemoryPrompt(
        character: _asCharacter(book),
        userId: book.userId,
        currentMessage: currentText,
        memoryMode: memoryMode,
      );
    } catch (e) {
      debugPrint('StoryMemoryEngine: buildMemoryPrompt failed: $e');
      return '';
    }
  }

  /// 从最近剧情段落中提取关键记忆（LLM 抽取，回退正则）
  Future<void> extractMemory({
    required StoryBook book,
    required List<ChatMessage> recentSegments,
  }) async {
    try {
      final character = _asCharacter(book);
      await _engine.extractMemory(
        character: character,
        userId: book.userId,
        recentMessages: recentSegments,
        characterName: character.name,
      );
    } catch (e) {
      debugPrint('StoryMemoryEngine: extractMemory failed: $e');
    }
  }

  /// 检查是否需要生成新的滚动摘要
  Future<List<ChatMessage>?> checkRollingSummaryNeeded({
    required StoryBook book,
    required List<ChatMessage> allSegments,
  }) {
    return _engine.checkRollingSummaryNeeded(
      characterId: book.id,
      userId: book.userId,
      allMessages: allSegments,
    );
  }

  /// 保存滚动摘要（永久记忆档案）
  Future<void> saveRollingSummary({
    required StoryBook book,
    required String summary,
    required int messageCount,
  }) {
    return _engine.saveRollingSummary(
      characterId: book.id,
      userId: book.userId,
      summary: summary,
      messageCount: messageCount,
    );
  }

  /// 保存对话摘要（防止长剧情失忆）
  Future<void> saveConversationSummary({
    required StoryBook book,
    required List<ChatMessage> segments,
  }) {
    return _engine.saveConversationSummary(
      character: _asCharacter(book),
      userId: book.userId,
      messages: segments,
    );
  }

  /// 每日维护（衰减 + 梦境整合），在打开书本时调用
  Future<void> runDailyMaintenance(StoryBook book) {
    return _engine.runDailyMaintenance(
      characterId: book.id,
      userId: book.userId,
    );
  }

  /// 生成滚动摘要文本（委托底层 LLM 摘要）
  MemoryEngine get raw => _engine;
}
