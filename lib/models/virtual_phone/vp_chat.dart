import 'package:equatable/equatable.dart';

/// 虚拟手机 · 一条对话线（角色与某个联系人的聊天会话）
class VpChat extends Equatable {
  final String id;
  final String phoneId;
  final String characterId;

  /// 关联的联系人 id
  final String contactId;

  /// 会话标题（通常是联系人名）
  final String title;

  /// 最后一条消息预览
  final String lastPreview;

  final int orderIndex;

  const VpChat({
    required this.id,
    required this.phoneId,
    required this.characterId,
    required this.contactId,
    this.title = '',
    this.lastPreview = '',
    this.orderIndex = 0,
  });

  VpChat copyWith({String? lastPreview}) => VpChat(
        id: id,
        phoneId: phoneId,
        characterId: characterId,
        contactId: contactId,
        title: title,
        lastPreview: lastPreview ?? this.lastPreview,
        orderIndex: orderIndex,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'phoneId': phoneId,
        'characterId': characterId,
        'contactId': contactId,
        'title': title,
        'lastPreview': lastPreview,
        'orderIndex': orderIndex,
      };

  factory VpChat.fromMap(Map<String, dynamic> map) => VpChat(
        id: map['id'] as String,
        phoneId: map['phoneId'] as String,
        characterId: map['characterId'] as String,
        contactId: map['contactId'] as String? ?? '',
        title: map['title'] as String? ?? '',
        lastPreview: map['lastPreview'] as String? ?? '',
        orderIndex: (map['orderIndex'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, contactId, title];
}

/// 虚拟手机 · 一条聊天消息
class VpChatMessage extends Equatable {
  final String id;
  final String chatId;

  /// 是否是「手机主人（角色本人）」发出的。false 表示对方发的。
  final bool fromOwner;

  final String content;

  /// 虚构的发送时刻文本（如 "昨天 22:14"），只做展示
  final String timeLabel;

  final int orderIndex;

  const VpChatMessage({
    required this.id,
    required this.chatId,
    required this.fromOwner,
    required this.content,
    this.timeLabel = '',
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'chatId': chatId,
        'fromOwner': fromOwner ? 1 : 0,
        'content': content,
        'timeLabel': timeLabel,
        'orderIndex': orderIndex,
      };

  factory VpChatMessage.fromMap(Map<String, dynamic> map) => VpChatMessage(
        id: map['id'] as String,
        chatId: map['chatId'] as String,
        fromOwner: (map['fromOwner'] == 1 || map['fromOwner'] == true),
        content: map['content'] as String? ?? '',
        timeLabel: map['timeLabel'] as String? ?? '',
        orderIndex: (map['orderIndex'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, chatId, fromOwner, content, orderIndex];
}
