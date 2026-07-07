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
  const VirtualPhoneOpened(this.character, {this.userNickname = ''});
  @override
  List<Object?> get props => [character.id, userNickname];
}

/// 手动刷新：重新全量生成手机内容。
class VirtualPhoneRefreshed extends VirtualPhoneEvent {
  const VirtualPhoneRefreshed();
}
