part of 'novel_bloc.dart';

abstract class NovelEvent extends Equatable {
  const NovelEvent();

  @override
  List<Object?> get props => [];
}

/// 加载书架列表
class NovelLoadList extends NovelEvent {
  final String userId;
  const NovelLoadList(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// 创建新小说
class NovelCreate extends NovelEvent {
  final Novel novel;
  const NovelCreate(this.novel);

  @override
  List<Object?> get props => [novel];
}

/// 更新小说元数据
class NovelUpdate extends NovelEvent {
  final Novel novel;
  const NovelUpdate(this.novel);

  @override
  List<Object?> get props => [novel];
}

/// 删除小说（含所有章节）
class NovelDelete extends NovelEvent {
  final String novelId;
  final String userId;
  const NovelDelete({required this.novelId, required this.userId});

  @override
  List<Object?> get props => [novelId, userId];
}

/// 归档 / 取消归档
class NovelArchive extends NovelEvent {
  final String novelId;
  final bool archived;
  const NovelArchive({required this.novelId, required this.archived});

  @override
  List<Object?> get props => [novelId, archived];
}

/// 加载某本小说的章节列表
class NovelLoadChapters extends NovelEvent {
  final String novelId;
  const NovelLoadChapters(this.novelId);

  @override
  List<Object?> get props => [novelId];
}

/// 新增空白章节
class NovelAddChapter extends NovelEvent {
  final String novelId;
  final String title;
  const NovelAddChapter({required this.novelId, required this.title});

  @override
  List<Object?> get props => [novelId, title];
}

/// 保存章节内容（手动编辑后调用）
class NovelUpdateChapter extends NovelEvent {
  final NovelChapter chapter;
  const NovelUpdateChapter(this.chapter);

  @override
  List<Object?> get props => [chapter];
}

/// 删除章节
class NovelDeleteChapter extends NovelEvent {
  final String chapterId;
  final String novelId;
  const NovelDeleteChapter({required this.chapterId, required this.novelId});

  @override
  List<Object?> get props => [chapterId, novelId];
}

/// 章节拖拽排序后提交新顺序
class NovelReorderChapters extends NovelEvent {
  final String novelId;
  final List<NovelChapter> chapters;
  const NovelReorderChapters({required this.novelId, required this.chapters});

  @override
  List<Object?> get props => [novelId, chapters];
}

/// AI 生成章节正文
///   - chapterId 为 null 时：新建章节
///   - chapterId 非 null 时：覆写现有章节
///   - targetWords：目标字数，默认 2000，用于 prompt 和 maxTokens 换算
class NovelGenerateChapter extends NovelEvent {
  final String? chapterId;
  final String? chapterTitle;
  final String? instruction;
  final int targetWords;
  const NovelGenerateChapter({
    this.chapterId,
    this.chapterTitle,
    this.instruction,
    this.targetWords = 2000,
  });

  @override
  List<Object?> get props => [chapterId, chapterTitle, instruction, targetWords];
}