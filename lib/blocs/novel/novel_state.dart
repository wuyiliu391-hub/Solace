part of 'novel_bloc.dart';

class NovelState extends Equatable {
  final List<Novel> novels;
  final Novel? currentNovel;
  final List<NovelChapter> chapters;
  final bool isLoading;
  final bool isLoadingChapters;
  final bool isGenerating;
  final String? generatingChapterId; // null 表示生成新章节，非 null 表示覆写该章节
  final String? error;
  final String? userId;

  const NovelState({
    this.novels = const [],
    this.currentNovel,
    this.chapters = const [],
    this.isLoading = false,
    this.isLoadingChapters = false,
    this.isGenerating = false,
    this.generatingChapterId,
    this.error,
    this.userId,
  });

  NovelState copyWith({
    List<Novel>? novels,
    Novel? currentNovel,
    List<NovelChapter>? chapters,
    bool? isLoading,
    bool? isLoadingChapters,
    bool? isGenerating,
    String? generatingChapterId,
    String? error,
    String? userId,
    bool clearError = false,
    bool clearGeneratingId = false,
  }) {
    return NovelState(
      novels: novels ?? this.novels,
      currentNovel: currentNovel ?? this.currentNovel,
      chapters: chapters ?? this.chapters,
      isLoading: isLoading ?? this.isLoading,
      isLoadingChapters: isLoadingChapters ?? this.isLoadingChapters,
      isGenerating: isGenerating ?? this.isGenerating,
      generatingChapterId: clearGeneratingId
          ? null
          : generatingChapterId ?? this.generatingChapterId,
      error: clearError ? null : error ?? this.error,
      userId: userId ?? this.userId,
    );
  }

  @override
  List<Object?> get props => [
        novels,
        currentNovel,
        chapters,
        isLoading,
        isLoadingChapters,
        isGenerating,
        generatingChapterId,
        error,
        userId,
      ];
}