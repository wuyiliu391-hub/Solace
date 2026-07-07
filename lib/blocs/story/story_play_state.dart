part of 'story_play_bloc.dart';

class StoryPlayState extends Equatable {
  final StoryBook? book;
  final List<StorySegment> segments;
  final StoryScene scene;
  final List<String> currentBranches; // 当前可选分支
  final bool isLoading;
  final bool isGenerating; // AI 正在续写
  final String streamingText; // 流式正文（未定稿）
  final String? error;

  const StoryPlayState({
    this.book,
    this.segments = const [],
    required this.scene,
    this.currentBranches = const [],
    this.isLoading = false,
    this.isGenerating = false,
    this.streamingText = '',
    this.error,
  });

  factory StoryPlayState.initial() => StoryPlayState(
        scene: StoryScene.initial('', ''),
      );

  StoryPlayState copyWith({
    StoryBook? book,
    List<StorySegment>? segments,
    StoryScene? scene,
    List<String>? currentBranches,
    bool? isLoading,
    bool? isGenerating,
    String? streamingText,
    String? error,
    bool clearError = false,
  }) {
    return StoryPlayState(
      book: book ?? this.book,
      segments: segments ?? this.segments,
      scene: scene ?? this.scene,
      currentBranches: currentBranches ?? this.currentBranches,
      isLoading: isLoading ?? this.isLoading,
      isGenerating: isGenerating ?? this.isGenerating,
      streamingText: streamingText ?? this.streamingText,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        book,
        segments,
        scene,
        currentBranches,
        isLoading,
        isGenerating,
        streamingText,
        error,
      ];
}
