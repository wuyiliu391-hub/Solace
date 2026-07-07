import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/story_book.dart';
import '../../repositories/local_storage_repository.dart';

part 'story_event.dart';
part 'story_state.dart';

/// 书架管理 Bloc：加载/新建/更新/复制/删除/归档故事书
class StoryBloc extends Bloc<StoryEvent, StoryState> {
  final LocalStorageRepository _storage;
  final _uuid = const Uuid();

  StoryBloc(this._storage) : super(const StoryState()) {
    on<StoryLoadBooks>(_onLoadBooks);
    on<StorySaveBook>(_onSaveBook);
    on<StoryDuplicateBook>(_onDuplicateBook);
    on<StoryDeleteBook>(_onDeleteBook);
    on<StoryArchiveBook>(_onArchiveBook);
  }

  Future<void> _onLoadBooks(
    StoryLoadBooks event,
    Emitter<StoryState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final books = await _storage.getStoryBooks(event.userId,
          includeArchived: event.includeArchived);
      emit(state.copyWith(
        books: books,
        userId: event.userId,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: '加载书架失败: $e'));
    }
  }

  Future<void> _onSaveBook(
    StorySaveBook event,
    Emitter<StoryState> emit,
  ) async {
    try {
      await _storage.saveStoryBook(event.book);
      add(StoryLoadBooks(event.book.userId));
    } catch (e) {
      emit(state.copyWith(error: '保存失败: $e'));
    }
  }

  Future<void> _onDuplicateBook(
    StoryDuplicateBook event,
    Emitter<StoryState> emit,
  ) async {
    try {
      final src = await _storage.getStoryBook(event.bookId);
      if (src == null) return;
      final now = DateTime.now();
      final newId = _uuid.v4();
      final copy = src.copyWith(
        id: newId,
        title: '${src.title} 副本',
        currentSaveId: null,
        createdAt: now,
        updatedAt: now,
      );
      await _storage.saveStoryBook(copy);
      add(StoryLoadBooks(src.userId));
    } catch (e) {
      emit(state.copyWith(error: '复制失败: $e'));
    }
  }

  Future<void> _onDeleteBook(
    StoryDeleteBook event,
    Emitter<StoryState> emit,
  ) async {
    try {
      await _storage.deleteStoryBook(event.bookId);
      add(StoryLoadBooks(event.userId));
    } catch (e) {
      emit(state.copyWith(error: '删除失败: $e'));
    }
  }

  Future<void> _onArchiveBook(
    StoryArchiveBook event,
    Emitter<StoryState> emit,
  ) async {
    try {
      final book = await _storage.getStoryBook(event.bookId);
      if (book == null) return;
      await _storage.saveStoryBook(book.copyWith(
        isArchived: event.archived,
        updatedAt: DateTime.now(),
      ));
      add(StoryLoadBooks(book.userId));
    } catch (e) {
      emit(state.copyWith(error: '归档失败: $e'));
    }
  }
}
