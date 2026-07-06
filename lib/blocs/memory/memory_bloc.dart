// 【对标来源：Muice-Chatbot-1.4 — llm/faiss_memory.py 记忆管理】
// BLoC 状态管理，记忆仓库层对标 Muice FAISS 记忆检索

import "dart:async";
import "package:flutter_bloc/flutter_bloc.dart";
import "../../models/emotion_memory_entry.dart";
import "../../repositories/memory_repository.dart";
import "../../services/emotion_memory_pool.dart";

abstract class MemoryEvent {}

class LoadMemories extends MemoryEvent {
  final String characterId;
  final String userId;
  LoadMemories(this.characterId, this.userId);
}

class SearchMemories extends MemoryEvent {
  final String query;
  final String characterId;
  final String userId;
  final String? emotionTag;
  SearchMemories({
    required this.query,
    required this.characterId,
    required this.userId,
    this.emotionTag,
  });
}

class InsertMemory extends MemoryEvent {
  final String input;
  final String output;
  final String characterId;
  final String userId;
  final String? emotionTag;
  InsertMemory({
    required this.input,
    required this.output,
    required this.characterId,
    required this.userId,
    this.emotionTag,
  });
}

class DeleteMemory extends MemoryEvent {
  final String memoryId;
  DeleteMemory(this.memoryId);
}

class ClearMemories extends MemoryEvent {
  final String characterId;
  final String userId;
  ClearMemories(this.characterId, this.userId);
}

abstract class MemoryState {}

class MemoryInitial extends MemoryState {}

class MemoryLoading extends MemoryState {}

class MemoriesLoaded extends MemoryState {
  final List<EmotionMemoryEntry> memories;
  final int totalCount;
  MemoriesLoaded(this.memories, this.totalCount);
}

class MemoriesSearched extends MemoryState {
  final List<EmotionMemoryEntry> results;
  MemoriesSearched(this.results);
}

class MemoryError extends MemoryState {
  final String message;
  MemoryError(this.message);
}

class MemoryBloc extends Bloc<MemoryEvent, MemoryState> {
  final MemoryRepository _memoryRepo;
  final EmotionMemoryPool _emotionPool;

  MemoryBloc({
    MemoryRepository? memoryRepo,
    EmotionMemoryPool? emotionPool,
  })  : _memoryRepo = memoryRepo ?? MemoryRepository.instance,
        _emotionPool = emotionPool ?? EmotionMemoryPool(),
        super(MemoryInitial()) {
    on<LoadMemories>(_onLoadMemories);
    on<SearchMemories>(_onSearchMemories);
    on<InsertMemory>(_onInsertMemory);
    on<DeleteMemory>(_onDeleteMemory);
    on<ClearMemories>(_onClearMemories);
  }

  Future<void> _onLoadMemories(
    LoadMemories event,
    Emitter<MemoryState> emit,
  ) async {
    emit(MemoryLoading());
    try {
      final memories =
          await _memoryRepo.getAllMemories(event.characterId, event.userId);
      final count =
          await _memoryRepo.getMemoryCount(event.characterId, event.userId);
      emit(MemoriesLoaded(memories, count));
    } catch (e) {
      emit(MemoryError("加载记忆失败: $e"));
    }
  }

  Future<void> _onSearchMemories(
    SearchMemories event,
    Emitter<MemoryState> emit,
  ) async {
    emit(MemoryLoading());
    try {
      final results = await _emotionPool.searchMemory(
        query: event.query,
        characterId: event.characterId,
        userId: event.userId,
        currentEmotionTag: event.emotionTag,
      );
      emit(MemoriesSearched(results));
    } catch (e) {
      emit(MemoryError("搜索记忆失败: $e"));
    }
  }

  Future<void> _onInsertMemory(
    InsertMemory event,
    Emitter<MemoryState> emit,
  ) async {
    try {
      await _emotionPool.insertMemory(
        input: event.input,
        output: event.output,
        characterId: event.characterId,
        userId: event.userId,
        emotionTag: event.emotionTag,
      );
    } catch (e) {
      emit(MemoryError("保存记忆失败: $e"));
    }
  }

  Future<void> _onDeleteMemory(
    DeleteMemory event,
    Emitter<MemoryState> emit,
  ) async {
    try {
      await _memoryRepo.deleteMemory(event.memoryId);
    } catch (e) {
      emit(MemoryError("删除记忆失败: $e"));
    }
  }

  Future<void> _onClearMemories(
    ClearMemories event,
    Emitter<MemoryState> emit,
  ) async {
    try {
      await _memoryRepo.clearMemories(event.characterId, event.userId);
      emit(MemoriesLoaded([], 0));
    } catch (e) {
      emit(MemoryError("清空记忆失败: $e"));
    }
  }
}
