part of 'story_bloc.dart';

abstract class StoryEvent extends Equatable {
  const StoryEvent();
  @override
  List<Object?> get props => [];
}

class StoryLoadBooks extends StoryEvent {
  final String userId;
  final bool includeArchived;
  const StoryLoadBooks(this.userId, {this.includeArchived = false});
  @override
  List<Object?> get props => [userId, includeArchived];
}

class StorySaveBook extends StoryEvent {
  final StoryBook book;
  const StorySaveBook(this.book);
  @override
  List<Object?> get props => [book];
}

class StoryDuplicateBook extends StoryEvent {
  final String bookId;
  const StoryDuplicateBook(this.bookId);
  @override
  List<Object?> get props => [bookId];
}

class StoryDeleteBook extends StoryEvent {
  final String bookId;
  final String userId;
  const StoryDeleteBook(this.bookId, this.userId);
  @override
  List<Object?> get props => [bookId, userId];
}

class StoryArchiveBook extends StoryEvent {
  final String bookId;
  final bool archived;
  const StoryArchiveBook(this.bookId, this.archived);
  @override
  List<Object?> get props => [bookId, archived];
}
