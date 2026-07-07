part of 'story_bloc.dart';

class StoryState extends Equatable {
  final List<StoryBook> books;
  final String userId;
  final bool isLoading;
  final String? error;

  const StoryState({
    this.books = const [],
    this.userId = '',
    this.isLoading = false,
    this.error,
  });

  StoryState copyWith({
    List<StoryBook>? books,
    String? userId,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return StoryState(
      books: books ?? this.books,
      userId: userId ?? this.userId,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [books, userId, isLoading, error];
}
