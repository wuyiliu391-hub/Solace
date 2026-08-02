import 'package:equatable/equatable.dart';

/// 群聊聊天记录（分支）— 对标 SillyTavern group.chats[chatId]
class GroupChatBranch extends Equatable {
  final String branchId;
  final String groupId;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const GroupChatBranch({
    required this.branchId,
    required this.groupId,
    this.name = '默认聊天',
    required this.createdAt,
    this.updatedAt,
  });

  GroupChatBranch copyWith({
    String? branchId,
    String? groupId,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GroupChatBranch(
      branchId: branchId ?? this.branchId,
      groupId: groupId ?? this.groupId,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'branchId': branchId,
        'groupId': groupId,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory GroupChatBranch.fromMap(Map<String, dynamic> map) {
    final ca = map['createdAt'];
    final ua = map['updatedAt'];
    return GroupChatBranch(
      branchId: map['branchId'] as String,
      groupId: (map['groupId'] as String?) ?? '',
      name: (map['name'] as String?) ?? '默认聊天',
      createdAt: ca is String
          ? (DateTime.tryParse(ca) ?? DateTime.now())
          : DateTime.now(),
      updatedAt: ua is String ? DateTime.tryParse(ua) : null,
    );
  }

  @override
  List<Object?> get props => [branchId, groupId, name, createdAt, updatedAt];
}
