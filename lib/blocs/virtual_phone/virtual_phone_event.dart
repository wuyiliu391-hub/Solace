part of 'virtual_phone_bloc.dart';

abstract class VirtualPhoneEvent extends Equatable {
  const VirtualPhoneEvent();
  @override
  List<Object?> get props => [];
}

/// 打开某个角色的虚拟手机：若不存在则建档，若为空则触发首次全量生成。
class VirtualPhoneOpened extends VirtualPhoneEvent {
  final AICharacter character;
  final String userNickname;
  final String userId;
  const VirtualPhoneOpened(this.character,
      {this.userNickname = '', this.userId = ''});
  @override
  List<Object?> get props => [character.id, userNickname, userId];
}

/// 生活推进（增量）：基于最近记忆/对话，往手机里追加少量新内容，不清空旧内容。
/// [auto] 为 true 时表示后台按阈值自动触发（静默，不打断用户）。
class VirtualPhoneAdvanced extends VirtualPhoneEvent {
  final bool auto;
  const VirtualPhoneAdvanced({this.auto = false});
  @override
  List<Object?> get props => [auto];
}

/// 彻底重建：清空后全量重新生成手机内容（二级菜单，谨慎使用）。
class VirtualPhoneRefreshed extends VirtualPhoneEvent {
  const VirtualPhoneRefreshed();
}
