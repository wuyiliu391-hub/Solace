part of 'story_play_bloc.dart';

abstract class StoryPlayEvent extends Equatable {
  const StoryPlayEvent();
  @override
  List<Object?> get props => [];
}

/// 打开书本，加载当前存档的剧情与场景
class StoryPlayOpen extends StoryPlayEvent {
  final String bookId;
  const StoryPlayOpen(this.bookId);
  @override
  List<Object?> get props => [bookId];
}

/// 玩家推进剧情（自由输入或选中分支）
class StoryPlayAdvance extends StoryPlayEvent {
  final String input; // 玩家输入/选择的分支文本
  const StoryPlayAdvance(this.input);
  @override
  List<Object?> get props => [input];
}

/// 切换叙事视角（主角/配角）
class StoryPlaySwitchNarrator extends StoryPlayEvent {
  final NarratorRole role;
  const StoryPlaySwitchNarrator(this.role);
  @override
  List<Object?> get props => [role];
}

/// 内部：流式增量到达
class StoryPlayStreamTick extends StoryPlayEvent {
  final String text;
  const StoryPlayStreamTick(this.text);
  @override
  List<Object?> get props => [text];
}

/// 新建存档
class StoryPlayCreateSave extends StoryPlayEvent {
  final String name;
  const StoryPlayCreateSave(this.name);
  @override
  List<Object?> get props => [name];
}

/// 读取存档
class StoryPlayLoadSave extends StoryPlayEvent {
  final String saveId;
  const StoryPlayLoadSave(this.saveId);
  @override
  List<Object?> get props => [saveId];
}
