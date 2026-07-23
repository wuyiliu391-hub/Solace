import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/ai_character.dart';
import '../../models/story_book.dart';
import '../../models/story_segment.dart';
import '../../models/story_scene.dart';
import '../../models/story_save.dart';
import '../../models/chat_message.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/story_memory_engine.dart';
import '../../services/story_protocol.dart';

part 'story_play_event.dart';
part 'story_play_state.dart';

/// 单本故事书的剧情播放 Bloc
class StoryPlayBloc extends Bloc<StoryPlayEvent, StoryPlayState> {
  final LocalStorageRepository _storage;
  final AIService _aiService;
  final StoryMemoryEngine _memory;
  final _uuid = const Uuid();

  StoryPlayBloc(this._storage, this._aiService)
      : _memory = StoryMemoryEngine(_storage),
        super(StoryPlayState.initial()) {
    on<StoryPlayOpen>(_onOpen);
    on<StoryPlayAdvance>(_onAdvance);
    on<StoryPlaySwitchNarrator>(_onSwitchNarrator);
    on<StoryPlayStreamTick>(_onStreamTick);
    on<StoryPlayCreateSave>(_onCreateSave);
    on<StoryPlayLoadSave>(_onLoadSave);
  }

  Future<void> _onOpen(
    StoryPlayOpen event,
    Emitter<StoryPlayState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final book = await _storage.getStoryBook(event.bookId);
      if (book == null) {
        emit(state.copyWith(isLoading: false, error: '故事不存在'));
        return;
      }

      // 确保有一个激活存档
      var saveId = book.currentSaveId;
      StoryBook activeBook = book;
      if (saveId == null || saveId.isEmpty) {
        final save = await _createDefaultSave(book);
        saveId = save.id;
        activeBook = book.copyWith(currentSaveId: saveId);
        await _storage.saveStoryBook(activeBook);
      }

      final segments = await _storage.getStorySegments(book.id, saveId);
      final scene = await _storage.getStoryScene(book.id, saveId) ??
          StoryScene.initial(book.id, saveId);

      // 最新一条 narration 的分支
      final lastNarration = segments.reversed
          .where((s) => s.isNarration && s.branchOptions.isNotEmpty)
          .firstOrNull;

      emit(state.copyWith(
        book: activeBook,
        segments: segments,
        scene: scene,
        currentBranches: lastNarration?.branchOptions ?? const [],
        isLoading: false,
      ));

      // 后台跑记忆维护
      unawaited(_memory.runDailyMaintenance(activeBook));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: '打开失败: $e'));
    }
  }

  Future<StorySave> _createDefaultSave(StoryBook book) async {
    final now = DateTime.now();
    final save = StorySave(
      id: _uuid.v4(),
      storyId: book.id,
      name: '存档 1',
      segmentCount: 0,
      narratorRole: book.narratorRole.index,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveStorySave(save);
    return save;
  }

  Future<void> _onSwitchNarrator(
    StoryPlaySwitchNarrator event,
    Emitter<StoryPlayState> emit,
  ) async {
    final book = state.book;
    if (book == null) return;
    final updated = book.copyWith(narratorRole: event.role, updatedAt: DateTime.now());
    await _storage.saveStoryBook(updated);
    emit(state.copyWith(book: updated));
  }

  void _onStreamTick(
    StoryPlayStreamTick event,
    Emitter<StoryPlayState> emit,
  ) {
    emit(state.copyWith(streamingText: event.text));
  }

  Future<void> _onAdvance(
    StoryPlayAdvance event,
    Emitter<StoryPlayState> emit,
  ) async {
    final book = state.book;
    if (book == null || state.isGenerating) return;
    final saveId = book.currentSaveId ?? '';
    final input = event.input.trim();
    if (input.isEmpty) return;

    // 1) 保存玩家输入段落
    final baseCount = state.segments.length;
    final userSeg = StorySegment(
      id: _uuid.v4(),
      storyId: book.id,
      saveId: saveId,
      role: SegmentRole.user,
      content: input,
      narratorRole: book.narratorRole.index,
      orderIndex: baseCount,
      createdAt: DateTime.now(),
    );
    await _storage.saveStorySegment(userSeg);

    emit(state.copyWith(
      segments: [...state.segments, userSeg],
      currentBranches: const [],
      isGenerating: true,
      streamingText: '',
      clearError: true,
    ));

    // 2) 构建 messages 并流式生成
    try {
      final messages = await _buildMessages(book, input);
      final buffer = StringBuffer();
      await for (final chunk in _aiService.sendStoryMessageStream(
        messages: messages,
      )) {
        if (chunk.content.isNotEmpty) {
          buffer.write(chunk.content);
          add(StoryPlayStreamTick(
              StoryProtocol.stripStateForDisplay(buffer.toString())));
        }
      }

      // 3) 解析结果
      final result = StoryProtocol.parse(buffer.toString());
      final narrative =
          result.narrative.isEmpty ? '（……）' : result.narrative;

      final narrationSeg = StorySegment(
        id: _uuid.v4(),
        storyId: book.id,
        saveId: saveId,
        role: SegmentRole.narration,
        content: narrative,
        narratorRole: book.narratorRole.index,
        branchOptions: result.branchOptions,
        orderIndex: baseCount + 1,
        createdAt: DateTime.now(),
      );
      await _storage.saveStorySegment(narrationSeg);

      // 4) 更新场景快照
      var newScene = state.scene;
      if (result.sceneDelta != null) {
        newScene = result.sceneDelta!.applyTo(state.scene.copyWith(
          storyId: book.id,
          saveId: saveId,
        ));
        await _storage.saveStoryScene(newScene);
      }

      // 5) 更新书本预览
      final updatedBook = book.copyWith(
        updatedAt: DateTime.now(),
        lastSegmentPreview:
            narrative.length > 40 ? '${narrative.substring(0, 40)}…' : narrative,
      );
      await _storage.saveStoryBook(updatedBook);

      emit(state.copyWith(
        book: updatedBook,
        segments: [...state.segments, narrationSeg],
        scene: newScene,
        currentBranches: result.branchOptions,
        isGenerating: false,
        streamingText: '',
      ));

      // 6) 记忆写回（后台）
      unawaited(_writeBackMemory(updatedBook, saveId));
    } catch (e) {
      debugPrint('StoryPlay advance failed: $e');
      emit(state.copyWith(
        isGenerating: false,
        streamingText: '',
        error: '续写失败: $e',
      ));
    }
  }

  /// 构建发给 LLM 的 messages（system 世界观+记忆+协议 + 历史段落 + 本轮输入）
  Future<List<Map<String, String>>> _buildMessages(
      StoryBook book, String input) async {
    final sys = StringBuffer();
    sys.writeln('你是一位沉浸式互动小说的叙事引擎。');
    sys.writeln('【故事标题】${book.title}');
    if (book.worldSetting.trim().isNotEmpty) {
      sys.writeln('【世界观设定】\n${book.worldSetting.trim()}');
    }
    if (book.synopsis.trim().isNotEmpty) {
      sys.writeln('【故事简介】${book.synopsis.trim()}');
    }
    sys.writeln('【创作风格】${book.genre.label}');
    sys.writeln('【当前叙事视角】以「${book.narratorRole.label}」的第一人称视角推进剧情。');

    // 导入角色信息
    if (book.participantCharacterIds.isNotEmpty) {
      final names = <String>[];
      for (final cid in book.participantCharacterIds) {
        final c = await _storage.getAICharacter(cid);
        if (c != null) {
          names.add('${c.name}（${c.personality}）');
        }
      }
      if (names.isNotEmpty) {
        sys.writeln('【登场人物】${names.join('；')}');
      }
    }

    // 记忆注入
    final mem = await _memory.buildMemoryPrompt(book: book, currentText: input);
    if (mem.trim().isNotEmpty) {
      sys.writeln(mem.trim());
    }

    // 情绪引擎注入：根据故事当前情绪状态调整语气
    if (state.scene.storyId.isNotEmpty) {
      final scene = state.scene;
      if (scene.emotionLabel.isNotEmpty) {
        sys.writeln('【当前情绪氛围】${scene.emotionLabel}');
        final emotionGuide = _buildStoryEmotionGuide(scene);
        if (emotionGuide.isNotEmpty) sys.writeln(emotionGuide);
      }
      if (scene.atmosphere.isNotEmpty) {
        sys.writeln('【场景氛围】${scene.atmosphere}');
      }
    }

    // 节奏控制：根据已读段落数调整回复节奏
    final segCount = state.segments.length;
    if (segCount < 3) {
      sys.writeln('【节奏指引】故事刚开始，保持节奏明快，每段控制在80字以内，快速建立场景和悬念。');
    } else if (segCount < 15) {
      sys.writeln('【节奏指引】故事进入发展期，可以适当展开描写，每段100-150字，注意情节推进和人物互动。');
    } else {
      sys.writeln('【节奏指引】故事已深入，可以穿插内心独白和环境描写，每段100-200字，保持张弛有度。');
    }

    sys.writeln(StoryProtocol.outputInstruction);

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys.toString()},
    ];

    // 历史段落（最近 30 条）
    final history = state.segments.length > 30
        ? state.segments.sublist(state.segments.length - 30)
        : state.segments;
    for (final seg in history) {
      if (seg.content.trim().isEmpty) continue;
      messages.add({
        'role': seg.isUser ? 'user' : 'assistant',
        'content': seg.content,
      });
    }
    messages.add({'role': 'user', 'content': input});
    return messages;
  }

  /// 根据故事场景情绪状态构建语气指引
  String _buildStoryEmotionGuide(StoryScene scene) {
    final emotion = scene.emotionLabel.toLowerCase();
    if (emotion.contains('开心') || emotion.contains('兴奋')) {
      return '叙事基调积极明亮，描写可以多用暖色调意象，节奏轻快。';
    } else if (emotion.contains('难过') || emotion.contains('悲伤')) {
      return '叙事基调偏沉，适当放慢节奏，多用细腻的内心描写和环境渲染。';
    } else if (emotion.contains('紧张') || emotion.contains('焦虑')) {
      return '叙事节奏加快，多用短句和动作描写，营造紧迫感。';
    } else if (emotion.contains('温柔') || emotion.contains('感动')) {
      return '叙事风格柔和，注重情感细节和人物互动，节奏舒缓。';
    } else if (emotion.contains('愤怒') || emotion.contains('生气')) {
      return '叙事张力增强，人物内心冲突外化，语气更直接有力。';
    } else if (emotion.contains('害怕') || emotion.contains('恐惧')) {
      return '叙事氛围偏暗，多用环境暗示和心理描写营造悬疑感。';
    }
    return '';
  }

  /// 记忆写回：提取记忆 + 滚动摘要
  Future<void> _writeBackMemory(StoryBook book, String saveId) async {
    try {
      final segs = await _storage.getStorySegments(book.id, saveId);
      final asMessages = segs
          .map((s) => ChatMessage(
                id: s.id,
                chatId: book.id,
                senderId: s.isUser ? 'user' : 'ai_${book.id}',
                content: s.content,
                isUser: s.isUser,
                createdAt: s.createdAt,
              ))
          .toList();

      final recent =
          asMessages.length > 8 ? asMessages.sublist(asMessages.length - 8) : asMessages;
      await _memory.extractMemory(book: book, recentSegments: recent);

      final need = await _memory.checkRollingSummaryNeeded(
          book: book, allSegments: asMessages);
      if (need != null && need.isNotEmpty) {
        final existing = await _memory.raw
            .getRollingSummary(characterId: book.id, userId: book.userId);
        final summary = await _aiService.generateRollingSummary(
          newMessages: need,
          character: _storyCharacter(book),
          existingSummary: existing,
        );
        if (summary.trim().isNotEmpty) {
          await _memory.saveRollingSummary(
            book: book,
            summary: summary,
            messageCount: asMessages.length,
          );
        }
      }
    } catch (e) {
      debugPrint('StoryPlay memory writeback failed: $e');
    }
  }

  Future<void> _onCreateSave(
    StoryPlayCreateSave event,
    Emitter<StoryPlayState> emit,
  ) async {
    final book = state.book;
    if (book == null) return;
    final fromSaveId = book.currentSaveId ?? '';
    final now = DateTime.now();
    final newId = _uuid.v4();
    final save = StorySave(
      id: newId,
      storyId: book.id,
      name: event.name.isEmpty ? '存档 ${now.millisecondsSinceEpoch}' : event.name,
      segmentCount: state.segments.length,
      narratorRole: book.narratorRole.index,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.saveStorySave(save);
    // 复制当前存档内容到新存档，并切换过去
    await _storage.copyStorySaveContents(book.id, fromSaveId, newId);
    final updated = book.copyWith(currentSaveId: newId, updatedAt: now);
    await _storage.saveStoryBook(updated);
    add(StoryPlayOpen(book.id));
  }

  Future<void> _onLoadSave(
    StoryPlayLoadSave event,
    Emitter<StoryPlayState> emit,
  ) async {
    final book = state.book;
    if (book == null) return;
    final updated =
        book.copyWith(currentSaveId: event.saveId, updatedAt: DateTime.now());
    await _storage.saveStoryBook(updated);
    add(StoryPlayOpen(book.id));
  }

  /// 合成书本角色（供 generateRollingSummary 使用）
  AICharacter _storyCharacter(StoryBook book) => AICharacter(
        id: book.id,
        name: book.title.isEmpty ? '故事' : book.title,
        personality: book.worldSetting,
        coreDesire: '',
        moralBoundary: '',
        createdAt: book.createdAt,
      );
}
